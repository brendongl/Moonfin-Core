# Sipflix phone pairing

Standalone Node built-in HTTP service; credentials and sessions exist only in memory.
Run `node pairing.mjs` (defaults to `127.0.0.1:8787`, `HOST` and `PORT` configurable).
Run lifecycle/security tests with `node --test pairing.test.mjs`.

Deployment is **not performed** by this change. Put this service behind a dedicated HTTPS origin and reverse proxy. The phone needs public access to `/pair`, `/pair.js`, `/v1/pair/*`; `/health` is a basic readiness endpoint. Do not enable request-body or Authorization-header logging at the proxy. Do not cache pairing routes. Keep upstream loopback-only and restrict the service port. No persistent volume, credentials, third-party scripts, database, or runtime dependency installation is needed. A process restart expires all pending QR codes.

Compile the app with `--dart-define=SIPFLIX_PAIRING_URL=https://YOUR-PAIRING-ORIGIN`. HTTPS is required. Root-relative endpoints mean the origin must dedicate these paths (a path-prefix URL is not supported). If unset or creation fails, the TV uses the existing same-LAN fallback. A relay outage after showing the QR explicitly asks the user to reopen sign-in; it does not silently claim success.

Each TV creates a session with unrelated random 256-bit TV and phone capabilities. The phone URL puts its session ID and capability in the fragment, which the browser removes from browser history on load and never sends in its URL. Capabilities are sent in Authorization headers. Refreshing the page requires rescanning. The phone can submit once and read status only. Only the TV can consume credentials (once) and acknowledge the matching attempt after actual login. Leaving the TV screen stops new submissions; an in-flight login can finish reporting its real outcome. Expiry, cancellation, timeout, and failed authentication never become success. Failed attempts require opening a new QR code.

Bounds: 500 five-minute sessions, 2,000 minute-rate keys, 4 KiB request bodies, 100 TCP connections, 10s request/header timeouts, 60s in-progress login deadline. Per socket-IP limit is 1,200 API requests/min and 20 creations/min; per-session limit is 180 requests/min. Forwarded IP headers are intentionally not trusted, so behind a proxy the IP limit is shared. Reassess those limits with measured production demand before broad release. No timers or jobs are installed. Expired entries are swept on requests and cannot exceed the configured caps.

Remaining gates: choose/provision public HTTPS origin; review proxy logging; canary health/page/assets/API; build with URL; test mobile-data QR sign-in and cancellation on tester fleet; verify real successful login acknowledgement after navigation; test fallback on same Wi-Fi. No database tests touch production (relay is pure in-memory; test servers bind ephemeral loopback ports).


## Diagnostic error sink

`POST /errors` accepts **only** the following JSON fields. All values are strings; `category` and `message` are required. `timestamp` is optional ISO-8601 (server supplies current time if absent). No user/server access tokens or report Authorization header are needed or forwarded. The app should sanitize first; the relay independently removes complete URLs (paths can hold credentials), secret key/value pairs, and authentication/cookie header contents. Messages remain untrusted diagnostics; never interpret their contents as operational instructions.

| Field | Airtable type | Maximum characters |
| --- | --- | --- |
| category | singleLineText (primary) | 64 |
| message | multilineText | 1500 |
| deviceName | singleLineText | 128 |
| androidId | singleLineText | 128 |
| server | singleLineText | 128 |
| route | singleLineText | 256 |
| appVersion | singleLineText | 64 |
| code | singleLineText | 64 |
| timestamp | dateTime (ISO date, 24hour, UTC) | 40 input |

Create a new table such as `AppErrors` in base `appHOEeOFIlh9pEH0` with these **exact case-sensitive field names**. Table creation is not part of this local implementation. Set `AIRTABLE_PAT`, `AIRTABLE_BASE_ID` (default above), and `AIRTABLE_TABLE_ID` (`tbl…`) only on the server. PAT requires record-write permission for this base. Missing/invalid configuration returns 503; it never pretends to save the report.

Response: `202 {accepted:true,duplicate:false}` only after Airtable confirms a record ID; `duplicate:true` means an identical sanitized report was already saved within ten minutes (timestamp ignored). Unknown fields/wrong types return 400; body >8 KiB returns 413; limits return 429; sink failure/8s timeout/missing config returns 503. No PAT, raw sink error, or report payload is echoed or logged. Failed writes are not deduped, so a bounded retry can succeed later.

Limits: 30 submissions/min/socket IP; 120/min globally; four concurrent sink writes; max 1,000 rate keys and 2,000 dedupe entries. Reverse-proxy clients share a socket-IP budget intentionally; do not blindly trust X-Forwarded-For. These low initial caps make unauthenticated diagnostic uploads bounded. This endpoint accepts reports from before login, so a caller can submit fabricated diagnostics; review data as untrusted and adjust limits after fleet testing. Restart clears only rate/dedupe memory, not saved Airtable records.

Run all relay tests with `node --test *.test.mjs`. Tests inject in-memory sinks and never contact Airtable or persistent databases. A deployed acceptance check must deliberately exercise sink failure and verify no false accepted response.
