# Sipflix → Moonfin-Core 2.2.0 (Flutter) Port

Re-fork of `Moonfin-Client/Moonfin-Core` (Flutter/Dart, tag **2.2.0**) carrying the Sipflix
customizations originally built on the old Kotlin `AndroidTV-FireTV` fork
(`~/projects/moonfin-tv`, branch `sipflix-mvp`). Kotlin → Dart = **re-implementation**, not merge.

- Fork: `brendongl/Moonfin-Core`, branch `sipflix`, upstream remote = `Moonfin-Client/Moonfin-Core`.
- Flutter pin: **3.44.1** (matches upstream CI). Build flavor for TV boxes: `androidtv` release.
- **ABI: SamPlay boxes (Allwinner H6/H618) run a 32-bit Android userspace** → `ro.product.cpu.abilist=armeabi-v7a,armeabi`. MUST build with `armeabi-v7a` (`--target-platform android-arm`); an arm64-only APK crashes at launch with `Could not find 'libflutter.so' ... only found: [arm64-v8a]`. Release/fleet build = `android-arm,android-arm64`. Build env: `flutter` at `~/flutter`, `ANDROID_HOME=~/android-sdk`, durable build via `systemd-run --user --unit=sipflix-tvbuild` (survives harness session teardown; `setsid` alone does not).
- Test device: **Pro17 = 192.168.50.126:5555** (SamPlay A98pro). Stock Emby was installed; old fork app id `com.sipflix.moonfin`.

## Load-bearing config to reproduce (from old Kotlin SipflixConnectionManager/Injector)

Servers injected on first launch (type **EMBY**, version `4.10.0.4`, setupCompleted, default route = **CDN**):

| Server | UUID | CDN | Direct | VN Proxy |
|---|---|---|---|---|
| **Alpha** | `51901ff1-a001-4000-8000-000000000001` | `https://emby.alphacdn.sipflix.net` | `https://emby.alpha.sipflix.net` | `https://emby.alphavn.sipflix.net` |
| **iDuck** | `51901ff1-a001-4000-8000-000000000002` | `https://34335.brr.savethecdn.com` | `http://95.216.4.149:42418` | `https://emby.iduckvn.sipflix.net` |

- Route toggle cycles **CDN → Direct → VN → CDN**; persists per-server; on switch, rewrites the active server address.
- Low-RAM (≤2 GB) devices: disable background blur, media bar, episode preview (run once).

## Feature checklist (port targets)

- [~] Branding — per operator: KEEP "Moonfin" wording, only swap the icon to the Sipflix badge. Wordmark (`assets/images/logo_and_text.png`) + TV banner (`moonfin_tv_banner.png`) recomposed = Sipflix badge (`ic_sipflix_large.png`) + white "Moonfin" text. App name stays "Moonfin". Originals backed up in scratchpad. TODO (optional): app-icon mipmaps to Sipflix badge.
- [x] Hardcoded server injection (Alpha + iDuck) + hide "Add Server" — DONE, verified on Pro17 2026-06-29 (`lib/sipflix/sipflix_servers.dart` + startup hook + server_select_screen flag)
- [x] CDN / Direct / VN route toggle — DONE, verified on Pro17 2026-06-29 (`sipflix_connection_manager.dart`; "Connection: <mode>" button on login_screen + server_screen; rewrites address + drops cached client). TODO later: in-player overlay route switch.
- [x] QR-code web login — DONE, verified end-to-end on Pro17 2026-06-29 (POSTed creds to box :8765 → authenticated → home). `lib/sipflix/sipflix_login_server.dart` (dart:io HttpServer on :8765 phone login form) + `sipflix_qr_login_screen.dart` (QR of http://<box-ip>:8765, reuses `_authRepo.authenticate` → `switchCurrentSession`); route `Destinations.qrLogin` (MUST be in app_router `_authRoutes` allowlist or the redirect bounces it pre-login); "Sign in with phone" button on login_screen.
- [~] Bitrate auto-suggest dialog on buffering — IMPLEMENTED + logic unit-tested (5/5) + no device regression 2026-06-29 (`lib/sipflix/sipflix_bitrate_watchdog.dart` + hooks in `video_player_screen.dart`: bufferingStream listener → dialog → `setBitrateOverride` + `startQueuedPlayback`). PENDING: live on-device trigger test (needs Emby login + induced stalls).
      SPEC (from old Kotlin): sliding window ≥3 buffering events in 60s → offer ONCE per item; tiers Mbps [120,80,60,40,30,20,15,10,8,5,3] suggest first < current (min 3); dialog "Stream is X Mbps. Lower to Y Mbps?" Yes(focused)/No, auto-dismiss; on Yes set maxBitrate pref + restart stream at current position; reset tracking on new item. Secondary: prefer AC3/EAC3 5.1 > AAC > … > TrueHD 7.1.
- [ ] De-duplicate 4K libraries
- [ ] Ratings overlay on detail pages (was built+disabled in Kotlin via MDBList)
- [ ] Homepage collection carousels (check if upstream 2.2.0 already has this)
- [ ] Direct-Jellyseerr client for Emby (upstream Seerr is Jellyfin-plugin-only — won't work on Emby)
- [ ] RAM-adaptive defaults for low-end boxes
- [ ] Hide Jellyseerr/SyncPlay where not applicable on Emby

## Architecture mapping in Moonfin-Core 2.2.0 (verified against source)

- **Server model**: `lib/auth/models/server.dart` — `Server{id,name,address,version,serverType,setupCompleted,...}`, has `copyWith(address:)`, JSON (de)serialized. ServerType from `server_core` (jellyfin/emby).
- **Store / repo**: `lib/auth/store/authentication_store.dart` (`getServers/putServer/removeServer`); `lib/auth/repositories/server_repository.dart` (`addServer(address)` PROBES network — DON'T use for injection; use `putServer` directly with fixed Server). `updateServer(server)` persists changes.
- **Inject hardcoded servers**: in `lib/ui/screens/auth/startup_screen.dart` `_initialize()` — if `getServers().isEmpty`, construct the two `Server`s (EMBY, fixed UUIDs, address=CDN, setupCompleted:true) and `putServer`. Bypass the probe.
- **Active base URL**: resolved in `lib/data/services/media_server_client_factory.dart` from `server.address` (cached per serverId → invalidate/soft-restart after a route switch). Route toggle = persist mode in a Sipflix prefs map + `updateServer(copyWith(address: routeUrl))`.
- **Login/account UI**: `lib/ui/screens/auth/{server_select_screen,server_screen,login_screen}.dart`. "Connection: CDN" button → `server_screen.dart` (the user-pick screen). Quick Connect already in `login_screen.dart` (basis for QR login).
- **Player/buffering**: AndroidTV uses `lib/playback/media3_player_backend.dart`; `packages/playback_core` exposes `bufferingStream: Stream<bool>` + `bufferStream`. Quality via `lib/playback/device_profile_builder.dart`. No auto-bitrate logic yet — listen to `bufferingStream`, lower max bitrate / re-negotiate.
- **Home carousels**: `lib/data/models/home_row.dart` ALREADY has `HomeRowType.collections` + `.playlists`; configured in `lib/preference/home_section_config.dart` + `lib/ui/screens/settings/home_sections_screen.dart`. ⇒ goal largely upstream.
- **Ratings**: `lib/ui/widgets/rating_display.dart` (`RatingsRow`) + `lib/data/repositories/mdblist_repository.dart` ALREADY upstream. ⇒ overlay goal largely upstream; just surface/configure.
- **4K dedup**: `lib/data/models/aggregated_item.dart` has 4K detection but NO grouping. Build dedup in repo + version-selector in `item_detail_screen.dart` (uses `mediaSources`).
- **Branding**: app name in `lib/l10n/app_*.arb` (`appTitle`) + `android/app/build.gradle.kts` (`baseAppName`, `baseAppId=org.moonfin.androidtv`); icons `assets/icons/` + `android/app/src/main/res/mipmap-*`; TV banner `res/drawable/moonfin_tv_banner`.
- **Settings pattern**: `lib/ui/screens/settings/settings_side_panel.dart` + per-screen files + `PreferenceTile` + routes in `lib/ui/navigation/{app_router,destinations}.dart`. Seerr config: `lib/ui/screens/settings/seerr_config_screen.dart` (proxy-only — add direct-Jellyseerr mode for Emby).

## Old Kotlin source references (behavior to reproduce)
`SipflixConnectionManager.kt`, `SipflixServerInjector.kt`, `LoginServer.kt`, `SelectRouteAction.kt`,
`UserLoginQRFragment.kt`, `DeviceCapabilities.kt`, `MdbListRepository.kt` (ratings),
`EmbyFeatureSupport.kt`, `vlc_player_interface.xml` (bitrate dialog + spinner).
All in `~/projects/moonfin-tv` @ branch `sipflix-mvp`.
