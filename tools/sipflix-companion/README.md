# Sipflix phone pairing

Standalone Node built-in HTTP service; credentials and sessions exist only in memory.
Run `node pairing.mjs` (defaults to `127.0.0.1:8787`; deployed port is8789, `HOST` and `PORT` configurable).
Run lifecycle/security tests with `node --test pairing.test.mjs`.

Deployment verified on 23 October 2026 at `https://pairing.sipflix.net`, behind the existing Cloudflare tunnel. For another deployment, use a dedicated HTTPS origin and reverse proxy. The phone needs public access to `/pair`, `/pair.js`, `/v1/pair/*`; `/health` is a basic readiness endpoint. Do not enable request-body or Authorization-header logging at the proxy. Do not cache pairing routes. Keep upstream loopback-only and restrict the service port. No persistent volume, credentials, third-party scripts, database, or runtime dependency installation is needed. A process restart expires all pending QR codes.

Compile the app with `--dart-define=SIPFLIX_PAIRING_URL=https://YOUR-PAIRING-ORIGIN`. HTTPS is required. Root-relative endpoints mean the origin must dedicate these paths (a path-prefix URL is not supported). If unset or creation fails, the TV uses the existing same-LAN fallback. A relay outage after showing the QR explicitly asks the user to reopen sign-in; it does not silently claim success.

Each TV creates a session with unrelated random 256-bit TV and phone capabilities. The phone URL puts its session ID and capability in the fragment, which the browser removes from browser history on load and never sends in its URL. Capabilities are sent in Authorization headers. Refreshing the page requires rescanning. The phone can submit once and read status only. Only the TV can consume credentials (once) and acknowledge the matching attempt after actual login. Leaving the TV screen stops new submissions; an in-flight login can finish reporting its real outcome. Expiry, cancellation, timeout, and failed authentication never become success. Failed attempts require opening a new QR code.

Bounds: 500 five-minute sessions, 2,000 minute-rate keys, 4 KiB request bodies, 100 TCP connections, 10s request/header timeouts, the same five-minute deadline for server selection and sign-in. Per socket-IP limit is 1,200 API requests/min and 20 creations/min; per-session limit is 180 requests/min. Forwarded IP headers are intentionally not trusted, so behind a proxy the IP limit is shared. Reassess those limits with measured production demand before broad release. Pairing itself uses no recurring job. Expired entries are swept on requests and cannot exceed the configured caps.

Public HTTPS canary and synthetic browser/TV-acknowledgement flow pass. Remaining gates: build with URL; test mobile-data QR sign-in and cancellation on tester fleet; verify real successful login acknowledgement after navigation; test fallback on same Wi-Fi. No database tests touch production (relay is pure in-memory; test servers bind ephemeral loopback ports).


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

Create a new table such as `AppErrors` in base `appHOEeOFIlh9pEH0` with these **exact case-sensitive field names**. The approved deployment uses new table `AppErrors` (`tblDGfyPfst0JB8Ag`), verified with a synthetic write and independent readback. Set `AIRTABLE_PAT`, `AIRTABLE_BASE_ID` (default above), and `AIRTABLE_TABLE_ID` (`tbl…`) only on the server. PAT requires record-write permission for this base. Missing/invalid configuration returns 503; it never pretends to save the report.

Response: `202 {accepted:true,duplicate:false}` only after Airtable confirms a record ID; `duplicate:true` means an identical sanitized report was already saved within ten minutes (timestamp ignored). Unknown fields/wrong types return 400; body >8 KiB returns 413; limits return 429; sink failure/8s timeout/missing config returns 503. No PAT, raw sink error, or report payload is echoed or logged. Failed writes are not deduped, so a bounded retry can succeed later.

Limits: 30 submissions/min/socket IP; 120/min globally; four concurrent sink writes; max 1,000 rate keys and 2,000 dedupe entries. Reverse-proxy clients share a socket-IP budget intentionally; do not blindly trust X-Forwarded-For. These low initial caps make unauthenticated diagnostic uploads bounded. This endpoint accepts reports from before login, so a caller can submit fabricated diagnostics; review data as untrusted and adjust limits after fleet testing. Restart clears only rate/dedupe memory, not saved Airtable records.

Run all relay tests with `node --test *.test.mjs`. Tests inject in-memory sinks and never contact Airtable or persistent databases. A deployed acceptance check must deliberately exercise sink failure and verify no false accepted response.


## Service deployment

`deploy/sipflix-companion-system.service` is the installed system-manager variant, running as user `brendongl`. The user-manager variant failed with218/CAPABILITIES on this host and remains disabled; the system manager applies the same restrictions successfully. It expects source files in `~/.local/share/sipflix-companion/` and a separately provisioned mode-0600 `~/.config/sipflix-companion.env` containing the three Airtable variables above. The executable is the verified `/usr/bin/node`. The unit listens only on `127.0.0.1:8789`; a dedicated public HTTPS route (reverse proxy or existing cloudflared tunnel) can forward to it. Do not expose port8789 directly. The active system unit is `sipflix-companion.service`; the separate weekly review timer is described below.

The user manager must support the read-only mount sandbox options; check actual start and `/health` during deployment. A successful `systemd-analyze verify` proves unit syntax, not runtime sandbox support. The unit permits no write paths and caps memory/tasks/open files. Node's JIT needs executable memory, so no `MemoryDenyWriteExecute` restriction is applied. Environment file is read by systemd, never put in repository or app.

Tester app configuration after public origin is verified:

```
--dart-define=SIPFLIX_PAIRING_URL=https://pairing.sipflix.net
--dart-define=SIPFLIX_ERROR_REPORT_URL=https://pairing.sipflix.net/errors
```

When deliberately building without these services, omit both: QR falls back to local Wi-Fi login; diagnostics remain disabled. Error-report delivery is best effort, capped and has no disk queue or retry loop. Pairing creation failure also falls back to LAN; the screen says when the phone needs the same Wi-Fi. These are tester-build parameters, not customer OTA authorization.

## Weekly review deployment

`deploy/weekly-review.py` reads only the configured AppErrors table in the approved base. It fetches at most ten100-row pages for the last seven days, then groups counts by category/server/code. It deliberately never requests raw messages or device identifiers. Unknown/malformed group labels are replaced, so submitted error messages cannot become model instructions or Discord mentions. Pagination overflow/auth/data errors fail the review instead of presenting partial data as complete. No reports is explicitly missing telemetry, never a healthy verdict.

Normal mode re-reads the mode-0600 companion config and the separate owner-only `~/.config/claude-oauth-token.env` (override with `--claude-auth-file`), then performs fresh `claude auth status --json` preflight, then one `claude -p` invocation. Locally verified flags disable tools, hooks/customizations, MCP and session persistence; total summary timeout120s and API budgetUS$1. Only that count summary reaches Claude. No Airtable/Discord tokens are passed to the Claude subprocess. Auth failures are saved distinctly and stop immediately; there is no login automation, shared-token rotation or retry. The CLI performs its normal OAuth refresh. A live read/model run under a transient user unit with `NoNewPrivileges` passed without posting; synthetic QA records are excluded from error totals.

`--output PATH` is required; it writes a private text report and `.json` receipt. Without `--post`, nothing is sent. `--post` uses the existing Discord helper for thread1563049878060539927 only, after a validated report. Any delivery failure/timeout is not retried because a partial delivery may already have happened. Failures are saved locally. With `--post`, a fixed failure notice is attempted once, except after a possibly partial delivery failure. Silence does not prove success.

Offline example (fixture only; no API, Claude, or posting):

```
python3 deploy/weekly-review.py --dry-run --fixture /absolute/fresh-temp/records.json --output /absolute/fresh-temp/review.txt
python3 deploy/weekly-review.test.py
```

Fixture shape is an Airtable-style JSON array of `{ "fields": { "timestamp": "2026-10-23T00:00:00Z", "category": "network", "server": "Delta", "code": "503" } }`. `--now` can supply a fixture-only ISO timestamp. Dry-run requires a fixture and rejects `--post`. Tests mock all external calls and use fresh temporary directories.

`deploy/sipflix-diagnostics-review.service` and `.timer` are installed in the user manager and enabled. The next run is Monday 26 October 2026 at08:00 Asia/Ho_Chi_Minh, then weekly. There is no catch-up or retry. A six-minute service timeout bounds the process tree. The live model check did not post; actual scheduled Discord delivery remains unverified. The user explicitly authorized this weekly report in the mission brief.

Runtime source is copied to `~/.local/share/sipflix-companion/`; after changes, compare hashes and restart only this service. A restart expires pending QR codes. The Airtable PAT stays in the owner-only companion environment file, never in the APK or repository. The weekly OAuth file is read fresh and is not copied or rotated by this job.

Origin responses use `Cache-Control: no-store, no-transform` to prevent proxy analytics injection; CSP permits only the local script. Cloudflare Browser Integrity Check is disabled only for this hostname's `/v1/pair*` and `/errors` API paths, so native clients are not rejected with1010. No zone-wide security change was made. Deployment snapshots and evidence are in the conversation's `work/` checkpoint directory.
