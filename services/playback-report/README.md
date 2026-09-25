# Sipflix automatic playback reports

The Flutter player sends a terminal failure to this relay after its existing
recovery attempts. The relay verifies the exact source at the configured origin,
then reports confirmed missing files to Seerr. Nothing is deleted, no library
permissions are changed, and no full-season requests are created.

## Delivery status

This is a staged implementation, not an enabled fleet rollout. The release
candidate targets `https://playback.sipflix.net/v1/playback-failures`; that hostname
must be routed to the relay over HTTPS before enabling the candidate on customers.
The normal build leaves reporting disabled unless `SIPFLIX_PLAYBACK_REPORT_URL`
is supplied. A dedicated Seerr service identity must be configured and verified.
Do not ship a personal/customer session or credentials in the APK.

## Request and authentication

`POST /v1/playback-failures`, JSON (maximum 4096 bytes), with
`Authorization: Bearer <the viewer's Emby access token>`:

```json
{
  "server": "alphav2",
  "userId": "emby-user-id",
  "itemId": "3705508",
  "mediaSourceId": "mediasource_3705508",
  "attemptId": "new-uuid-for-this-playback-attempt",
  "playMethod": "transcode",
  "httpStatus": 500,
  "appVersion": "2.4.0"
}
```

The configured server allowlist determines the origin. Client-supplied URLs,
paths, notes, passwords and unknown properties are rejected. The viewer's token
is forwarded only to that configured Emby origin; the user must be active, have
playback access, and be able to fetch the item and selected source. It is never
persisted, logged, or sent to Seerr. The authenticated service identity is used
for Seerr; the verified viewer name is attributed in the report note.

The relay listens on loopback. Put it behind the existing trusted HTTPS proxy,
with request rate limits. Never expose the Python HTTP listener directly to the
Internet. Bodies, redirects, socket concurrency and outgoing request times are
bounded. Do not log Authorization headers at the proxy.

## Diagnosis and submission rules

- Probe only a local file source, using `Static=true`, the exact `MediaSourceId`
  and a 1024-byte Range request. Close after at most 4096 received bytes even if
  the server ignores Range. Do not start ffmpeg or fetch arbitrary remote URLs.
- A 404/500 alone is insufficient. The error must explicitly state that the
  **exact file path in trusted metadata** is missing. Require that twice, with a
  successful video read from a different file in the same directory between.
- Missing control, unreadable mount, HTML login page, HLS segment 404, uncertain
  metadata, permissions failures and timeouts never trigger replacement.
- Use provider IDs from Emby series/movie metadata. Resolve Seerr's internal
  `mediaInfo.id`, verify TMDB ID and media type, then file VIDEO issue type 1 for
  the exact season/episode. Missing media rows go to review; never create an
  unrelated season request to manufacture a media row.
- The provider fork's login JS uses
  `POST /api/v1/auth/media-server/provider/emby/login` with username/password.
  Authenticate anew from the protected service credential file for each report,
  then verify `/api/v1/auth/me` against the configured expected Seerr user ID. Both the fresh login and identity-check protocol were exercised successfully against the live provider during read-only verification.
  Expired login or wrong identity is a reporting failure, not a missing video.
- Verify the issue returned by POST and a separate GET readback. `reported`
  means Seerr has the issue; `replacement_requested` additionally requires
  `arrProxyStatus == submitted`. Neither means the replacement is playable.
- An existing episode issue without this source's stable marker suppresses
  duplicate submission and goes to review, because it may concern another copy.

## Durable deduplication and failure handling

SQLite stores the source fingerprint, attempt IDs, sanitized status/version,
report marker, issue ID and result. No token, password, raw player URL or storage
path is retained. A unique attempt cannot be retargeted to a different source.
Transactions lease one writer per source. Duplicate attempts and concurrent
viewers get the existing result, including across process restarts.

The database records `submitting` **before** POST. An HTTP timeout, 500, malformed
response or process crash after that point can have committed an issue. A later
attempt searches for the stable marker; it never blindly repeats POST. If an
issue cannot be found within the bounded lookup, retain `uncertain` for review.
No background retry job is installed or needed; reconciliation happens on the
next authenticated failure event. Pending client polls reuse the same attempt.

Admission is also capped at twenty requests per token and 120 globally per minute, before upstream authentication. Limits: ten distinct attempts per viewer per ten minutes; at most five new
replacement submissions per server per ten minutes; eight active HTTP handlers.
The latter submission circuit prevents a storage outage from causing a re-grab
storm. Results are cached for five minutes. Existing open reports remain
referenced beyond the cache lifetime; a refresh does not create a new issue.

The viewer can leave while checks run. Reporting is never claimed before an
acknowledgement with a valid issue ID. Missing-file screens do not recommend
changing the connection or repeatedly retrying the broken copy. Alternative
versions are not offered by v1: cross-library alternatives need separate
access/capability checks, particularly for 4K on Allwinner boxes.

## Configuration and run

Copy `config.example.json` to a protected deployment location and replace its
service identity ID. `seerrCredentialsFile` points to mode-0600 JSON:

```json
{"username":"DEDICATED_SERVICE_ACCOUNT","password":"SECRET_FROM_SECRET_STORE"}
```

The service identity must belong to the correct provider tenant and be able to
view/create episode issues. Verify that identity and tenant against a known
existing issue before activation. Do not invent an API key or use a viewer's
saved cookie as the production account. For short controlled verification,
`seerrSessionFile` can point to mode-0600 Playwright storage state instead; the
cookie is re-read and expiry/identity checked on every use.

Install requirements into a dedicated venv. The supplied systemd unit is a
deployment template and is **not installed by tests**. Its dedicated user,
configuration directory and `/opt/sipflix-playback-report` must be provisioned
before installation. `SIPFLIX_REPORT_DB` overrides storage before any connection
opens. The database migration is idempotent and preserves existing incidents.

```sh
python relay.py --config /etc/sipflix-playback-report/config.json
```

`GET /healthz` verifies process/schema identity, not Seerr availability. A release
check must also perform an authenticated read-only origin and Seerr contract
check. No recurring watcher or customer notification is installed by this code.

## Validation

```sh
python3 -m unittest discover -s services/playback-report -v
flutter test --no-pub test/sipflix/sipflix_playback_report_test.dart \
  test/playback/playback_failure_overlay_test.dart \
  test/playback/playback_manager_lifecycle_test.dart
```

Backend tests always create fresh `/tmp` directories and do not read production
configuration. HTTP integration tests bind ephemeral loopback ports. The live
read-only verification during implementation confirmed the n2 E06 source
classification (`missing`) with a readable sibling; Seerr issue #70 readback
matched media 107231 / TMDB 95350 / S01E06 and ArrProxy submitted. No new live
Seerr issue was created during those checks.

Before release: run tests, build both ARM ABIs, inspect libapp.so for the new
report strings/endpoint, test on an operator-owned device, configure service
identity + HTTPS route, and run the authenticated end-to-end acceptance test.
Keep fleet publishing as a separate explicit rollout decision.
