# Sipflix upstream sync: release validation

This candidate is not approved for customer release. Branch `sipflix-2.8-sync` incorporates upstream main `0894f662b9a5a88bf857103bae8dc31dc583cd07`; the branch name does not imply an upstream 2.8 release.

## Evidence and gates

The initial integrated source passed 5,433 Flutter tests (one skipped) and 272 non-live server package tests. Subsequent review fixes have targeted regression coverage. Current run evidence and exact commits are recorded in `/home/brendongl/overnight/1563049878060539927/work/`; use the latest checkpoint rather than treating these counts as a device pass.

No APK has been built yet. Before the first build, inspect the installed `com.sipflix.moonfin` certificate on SNPtv1tv2 during its allowed window and compare with the local signing key. Keep the existing application ID. Bump `sipflix_tv_build_number` for every APK. Run the `moonfin-flutter-build-verify` skill, inspect a unique new-code string in both compiled `libapp.so` architectures, and verify APK signing certificate/version. An APK size alone is not proof.

Tester builds require:

```
--dart-define=MOONFIN_FORCE_TV=true
--dart-define=DISTRIBUTION_CHANNEL=android_tv_apk
--dart-define=SIPFLIX_PAIRING_URL=https://pairing.sipflix.net
--dart-define=SIPFLIX_ERROR_REPORT_URL=https://pairing.sipflix.net/errors
```

Use the approved build toolchain and Android TV flavor in the mission brief. The pairing/diagnostic relay is independently deployed; do not package its private environment file or Airtable credentials.

## Authorized device matrix

| Device | Access | Window | End state |
| --- | --- | --- | --- |
| Tester Onn 4K | Fleet broker reservation only | Broker availability | Restore original production APK/version |
| Tester Samplay Pro | Fleet broker reservation only | Broker availability | Restore original production APK/version |
| Tester Samplay Max | Fleet broker reservation only | Broker availability | Restore original production APK/version |
| SNPtv1tv2 | Discover current tunnel from devices API | 01:00–07:00 ICT only | New verified candidate, signed in |
| SNPBackarea | Discover current tunnel; verify model | 01:00–07:00 ICT only | New verified candidate, signed in |

Never use customer devices or the bedroom Onn. Record original APK/version/signature and package inventory before installing, so restoration is concrete. Use only SipflixTester and the configured non-admin DUMB tester. Do not restart or configure Emby or DUMB. Do not publish OTA or merge production branches.

For each device record evidence, not just a checkbox:

1. In-place upgrade; app identity, version and compiled markers match intended artifact.
2. QR sign-in and server autodetection on Emby and DUMB; remember both and switch back without another account's token or playback progress leaking across servers.
3. Route measurement selects a tested route; resume does not change an active stream; failure/timeout restores usable UI.
4. At least six minutes of 1080p playback on Alpha, Delta and DUMB; record source codec, direct/transcode method, elapsed time, errors and visible stalls.
5. Alpha/Delta default to smallest eligible version. Manual choice remains available. Delta excludes >1080p in detail, playback, autoplay and casting/download entry points.
6. DUMB request through Seerr becomes playable. No-plugin Alpha/Delta hide Requests cleanly. Turning Seerr off must leave a way to turn it on again.
7. Trigger a controlled invalid item/network failure, confirm useful on-screen explanation and independent Airtable receipt with sanitized metadata.
8. Basic/Advanced toggle, repeated BACK/HOME navigation, resume and account switching cause no crash.

## Human checks required before release

| What | Hardware/person | Why human evidence is needed |
| --- | --- | --- |
| Phone on mobile data scans TV QR, enters tester login, chooses server and sees truthful success | One cafe box plus a real phone; repeat on both Emby/DUMB | Headless browser/synthetic TV acknowledgements do not prove camera/mobile-network/real-TV flow |
| Close QR, rescan, wait before choosing, enter wrong credentials | Same phone/TV | Confirm timing, readable feedback and no unexpected navigation after cancellation |
| Audio/video sync, lip sync, black frames, smooth motion, remote responsiveness | All five approved boxes, with both H264 and suitable HEVC samples | Logs cannot establish perceived quality or HDMI/audio behavior |
| Fragile-decoder refusal reads clearly; safe H264 plays | Samplay models and confirmed cafe hardware | Device models/codecs vary; software guard tests do not prove decoder behavior |
| Settings and errors readable from normal viewing distance | Cafe TV and Onn | Focus, font size and plain-language wording need visual judgment |
| DUMB request-to-play completes and correct title/version appears | DUMB tester on one box, then smoke-check others | Request APIs alone do not establish actual media readiness/playback |
| Final rollout approval | Brendon | Candidate test success does not authorize customer OTA publication |

Stop the mission by 26 October 2026 08:00 ICT. If a gate is unavailable, label it missing evidence or blocked; do not mark it passed. Preserve current checkpoints and restore reserved tester boxes before ending their jobs.
