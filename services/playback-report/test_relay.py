import json
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
from urllib.parse import urlsplit

from relay import Emby, Fault, HTTPServer, Relay, Reply, Seerr, Server, Store, Transport

TOKEN = 'viewer-token-000000000000'
EVENT = dict(server='alphav2', userId='viewer', itemId='6', mediaSourceId='src6',
             attemptId='attempt-1', playMethod='transcode', httpStatus=500, appVersion='test.1')
SOURCE = dict(Id='src6', Protocol='File', Container='mkv', Path='/library/series/Season 1/e6.mkv', Size=12345)
ITEM = dict(Id='6', Type='Episode', ParentId='season1', SeriesId='series',
            ParentIndexNumber=1, IndexNumber=6, MediaSources=[SOURCE])
CONTROL = dict(Id='5', MediaSources=[{**SOURCE, 'Id': 'src5', 'Path': '/library/series/Season 1/e5.mkv'}])
MEDIA = dict(id=107231, tmdbId=95350, mediaType='tv')


def reply(status, body, headers=None):
    return Reply(status, json.dumps(body).encode() if not isinstance(body, bytes) else body,
                 headers or {'Content-Type': 'application/json'})


class FakeTransport(Transport):
    def __init__(self):
        super().__init__()
        self.calls = []
        self.source = 'missing'
        self.control = 'readable'
        self.issue = None
        self.posts = 0
        self.auth = True
        self.post_timeout = False
        self.bad_readback = False
        self.block = None
        self.entered = threading.Event()

    def request(self, method, url, *, headers=None, params=None, payload=None, limit=1024*1024):
        self.calls.append((method, urlsplit(url).path, params))
        path = urlsplit(url).path
        if path == '/Users/viewer':
            if headers.get('X-Emby-Token') != TOKEN:
                return reply(401, {})
            return reply(200, {'Id': 'viewer', 'Name': 'Example Viewer', 'Policy': {}})
        if path == '/Users/viewer/Items/6':
            return reply(200, ITEM)
        if path == '/Users/viewer/Items/series':
            return reply(200, {'Id': 'series', 'Type': 'Series', 'ProviderIds': {'Tmdb': '95350'}})
        if path == '/Users/viewer/Items':
            return reply(200, {'Items': [ITEM, CONTROL]})
        if path.startswith('/Videos/'):
            assert params['Static'] == 'true'
            assert headers['Range'] == 'bytes=0-1023'
            assert limit == 4096
            status = self.source if '/6/' in path else self.control
            if self.block and '/6/' in path:
                self.entered.set()
                self.block.wait(timeout=3)
            if status == 'missing':
                return reply(404, f"File '{SOURCE['Path']}' could not be found".encode())
            if status == 'readable':
                return reply(206, b'video' * 300, {'Content-Type': 'video/x-matroska'})
            if status == 'segment':
                return reply(404, b'Segment 123.ts could not be found')
            if status == 'html':
                return reply(200, b'<html>login</html>' * 100, {'Content-Type': 'text/html'})
            if status == 'timeout':
                raise Fault('upstream_unreachable')
            return reply(500, b'ffmpeg failed')
        if path == '/api/v1/auth/me':
            return reply(200 if self.auth else 401, {'id': 42})
        if path == '/api/v1/auth/media-server/provider/emby/login':
            assert payload == {'username': 'service', 'password': 'secret-test'}
            return reply(200, {'id': 42}, {'Set-Cookie': 'connect.sid=test-session; Path=/; HttpOnly'})
        if path == '/api/v1/tv/95350':
            return reply(200, {'mediaInfo': MEDIA})
        if path == '/api/v1/issue' and method == 'GET':
            return reply(200, {'results': [self.issue] if self.issue else [], 'pageInfo': {'results': 1 if self.issue else 0}})
        if path == '/api/v1/issue/70':
            return reply(200, {**self.issue, 'media': {'id': 1}} if self.bad_readback else self.issue)
        if path == '/api/v1/issue' and method == 'POST':
            self.posts += 1
            assert payload['mediaId'] == MEDIA['id'], 'TMDB ID is not issue mediaId'
            self.issue = {'id': 70, 'media': MEDIA, 'status': 1, 'issueType': 1,
                          'problemSeason': payload['problemSeason'], 'problemEpisode': payload['problemEpisode'],
                          'arrProxyStatus': 'submitted', 'comments': [{'message': payload['message']}]}
            if self.post_timeout:
                raise Fault('upstream_unreachable')
            return reply(201, self.issue)
        raise AssertionError((method, path, params))


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sipflix-report-', dir='/tmp')
        self.addCleanup(self.tmp.cleanup)
        path = Path(self.tmp.name)
        assert str(path).startswith('/tmp/')
        self.db = path / 'test.sqlite'
        self.store = Store(self.db)
        state = path / 'session.json'
        state.write_text(json.dumps({'cookies': [{'name': 'connect.sid', 'value': 'test-session',
                                                  'domain': 'seerr.example', 'expires': -1}]}))
        state.chmod(0o600)
        self.transport = FakeTransport()
        self.seerr = Seerr(self.transport, 'https://seerr.example', state, 42)
        self.relay = Relay({'alphav2': Server('https://origin.example')}, self.store, self.transport, self.seerr)

    def run_report(self, **changes):
        return self.relay.report({**EVENT, **changes}, TOKEN)

    def test_missing_source_reports_once_and_readbacks_correct_episode(self):
        value = self.run_report()
        self.assertEqual(value, dict(diagnosis='missing', reportStatus='replacement_requested', issueId=70))
        self.assertEqual(self.transport.posts, 1)
        self.assertEqual(self.run_report(), value)
        self.assertEqual(self.run_report(attemptId='attempt-2'), value)
        self.assertEqual(self.transport.posts, 1)
        with self.store.connect() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM attempts').fetchone()[0], 2)
        self.assertNotIn(TOKEN.encode(), self.db.read_bytes())
        self.assertNotIn(b'/library/', self.db.read_bytes())

    def test_hls_404_does_not_report_a_missing_file(self):
        self.transport.source = 'segment'
        self.assertEqual(self.run_report()['diagnosis'], 'unknown')
        self.assertEqual(self.transport.posts, 0)

    def test_source_readable_but_transcode_failed_does_not_regrab(self):
        self.transport.source = 'readable'
        self.assertEqual(self.run_report()['diagnosis'], 'source_readable')
        self.assertEqual(self.transport.posts, 0)

    def test_storage_outage_fails_closed(self):
        self.transport.control = 'timeout'
        self.assertEqual(self.run_report()['diagnosis'], 'unknown')
        self.assertEqual(self.transport.posts, 0)

    def test_html_200_is_not_a_healthy_control(self):
        self.transport.control = 'html'
        self.assertEqual(self.run_report()['diagnosis'], 'unknown')
        self.assertEqual(self.transport.posts, 0)

    def test_expired_seerr_session_is_not_success(self):
        self.transport.auth = False
        self.assertEqual(self.run_report()['reportStatus'], 'auth_required')
        self.assertEqual(self.transport.posts, 0)

    def test_wrong_service_identity_blocks_submission(self):
        self.seerr.expected_user_id = 100
        self.assertEqual(self.run_report()['reportStatus'], 'auth_required')
        self.assertEqual(self.transport.posts, 0)

    def test_ambiguous_post_reconciles_after_restart_without_second_post(self):
        self.transport.post_timeout = True
        self.assertEqual(self.run_report()['reportStatus'], 'uncertain')
        # A restart loses all process memory but retains the durable marker.
        self.relay.store = Store(self.db)
        self.assertEqual(self.run_report(attemptId='attempt-2')['issueId'], 70)
        self.assertEqual(self.transport.posts, 1)

    def test_ambiguous_post_without_visible_issue_is_never_reposted(self):
        self.transport.post_timeout = True
        self.run_report()
        self.transport.issue = None
        self.assertEqual(self.run_report(attemptId='attempt-2')['reportStatus'], 'uncertain')
        self.assertEqual(self.transport.posts, 1)

    def test_readback_wrong_media_is_not_reported_success(self):
        self.transport.bad_readback = True
        self.assertEqual(self.run_report()['reportStatus'], 'uncertain')
        self.assertEqual(self.transport.posts, 1)

    def test_existing_manual_issue_blocks_duplicate(self):
        self.transport.issue = {'id': 70, 'media': MEDIA, 'status': 1, 'issueType': 1,
                                'problemSeason': 1, 'problemEpisode': 6,
                                'arrProxyStatus': 'submitted', 'comments': [{'message': 'manual report'}]}
        self.assertEqual(self.run_report()['issueId'], 70)
        self.assertEqual(self.transport.posts, 0)

    def test_concurrent_requests_have_one_writer(self):
        self.transport.block = threading.Event()
        with ThreadPoolExecutor(max_workers=2) as executor:
            one = executor.submit(self.run_report)
            self.assertTrue(self.transport.entered.wait(2))
            two = executor.submit(self.run_report, attemptId='attempt-2')
            self.assertEqual(two.result()['reportStatus'], 'pending')
            self.transport.block.set()
            self.assertEqual(one.result()['issueId'], 70)
        self.assertEqual(self.transport.posts, 1)

    def test_global_circuit_breaker_stops_replacement_storm(self):
        import time
        with self.store.connect() as db:
            for n in range(5):
                db.execute('INSERT INTO incidents(key,server,item,source,state,updated,marker,report_started,created) VALUES(?,?,?,?,?,?,?,?,?)',
                           (str(n), 'alphav2', str(n), 's', 'reported', time.time(), str(n), time.time(), time.time()))
        self.assertEqual(self.run_report()['reportStatus'], 'needs_review')
        self.assertEqual(self.transport.posts, 0)

    def test_rate_limit_counts_unique_attempts_not_polling(self):
        for n in range(10):
            self.run_report(attemptId=str(n))
        self.run_report(attemptId='0')
        with self.assertRaises(Fault) as exc:
            self.run_report(attemptId='11')
        self.assertEqual(exc.exception.status, 429)

    def test_untrusted_urls_and_invalid_tokens_never_reach_origin(self):
        with self.assertRaises(Fault):
            self.run_report(url='http://localhost/secrets')
        with self.assertRaises(Fault):
            self.run_report(itemId='../../secret')
        with self.assertRaises(Fault):
            self.relay.report(EVENT, 'short')
        self.assertEqual(self.transport.calls, [])

    def test_invalid_account_token_cannot_probe_or_report(self):
        with self.assertRaises(Fault) as exc:
            self.relay.report(EVENT, 'invalid-token-0000000000')
        self.assertEqual(exc.exception.status, 401)
        self.assertEqual(len(self.transport.calls), 1)

    def test_media_source_must_belong_to_accessible_item(self):
        self.assertEqual(self.run_report(mediaSourceId='private-source')['diagnosis'], 'unknown')
        self.assertFalse(any(c[1].startswith('/Videos/') for c in self.transport.calls))

    def test_fresh_service_login_each_report_checks_identity(self):
        credentials = Path(self.tmp.name) / 'credentials.json'
        credentials.write_text(json.dumps({'username': 'service', 'password': 'secret-test'}))
        credentials.chmod(0o600)
        self.seerr.credentials_file = credentials
        self.assertEqual(self.run_report()['issueId'], 70)
        self.assertTrue(any('/provider/emby/login' in c[1] for c in self.transport.calls))
        self.assertNotIn(b'secret-test', self.db.read_bytes())

    def test_schema_migration_keeps_old_incidents(self):
        import sqlite3
        old = Path(self.tmp.name) / 'old.sqlite'
        with sqlite3.connect(old) as db:
            db.execute('CREATE TABLE attempts(server TEXT,user TEXT,attempt TEXT,incident TEXT,created REAL,PRIMARY KEY(server,user,attempt))')
            db.execute("INSERT INTO attempts VALUES('alphav2','viewer','old','incident',123)")
        migrated = Store(old)
        Store(old)  # repeated migration is harmless
        with migrated.connect() as db:
            row = db.execute('SELECT * FROM attempts').fetchone()
            self.assertEqual(row['attempt'], 'old')
            self.assertIsNone(row['diagnostics'])

    def test_missing_seerr_media_row_never_creates_season_request(self):
        with patch.object(self.seerr, 'media', side_effect=Fault('mapping_needs_review')):
            self.assertEqual(self.run_report()['reportStatus'], 'needs_review')
        self.assertEqual(self.transport.posts, 0)
        self.assertFalse(any('/request' in c[1] for c in self.transport.calls))

    def test_regrabbing_failed_is_reported_but_not_replacement_requested(self):
        original = self.seerr.create
        def create(headers, payload):
            value = original(headers, payload)
            self.transport.issue['arrProxyStatus'] = 'failed'
            return value
        with patch.object(self.seerr, 'create', side_effect=create):
            self.assertEqual(self.run_report()['reportStatus'], 'reported')

    def test_resolved_old_issue_never_promises_new_replacement(self):
        self.run_report()
        self.transport.issue['status'] = 3
        with self.store.connect() as db:
            db.execute('UPDATE incidents SET updated=0')
        self.assertEqual(self.run_report(attemptId='attempt-2')['reportStatus'], 'needs_review')
        self.assertEqual(self.transport.posts, 1)

    def test_existing_report_for_other_copy_requires_review(self):
        self.transport.issue = {'id': 70, 'media': MEDIA, 'status': 1, 'issueType': 1,
                                'problemSeason': 1, 'problemEpisode': 6,
                                'arrProxyStatus': 'submitted', 'comments': [{'message': '4k DV copy problem'}]}
        self.assertEqual(self.run_report()['reportStatus'], 'needs_review')
        self.assertEqual(self.transport.posts, 0)

    def test_repeated_invalid_tokens_are_limited_before_origin(self):
        for _ in range(20):
            with self.assertRaises(Fault):
                self.relay.report(EVENT, 'invalid-token-0000000000')
        with self.assertRaises(Fault) as error:
            self.relay.report(EVENT, 'invalid-token-0000000000')
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(len(self.transport.calls), 20)

    def test_actual_http_handler_auth_and_success(self):
        import requests
        server = HTTPServer(('127.0.0.1', 0), self.relay)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        url = f'http://127.0.0.1:{server.server_port}'
        self.assertEqual(requests.get(url + '/healthz', timeout=2).status_code, 200)
        self.assertEqual(requests.post(url + '/v1/playback-failures', json=EVENT, timeout=2).status_code, 401)
        r = requests.post(url + '/v1/playback-failures', json=EVENT,
                          headers={'Authorization': 'Bearer ' + TOKEN}, timeout=3)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()['issueId'], 70)
        self.assertEqual(requests.post(url + '/v1/playback-failures', data=b'x'*5000,
                                       headers={'Content-Type': 'application/json'}, timeout=2).status_code, 413)


if __name__ == '__main__':
    unittest.main()
