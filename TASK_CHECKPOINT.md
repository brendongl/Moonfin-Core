# Playback reporting — conversation 1553038053537222677

## Gate 1: source and integration identified
- Isolated branch feature/playback-report-1553038053537222677, base fd9c5f5d (committed Flutter fork, build 2400024). Shared checkout has unrelated WIP and is untouched.
- Persistent PlaybackFailureOverlay already exists. PlaybackManager emits terminal bring-up failures after recovery, but overclassifies 404 as missing content.
- Native Media3 already forwards httpStatus. Extend failed state to retain source ID and status; implement Sipflix-specific reporting outside upstream core.
- Seerr requires authenticated session; current tenant adapter protocol being checked. Earlier successful #70 is historical evidence, not a new integration test.
- Direct requests to Seerr timed out on IPv6; curl IPv4 reaches login (200). Not an application test failure.
- No helpers. No production mutation or customer messaging.

## Remaining
Implement relay (authenticated allowlisted origin probes, source-specific evidence, Seerr adapter, durable dedup, rate/circuit limits), Flutter reporting UI, isolated tests, release build and compiled string verification, operator-device validation if available.
Use no automated replacement unless exact source missing evidence and a healthy control agree. No broad season requests, source deletion, policy changes or customer credentials in APK.

## Next action
Finish read-only Seerr protocol verification, then implement relay and client.

## Gate 2: implementation and initial verification
- Added services/playback-report/relay.py, tests, deployment/config templates and README.
- Added lib/sipflix/sipflix_playback_report.dart, extended existing failure overlay, wired terminal failures, retained status/source in PlaybackBringupState, removed blanket 404=>deleted claim.
- Backend: 19 isolated tests passed, including HTTP handler, races, dedup across restart, ambiguous submission, source/control failures, identity/expiry, report readback, rate/circuit limits.
- Flutter: 18 focused tests passed (controller, remote navigation, existing playback lifecycle and source/status propagation).
- Analyzer: no errors/warnings; four pre-existing info lints in PlaybackManager (null-aware elements).
- Live READ-ONLY: current n2 E06 exact-source 404 contains its file path; production diagnosis logic returns missing with healthy same-folder control. Seerr #70 media/episode/arrProxy fields match adapter. No new issue/customer message.
- One scratch live test initially failed because curl_cffi Response lacks context-manager support; fixed scratch adapter, reran and passed. Not a relay code failure.
- APK candidate 2.4.0-sipflix.25-report1, code 2400025, building under user unit moonfin-report-build-1553038053537222677. Expected endpoint playback.sipflix.net is staged only, not provisioned.
- Remaining: security/edge-case review, final tests, APK verification, operator hardware gate. Dedicated service identity + public HTTPS routing not configured; this is missing activation evidence, not a failed test.
- No agents/helpers; shared checkout untouched.

## Gate 3: live contracts and operator preview
- Fresh Seerr provider/emby/login (200) and /auth/me identity verification (200) exercised with this conversation's previously authorized test identity. No issue created. Production dedicated identity is still unconfigured.
- Actual requests-based relay transport reached Seerr /status (200, 0.9s) and n2 public info (200, 0.7s). Earlier timeouts were transient, not a persistent capability restriction.
- Relay expanded to 25 passing tests, adding schema migration, wrong-copy/manual issue handling, missing mapping, ArrProxy failure, resolved issue, admission limits.
- Local Pro17 unreachable (no route); no repeated probes. Resolved SNPBackarea via frps to 6118, verified android_id 6995b320471cb9f1. Idle screensaver, no customer device touched.
- Compiled operator-only beta preview APK with both ARM ABIs. Verified preview and reporting strings in each libapp.so before install. com.sipflix.moonfin.beta was absent before installation. Existing production com.sipflix.moonfin 2.3.0 left intact.
- On-device confirmed-missing/report-accepted screen displayed correctly after D-pad centre. Screenshot in deliverables. Other scenario checks in progress, then remove temporary beta and return to launcher.
- Clean final production-candidate build running in unit moonfin-report-final-1553038053537222677; automatic libapp marker verification included. No fleet publishing.

## Gate 4: final build, tests, device cleanup
- Final isolated tests: 25 relay + 20 Flutter = 45 passing. Includes bounded pending polls and cancellation at the overall reporting deadline.
- New controller/tests/preview analyzer clean after correcting preview imports; touched upstream manager retains four pre-existing info lints, no errors/warnings.
- Clean release build successful: com.sipflix.moonfin, versionCode2400025, versionName2.4.0-sipflix.25-report1; 101832196 bytes; SHA256 dd5299ea52bae631c41f9e1dd9769b928e4dd80847a38a88778f1f45436ebbf8.
- Both ARM libapp.so contain reporting endpoint, missing-file text, report states and attempt ID. Neither contains operator preview marker. Build process complete; no active build helpers.
- Device acceptance: all three fixture screens and D-pad transitions passed. Temporary com.sipflix.moonfin.beta removed successfully and Home restored. Existing production com.sipflix.moonfin remains version2.3.0/code2000009.
- systemd deployment template syntax verified using a substituted local executable (production install path is not provisioned).
- Artifacts/logs/screenshots/candidate.json saved under /home/brendongl/deliverables/moonfin-report-1553038053537222677.
- Durable wiki note + memory pointer saved; corrected stale “no API login” Seerr note after fresh live verification.

## Remaining activation gates (not failed tests)
1. Provision a dedicated Seerr reporting identity in the correct tenant, store its credentials outside the repository and pin expected user ID.
2. Install relay behind HTTPS at planned playback.sipflix.net endpoint with proxy rate limits.
3. Validate complete production-player → relay → Seerr round trip with that identity. Current evidence is separate real protocol checks, actual backend HTTP fixture integration, Flutter tests and on-device UI fixture acceptance; do not describe it as full live end-to-end.
4. Publish/customer rollout only after activation. No OTA manifest, live service or customer device has been changed by this task.
5. Alternative-copy selection is not implemented in v1; no button offers an unverified 4K copy.

Next action on continuation: inspect this checkpoint and current branch; complete activation gates if deployment is requested. Do not replay existing customer messages or create duplicate Seerr issue70.
