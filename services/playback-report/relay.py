"""Sipflix playback diagnosis relay. No player URL or credential is persisted.

Event-driven, no unattended repair loop: at most two missing-source probes,
one healthy sibling probe, one Seerr create. Never delete/re-request a season,
change access, restart services, or claim a repair. HTTP reads independently
judge availability; Seerr readback judges submission. Ambiguous writes enter
review and are reconciled, never blindly retried. Customer rollout is separate.
"""
from __future__ import annotations

import argparse
from collections import OrderedDict, deque
import hashlib
import json
import os
import re
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookies import SimpleCookie
from pathlib import Path
from urllib.parse import urlsplit

import requests

ID = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
METHODS = {"directPlay", "directStream", "transcode", "unknown"}


class Fault(Exception):
    def __init__(self, code: str, status: int = 503):
        super().__init__(code)
        self.code, self.status = code, status


@dataclass(frozen=True)
class Reply:
    status: int
    body: bytes
    headers: dict

    def json(self):
        try:
            return json.loads(self.body)
        except (ValueError, UnicodeError):
            raise Fault("invalid_upstream_response") from None


class Transport:
    """Bounded bodies, timeouts, no redirects, no automatic POST retries."""
    def __init__(self):
        self.local = threading.local()

    @contextmanager
    def budget(self, seconds=30):
        self.local.deadline = time.monotonic() + seconds
        try:
            yield
        finally:
            self.local.deadline = None

    def remaining(self):
        deadline = getattr(self.local, 'deadline', None)
        left = deadline - time.monotonic() if deadline else 30
        if left <= 0:
            raise Fault('diagnosis_timeout')
        return max(0.1, left)

    def request(self, method, url, *, headers=None, params=None, payload=None,
                limit=1024 * 1024):
        try:
            with requests.request(method, url, headers=headers, params=params,
                                  json=payload, timeout=(min(3, self.remaining()), min(5, self.remaining())), stream=True,
                                  allow_redirects=False) as r:
                body = bytearray()
                for part in r.iter_content(chunk_size=min(limit, 4096)):
                    self.remaining()
                    body.extend(part)
                    if len(body) >= limit:
                        break
                return Reply(r.status_code, bytes(body[:limit]), dict(r.headers))
        except requests.RequestException:
            # Exception strings may contain token-bearing URLs. Never log them.
            raise Fault("upstream_unreachable") from None


@dataclass(frozen=True)
class Server:
    origin: str


class Store:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript("""
              CREATE TABLE IF NOT EXISTS incidents (
                key TEXT PRIMARY KEY, server TEXT NOT NULL, item TEXT NOT NULL,
                source TEXT NOT NULL, state TEXT NOT NULL, result TEXT,
                updated REAL NOT NULL, lease REAL NOT NULL DEFAULT 0,
                owner TEXT, issue INTEGER, marker TEXT NOT NULL,
                report_started REAL, created REAL NOT NULL
              );
              CREATE TABLE IF NOT EXISTS attempts (
                server TEXT NOT NULL, user TEXT NOT NULL, attempt TEXT NOT NULL,
                incident TEXT NOT NULL, created REAL NOT NULL, diagnostics TEXT,
                PRIMARY KEY(server,user,attempt)
              );
              CREATE INDEX IF NOT EXISTS attempts_rate ON attempts(server,user,created);
              CREATE INDEX IF NOT EXISTS incident_rate ON incidents(server,report_started);
              PRAGMA user_version=1;
            """)
            # Idempotent migration: development/previous databases may lack
            # diagnostics. Never rely on CREATE TABLE IF NOT EXISTS for drift.
            columns = {row[1] for row in db.execute('PRAGMA table_info(attempts)')}
            if 'diagnostics' not in columns:
                db.execute('ALTER TABLE attempts ADD COLUMN diagnostics TEXT')
        os.chmod(self.path, 0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def claim(self, key, event, user):
        now, owner = time.time(), uuid.uuid4().hex
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            old = db.execute("SELECT * FROM attempts WHERE server=? AND user=? AND attempt=?",
                             (event['server'], user, event['attemptId'])).fetchone()
            if old and old['incident'] != key:
                raise Fault('attempt_conflict', 409)
            if not old:
                count = db.execute("SELECT count(*) FROM attempts WHERE server=? AND user=? AND created>?",
                                   (event['server'], user, now - 600)).fetchone()[0]
                if count >= 10:
                    raise Fault('rate_limited', 429)
                diagnostic = {k: event.get(k) for k in ('playMethod', 'httpStatus', 'appVersion')}
                db.execute("INSERT INTO attempts(server,user,attempt,incident,created,diagnostics) VALUES(?,?,?,?,?,?)",
                           (event['server'], user, event['attemptId'], key, now, json.dumps(diagnostic)))
            row = db.execute("SELECT * FROM incidents WHERE key=?", (key,)).fetchone()
            if row:
                if row['lease'] > now:
                    return None, result('checking', 'pending')
                # Report submissions survive retries/restarts. Always reconcile
                # ambiguous writes; never turn an expired lease into another POST.
                if row['state'] in ('submitting', 'uncertain'):
                    db.execute("UPDATE incidents SET lease=?,owner=? WHERE key=?",
                               (now + 120, owner, key))
                    return owner, dict(row)
                if row['result'] and now - row['updated'] < 300:
                    return None, json.loads(row['result'])
                db.execute("UPDATE incidents SET lease=?,owner=? WHERE key=?",
                           (now + 120, owner, key))
                return owner, dict(row)
            marker = 'sipflix-' + key[:24]
            db.execute("INSERT INTO incidents(key,server,item,source,state,updated,lease,owner,marker,created) VALUES(?,?,?,?,?,?,?,?,?,?)",
                       (key, event['server'], event['itemId'], event['mediaSourceId'],
                        'checking', now, now + 120, owner, marker, now))
            return owner, {'marker': marker, 'issue': None, 'state': 'checking'}

    def begin_submit(self, key, owner):
        now = time.time()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            count = db.execute('SELECT count(*) FROM incidents WHERE server=(SELECT server FROM incidents WHERE key=?) AND report_started>?',
                               (key, now - 600)).fetchone()[0]
            if count >= 5:
                raise Fault('outage_circuit_open')
            changed = db.execute("UPDATE incidents SET state='submitting',report_started=?,updated=? WHERE key=? AND owner=? AND lease>?",
                                 (now, now, key, owner, now)).rowcount
            if changed != 1:
                raise Fault('lease_expired')

    def finish(self, key, owner, value, state=None):
        with self.connect() as db:
            db.execute('UPDATE incidents SET state=?,result=?,updated=?,lease=0,issue=COALESCE(?,issue) WHERE key=? AND owner=?',
                       (state or value['reportStatus'], json.dumps(value), time.time(),
                        value.get('issueId'), key, owner))


def result(diagnosis, report='not_sent', issue=None):
    return {'diagnosis': diagnosis, 'reportStatus': report,
            **({'issueId': issue} if issue else {})}


def validate_event(value):
    if not isinstance(value, dict):
        raise Fault('invalid_event', 400)
    allowed = {'server', 'userId', 'itemId', 'mediaSourceId', 'attemptId',
               'playMethod', 'httpStatus', 'appVersion'}
    if set(value) - allowed:
        raise Fault('invalid_event', 400)
    for field in ('server', 'userId', 'itemId', 'mediaSourceId', 'attemptId'):
        if not isinstance(value.get(field), str) or not ID.fullmatch(value[field]):
            raise Fault('invalid_event', 400)
    if value.get('playMethod') not in METHODS:
        raise Fault('invalid_event', 400)
    status = value.get('httpStatus', -1)
    if type(status) is not int or not (status == -1 or 100 <= status <= 599):
        raise Fault('invalid_event', 400)
    version = value.get('appVersion', 'unknown')
    if not isinstance(version, str) or not re.fullmatch(r'[A-Za-z0-9.+_-]{1,64}', version):
        raise Fault('invalid_event', 400)
    return value


class Emby:
    def __init__(self, transport, server, token, user):
        self.transport, self.server, self.user = transport, server, user
        self.headers = {'X-Emby-Token': token, 'Accept': 'application/json'}

    def get(self, path, params=None, limit=1024 * 1024):
        r = self.transport.request('GET', self.server.origin.rstrip('/') + path,
                                   headers=self.headers, params=params, limit=limit)
        if r.status in (401, 403):
            raise Fault('access_denied', 401)
        return r

    def authenticate(self):
        # Emby enforces user-token access on this endpoint; no admin key is used.
        r = self.get('/Users/' + self.user)
        if r.status != 200:
            raise Fault('authentication_unavailable')
        user = r.json()
        if user.get('Id') != self.user or user.get('Policy', {}).get('IsDisabled'):
            raise Fault('access_denied', 401)
        if user.get('Policy', {}).get('EnableMediaPlayback') is False:
            raise Fault('access_denied', 403)
        return user

    def item(self, item_id):
        r = self.get(f'/Users/{self.user}/Items/{item_id}',
                     {'Fields': 'MediaSources,ProviderIds,Path'})
        if r.status == 404:
            raise Fault('item_unavailable', 404)
        if r.status != 200:
            raise Fault('metadata_unavailable')
        value = r.json()
        if str(value.get('Id')) != item_id:
            raise Fault('item_mismatch')
        return value

    def probe(self, item_id, source):
        container = source.get('Container', '')
        path = source.get('Path', '')
        # Never probe remote/STRM sources, playlists or a client-supplied URL.
        if (source.get('Protocol', '').lower() != 'file' or
            not isinstance(path, str) or not path.startswith('/') or
            not re.fullmatch(r'[a-zA-Z0-9]{1,10}', container) or
            container.lower() in ('strm', 'm3u', 'm3u8')):
            return 'unknown'
        headers = {**self.headers, 'Range': 'bytes=0-1023', 'Accept': '*/*'}
        r = self.transport.request('GET', self.server.origin.rstrip('/') +
                                   f'/Videos/{item_id}/stream.{container}',
                                   headers=headers,
                                   params={'Static': 'true', 'MediaSourceId': source['Id']},
                                   limit=4096)
        mime = r.headers.get('Content-Type', r.headers.get('content-type', '')).lower()
        # A 200 HTML login/error page is not a readable video.
        if r.status in (200, 206) and len(r.body) >= 1024 and (
                mime.startswith('video/') or 'octet-stream' in mime):
            return 'readable'
        if r.status in (401, 403):
            raise Fault('access_denied', 401)
        text = r.body.decode('utf-8', 'replace')
        missing = re.search(r'could not (?:be found|find (?:file|a part of the path))|no such file', text, re.I)
        # Must name the exact origin file. A route/segment/proxy 404 is insufficient.
        if r.status in (404, 500) and path in text and missing:
            return 'missing'
        return 'unknown'

    def diagnose(self, item, source):
        first = self.probe(str(item['Id']), source)
        if first != 'missing':
            return first
        # Use a nearby file on the same storage directory as an independent
        # control. If the mount is down or control unavailable, fail closed.
        parent = item.get('ParentId')
        if not parent or not ID.fullmatch(str(parent)):
            return 'unknown'
        r = self.get(f'/Users/{self.user}/Items',
                     {'ParentId': parent, 'Limit': 6, 'Fields': 'MediaSources,Path',
                      'Recursive': 'false'})
        if r.status != 200:
            return 'unknown'
        folder = os.path.dirname(source['Path'])
        control = None
        for sibling in r.json().get('Items', []):
            sibling_id = str(sibling.get('Id', ''))
            if sibling_id == str(item['Id']) or not ID.fullmatch(sibling_id):
                continue
            for candidate in sibling.get('MediaSources', []):
                if (os.path.dirname(candidate.get('Path', '')) == folder and
                        ID.fullmatch(str(candidate.get('Id', '')))):
                    control = (sibling_id, candidate)
                    break
            if control:
                break
        if not control or self.probe(*control) != 'readable':
            return 'unknown'
        return 'missing' if self.probe(str(item['Id']), source) == 'missing' else 'unknown'


class Seerr:
    """Fresh dedicated service login; protected browser state is a fallback.

    Re-read credentials and verify /auth/me for every event, not at process
    startup. Expiry blocks submission explicitly; never retry a write on 401.
    """
    def __init__(self, transport, origin, state_file, expected_user_id, credentials_file=None):
        self.transport, self.origin = transport, origin.rstrip('/')
        self.state_file, self.expected_user_id = state_file, expected_user_id
        self.credentials_file = credentials_file

    def authenticate(self):
        if self.credentials_file:
            try:
                path = Path(self.credentials_file)
                if path.stat().st_mode & 0o077:
                    raise Fault('report_auth_configuration')
                credentials = json.loads(path.read_text())
                username, password = credentials['username'], credentials['password']
                if not isinstance(username, str) or not isinstance(password, str):
                    raise Fault('report_auth_configuration')
            except (OSError, ValueError, KeyError, TypeError):
                raise Fault('report_auth_configuration') from None
            # Verified against this provider fork's live login JS. Only our
            # dedicated Emby service identity is configured here, never a viewer.
            login = self.transport.request('POST', self.origin + '/api/v1/auth/media-server/provider/emby/login',
                                           payload={'username': username, 'password': password})
            if login.status != 200:
                raise Fault('report_auth_expired')
            cookie = SimpleCookie()
            cookie.load(login.headers.get('Set-Cookie', login.headers.get('set-cookie', '')))
            if 'connect.sid' not in cookie:
                raise Fault('report_auth_expired')
            value = cookie['connect.sid'].value
            return self.verify_identity(value)
        try:
            path = Path(self.state_file)
            if path.stat().st_mode & 0o077:
                raise Fault('report_auth_configuration')
            data = json.loads(path.read_text())
            host = urlsplit(self.origin).hostname
            cookies = [c for c in data['cookies'] if c['name'] == 'connect.sid'
                       and c['domain'].lstrip('.') == host
                       and (c.get('expires', -1) == -1 or c['expires'] > time.time())]
            if len(cookies) != 1:
                raise Fault('report_auth_expired')
            value = cookies[0]['value']
            if '\r' in value or '\n' in value:
                raise Fault('report_auth_configuration')
        except (OSError, ValueError, KeyError, TypeError):
            raise Fault('report_auth_configuration') from None
        return self.verify_identity(value)

    def verify_identity(self, value):
        headers = {'Cookie': 'connect.sid=' + value, 'Accept': 'application/json'}
        r = self.transport.request('GET', self.origin + '/api/v1/auth/me', headers=headers)
        if r.status != 200:
            raise Fault('report_auth_expired')
        if str(r.json().get('id')) != str(self.expected_user_id):
            raise Fault('report_identity_mismatch')
        return headers

    def get(self, path, headers, params=None):
        r = self.transport.request('GET', self.origin + '/api/v1' + path,
                                   headers=headers, params=params)
        if r.status in (401, 403):
            raise Fault('report_auth_expired')
        if r.status != 200:
            raise Fault('report_lookup_failed')
        return r.json()

    @staticmethod
    def matches(issue, media_id, season, episode):
        return (type(issue.get('id')) is int and issue['id'] > 0 and
                issue.get('media', {}).get('id') == media_id and
                issue.get('problemSeason', 0) == season and
                issue.get('problemEpisode', 0) == episode and
                issue.get('issueType') == 1)

    def media(self, headers, kind, tmdb):
        media = self.get(f'/{kind}/{tmdb}', headers).get('mediaInfo') or {}
        if (type(media.get('id')) is not int or media['id'] <= 0 or
                str(media.get('tmdbId')) != str(tmdb) or
                media.get('mediaType') != kind):
            raise Fault('mapping_needs_review')
        return media['id']

    def find(self, headers, media_id, season, episode, marker, issue_id=None):
        if issue_id:
            issue = self.get('/issue/' + str(issue_id), headers)
            if self.matches(issue, media_id, season, episode):
                return issue
            raise Fault('report_readback_mismatch')
        # Bounded pagination: if history exceeds cap, stop rather than guessing.
        existing_open = None
        for skip in (0, 100, 200):
            page = self.get('/issue', headers, {'take': 100, 'skip': skip, 'filter': 'all'})
            rows = page.get('results')
            if not isinstance(rows, list):
                raise Fault('report_lookup_failed')
            for row in rows:
                if not self.matches(row, media_id, season, episode):
                    continue
                full = self.get('/issue/' + str(row['id']), headers)
                text = json.dumps(full.get('comments', []))
                # A pre-existing open episode issue blocks a duplicate even
                # without our marker. Review quality conflicts instead of regrab.
                if marker in text:
                    return full
                if full.get('status') == 1:
                    existing_open = full
            total = page.get('pageInfo', {}).get('results')
            if len(rows) < 100 or (isinstance(total, int) and skip + len(rows) >= total):
                return existing_open
        if existing_open:
            return existing_open
        raise Fault('report_history_needs_review')

    def create(self, headers, payload):
        r = self.transport.request('POST', self.origin + '/api/v1/issue',
                                   headers=headers, payload=payload)
        if r.status not in (200, 201):
            # Even a 500 may have committed an issue before proxy failure.
            raise Fault('report_submission_uncertain')
        return r.json()


class Admission:
    """Bound upstream authentication work before trusting a viewer identity."""
    def __init__(self):
        self.lock = threading.Lock()
        self.global_calls = deque()
        self.tokens = OrderedDict()

    def allow(self, token):
        now = time.monotonic()
        fingerprint = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            while self.global_calls and self.global_calls[0] < now - 60:
                self.global_calls.popleft()
            calls = self.tokens.setdefault(fingerprint, deque())
            self.tokens.move_to_end(fingerprint)
            while calls and calls[0] < now - 60:
                calls.popleft()
            if len(self.global_calls) >= 120 or len(calls) >= 20:
                raise Fault('rate_limited', 429)
            self.global_calls.append(now)
            calls.append(now)
            while len(self.tokens) > 512:
                self.tokens.popitem(last=False)


class Relay:
    def __init__(self, servers, store, transport, seerr=None):
        self.servers, self.store, self.transport, self.seerr = servers, store, transport, seerr
        self.admission = Admission()

    def report(self, event, token):
        with self.transport.budget():
            return self._report(event, token)

    def _report(self, event, token):
        event = validate_event(event)
        if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9._~-]{16,512}', token):
            raise Fault('access_denied', 401)
        server = self.servers.get(event['server'])
        if server is None:
            raise Fault('unknown_server', 400)
        self.admission.allow(token)
        emby = Emby(self.transport, server, token, event['userId'])
        user = emby.authenticate()
        item = emby.item(event['itemId'])
        if item.get('Type') not in ('Episode', 'Movie') or item.get('IsVirtualItem'):
            return result('unsupported')
        sources = [s for s in item.get('MediaSources', [])
                   if str(s.get('Id')) == event['mediaSourceId']]
        if len(sources) != 1:
            return result('unknown')
        source = sources[0]
        fingerprint = json.dumps([event['server'], event['itemId'], source.get('Id'),
                                  source.get('Path'), source.get('Size'), source.get('DateModified')])
        key = hashlib.sha256(fingerprint.encode()).hexdigest()
        owner, previous = self.store.claim(key, event, event['userId'])
        if owner is None:
            return previous
        marker = previous['marker']
        uncertain = previous['state'] in ('submitting', 'uncertain')
        diagnosis = 'unknown'
        try:
            diagnosis = emby.diagnose(item, source)
            if diagnosis != 'missing':
                value = result('source_readable' if diagnosis == 'readable' else 'unknown')
                self.store.finish(key, owner, value, 'uncertain' if uncertain else None)
                return value
            if self.seerr is None:
                value = result('missing', 'unavailable')
                self.store.finish(key, owner, value, 'uncertain' if uncertain else None)
                return value
            headers = self.seerr.authenticate()
            kind = 'tv' if item['Type'] == 'Episode' else 'movie'
            season, episode = 0, 0
            title_item = item
            if kind == 'tv':
                series_id = str(item.get('SeriesId', ''))
                if not ID.fullmatch(series_id):
                    raise Fault('mapping_needs_review')
                title_item = emby.item(series_id)
                season, episode = item.get('ParentIndexNumber'), item.get('IndexNumber')
                if type(season) is not int or type(episode) is not int or season < 0 or episode <= 0:
                    raise Fault('mapping_needs_review')
            tmdb = str(title_item.get('ProviderIds', {}).get('Tmdb', ''))
            if not tmdb.isdigit() or int(tmdb) <= 0:
                raise Fault('mapping_needs_review')
            media_id = self.seerr.media(headers, kind, tmdb)
            issue = self.seerr.find(headers, media_id, season, episode, marker, previous.get('issue'))
            if issue is None:
                if uncertain:
                    raise Fault('report_submission_uncertain')
                self.store.begin_submit(key, owner)
                uncertain = True
                # Metadata is server-derived. Basename + quality identify the
                # affected copy without exposing storage layout or auth headers.
                filename = os.path.basename(source.get('Path', ''))
                note = (f'[{marker}] Automatic Moonfin playback report. '
                        f'Server {event["server"]}; Emby item {event["itemId"]}; '
                        f'source {event["mediaSourceId"]}; file {filename}. '
                        f'Origin twice explicitly reports this file missing; a sibling file '
                        f'in the same directory reads successfully. Please replace the affected copy. '
                        f'Viewer {user.get("Name", event["userId"])}; '
                        f'app {event.get("appVersion", "unknown")}; '
                        f'playback {event["playMethod"]}; HTTP {event.get("httpStatus", -1)}. '
                        f'UTC {time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}.')
                issue = self.seerr.create(headers, {'issueType': 1, 'mediaId': media_id,
                                                    'problemSeason': season, 'problemEpisode': episode,
                                                    'message': note})
                if not self.seerr.matches(issue, media_id, season, episode):
                    raise Fault('report_readback_mismatch')
                issue = self.seerr.find(headers, media_id, season, episode, marker, issue['id'])
            marker_matches = marker in json.dumps(issue.get('comments', []))
            if issue.get('status') != 1 or not marker_matches:
                value = result('missing', 'needs_review', issue['id'])
            else:
                status = 'replacement_requested' if issue.get('arrProxyStatus') == 'submitted' else 'reported'
                value = result('missing', status, issue['id'])
            self.store.finish(key, owner, value)
            return value
        except Fault as fault:
            report = ('uncertain' if uncertain else
                      'auth_required' if fault.code.startswith('report_auth') or fault.code == 'report_identity_mismatch' else
                      'needs_review' if fault.code in ('mapping_needs_review', 'outage_circuit_open', 'report_history_needs_review') else
                      'unavailable')
            value = result('access_denied' if fault.code == 'access_denied' else 'missing' if diagnosis == 'missing' else 'unknown', report)
            # Internal reason supports triage without exposing upstream messages.
            value['reason'] = fault.code
            self.store.finish(key, owner, value, 'uncertain' if uncertain else None)
            return value
        except Exception:
            self.store.finish(key, owner, result('unknown', 'uncertain' if uncertain else 'unavailable'),
                              'uncertain' if uncertain else 'unavailable')
            raise Fault('internal_error') from None


class HTTPServer(ThreadingHTTPServer):
    # Bound active sockets/threads BEFORE spawn; excess clients get a closed
    # connection and retain an honest not-confirmed result on the player.
    daemon_threads = True
    def __init__(self, address, relay):
        self.relay = relay
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(address, Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(8)

    def log_message(self, *_):
        pass  # Don't log headers, query strings, identities or tokens.

    def send_json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.send_json(200 if self.path == '/healthz' else 404,
                       {'service': 'sipflix-playback-report', 'schema': 1} if self.path == '/healthz' else {'error': 'not_found'})

    def do_POST(self):
        try:
            if self.path != '/v1/playback-failures':
                raise Fault('not_found', 404)
            if self.headers.get('Transfer-Encoding') or self.headers.get_content_type() != 'application/json':
                raise Fault('invalid_body', 400)
            try:
                length = int(self.headers.get('Content-Length', '0'))
            except ValueError:
                raise Fault('invalid_body', 400) from None
            if not 1 <= length <= 4096:
                raise Fault('invalid_body', 413)
            auth = self.headers.get('Authorization', '')
            if not auth.startswith('Bearer '):
                raise Fault('access_denied', 401)
            body = self.rfile.read(length)
            if len(body) != length:
                raise Fault('invalid_body', 400)
            try:
                event = json.loads(body)
            except ValueError:
                raise Fault('invalid_body', 400) from None
            value = self.server.relay.report(event, auth[7:])
            self.send_json(200, value)
        except Fault as fault:
            self.send_json(fault.status, {'error': fault.code})
        except (OSError, TimeoutError):
            return
        except Exception:
            self.send_json(500, {'error': 'internal_error'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    servers = {}
    for key, value in config['servers'].items():
        url = urlsplit(value['origin'])
        if not ID.fullmatch(key) or url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise SystemExit('Invalid server configuration')
        servers[key] = Server(value['origin'])
    seerr_url = config.get('seerrOrigin', '')
    seerr_parts = urlsplit(seerr_url)
    if seerr_url and (seerr_parts.scheme != 'https' or not seerr_parts.hostname or seerr_parts.username or seerr_parts.password or seerr_parts.query or seerr_parts.fragment):
        raise SystemExit('Seerr must use HTTPS')
    transport = Transport()
    seerr = Seerr(transport, seerr_url, config.get('seerrSessionFile'), config['seerrUserId'], config.get('seerrCredentialsFile')) if seerr_url else None
    # Override must be resolved before any DB connection is opened.
    store = Store(os.environ.get('SIPFLIX_REPORT_DB', config['database']))
    HTTPServer(('127.0.0.1', config.get('port', 8431)), Relay(servers, store, transport, seerr)).serve_forever()


if __name__ == '__main__':
    main()
