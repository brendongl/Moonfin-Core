# Sipflix → Moonfin-Core 2.2.0 (Flutter) Port

Re-fork of `Moonfin-Client/Moonfin-Core` (Flutter/Dart, tag **2.2.0**) carrying the Sipflix
customizations originally built on the old Kotlin `AndroidTV-FireTV` fork
(`~/projects/moonfin-tv`, branch `sipflix-mvp`). Kotlin → Dart = **re-implementation**, not merge.

- Fork: `brendongl/Moonfin-Core`, branch `sipflix`, upstream remote = `Moonfin-Client/Moonfin-Core`.
- Flutter pin: **3.44.1** (matches upstream CI). Build flavor for TV boxes: `androidtv` release.
- **ABI: SamPlay boxes (Allwinner H6/H618) run a 32-bit Android userspace** → `ro.product.cpu.abilist=armeabi-v7a,armeabi`. MUST build with `armeabi-v7a` (`--target-platform android-arm`); an arm64-only APK crashes at launch with `Could not find 'libflutter.so' ... only found: [arm64-v8a]`. Release/fleet build = `android-arm,android-arm64`. Build env: `flutter` at `~/flutter`, `ANDROID_HOME=~/android-sdk`, durable build via `systemd-run --user --unit=sipflix-tvbuild` (survives harness session teardown; `setsid` alone does not).
- **Upstream base is now 2.4.0**, merged in `81ef6c7e` (2026-08). The "2.2.0" in this doc's title and
  in the architecture section below is the *original* port baseline — file paths there were re-verified
  against the current tree on 2026-08-20 and still hold.
- Test devices: **Pro17 = 192.168.50.126:5555** (SamPlay A98pro, Allwinner, primary port/verify box).
  **onn 4K Pro = 192.168.50.4:5555** (bedroom, model `onn. Streaming Device 4K pro`, Android 14) — note it
  also reports a **32-bit** userspace (`ro.product.cpu.abi=armeabi-v7a`, no `abilist64`), so the same
  `--target-platform android-arm,android-arm64` rule applies. Old fork app id `com.sipflix.moonfin`.

## Load-bearing config to reproduce (from old Kotlin SipflixConnectionManager/Injector)

Servers injected on first launch (type **EMBY**, version `4.10.0.4`, setupCompleted, default route = **CDN**):

| Server | UUID | CDN | Direct | VN Proxy |
|---|---|---|---|---|
| **Alpha** | `51901ff1-a001-4000-8000-000000000001` | `https://emby.alphacdn.sipflix.net` | `https://emby.alpha.sipflix.net` | `https://emby.alphavn.sipflix.net` |
| **iDuck** | `51901ff1-a001-4000-8000-000000000002` | `https://34335.brr.savethecdn.com` | `http://95.216.4.149:42418` | `https://emby.iduckvn.sipflix.net` |

- Route toggle cycles **CDN → Direct → VN → CDN**; persists per-server; on switch, rewrites the active server address.
- **The table above is the ORIGINAL Kotlin config, kept for reference — it is NOT what ships.**
  The live routes are in `lib/sipflix/sipflix_servers.dart`: one hardcoded server (AlphaV2,
  Id `0ad3808b494044e8ac4706a765eef403`) reachable three ways —
  CDN 1 `https://emby.alphacdn1.sipflix.net`, CDN 2 `https://nebula.cdn2.d-crypt.io`,
  Direct `https://emby.n2.d-crypt.io`. Switching a route now retargets the LIVE client
  (`SipflixConnectionManager.applyRoute`), so it applies to the session already running —
  persisting the address alone only took effect at the next sign-in.
- Low-RAM (≤2 GB) devices: disable background blur, media bar, episode preview (run once).

## Feature checklist (port targets)

Status verified against the source on 2026-08-20 (not from memory — the list had drifted
badly: several items were done upstream, and four shipped Sipflix features were missing).

**Done**

- [x] Hardcoded server injection (Alpha + iDuck) + hide "Add Server" — verified Pro17 2026-06-29 (`lib/sipflix/sipflix_servers.dart`, startup hook, `server_select_screen.dart:552`).
- [x] CDN 1 / CDN 2 / Direct route toggle — `sipflix_connection_manager.dart`; button on `login_screen.dart` + `server_screen.dart` (it takes the "Select Server" slot, `908e6747`), plus a **Server Route** button in the player OSD beside the bitrate one (`OsdButton.serverRoute`). Two identity bugs fixed 2026-08-20:
    1. **A switch only took effect at the next sign-in.** The toggle persisted the address and evicted the cached client, but a signed-in app runs off the `MediaServerClient` singleton that `setActiveServerClient` registered at login, and that kept the old host. `SipflixConnectionManager.applyRoute` now retargets the live clients in place — the mechanism Stream Preflight already used — and the player re-resolves the current stream onto the new route.
    2. **Every route feature was gated on the server record's id.** A record not created by `injectOrMigrate` (an older build, a manual add) carries a different id, so on that box the switcher silently did nothing (`toggle` returned early) and the player button never drew. Identity is now `isSipflixServerRecord` / `findServer`: the hardcoded id OR an address matching a known route. Items are matched with `isSipflixServerRef`, because `AggregatedItem.serverId` is `_serverId ?? client.baseUrl` and is usually the URL on a single-server box. The same id-only guard was short-circuiting Stream Preflight.
- [x] QR-code web login — verified end-to-end Pro17 2026-06-29. `sipflix_login_server.dart` (HttpServer on :8765) + `sipflix_qr_login_screen.dart`; route `Destinations.qrLogin` MUST stay in `app_router` `_authRoutes` or the pre-login redirect bounces it.
- [x] Branding — Sipflix badge + wordmark on the launcher icon, TV banner, and player loading overlay (`cc785c76`). Per operator the app is still called "Moonfin" in strings; only the artwork is Sipflix. Nothing outstanding.
- [x] Ratings on detail pages — **already upstream**, no port work needed. `RatingsRow` (`lib/ui/widgets/rating_display.dart:21`) renders on `item_detail_screen.dart:3945`, `modern_detail_content.dart:3936`, home, browse, favorites and the media bar. MDBList scores need `UserPreferences.mdblistApiKey` set; the repo (`mdblist_repository.dart`) is upstream too.
- [x] Hide SyncPlay on Emby — **already upstream**. `syncplay_manager.dart:98` gates `syncPlayServerSupported` on `ServerType.jellyfin`, so it never shows on the fleet.
- [x] Auto bitrate — supersedes the old Kotlin "suggest a lower bitrate" dialog. Adaptive Auto mode measures the link (`sipflix_bandwidth_probe.dart`), learns a ceiling from real playback, steps down on a *sustained* stall and recovers upward when playback stays clean (`video_player_screen.dart:782-940`, `sipflix_auto_bitrate_service.dart`, prefs at `user_preferences.dart:1307/1391`). `sipflix_bitrate_watchdog.dart` (the manual prompt) is still wired for non-Auto mode.
- [x] Sipflix OTA in-app updater — manifest at `http://103.98.148.133/moonfin/manifest.json`, checked from the app shell (`app.dart:258`, `di/injection.dart:457`). Verified on-device (Pro13).
- [x] Stream Preflight — per-play route + quality check, opt-in; gates every new-item start (`sipflix_preflight.dart`, `playback_module.dart:518`). Renders as an OverlayEntry, NOT a pushed route (`aab729c8`) — pushing it broke playback start.
- [x] Fleet playback defaults — 1080p cap, stereo downmix, trailer/preview autoplay stripped, file size shown on detail (`user_preferences.dart:1430/1660/2014/1146`, `media_bar.dart:334`).

**Partly done**

- [~] De-duplicate 4K libraries — `MediaDeduplicationUtils` (`lib/data/utils/media_deduplication_utils.dart`) collapses a title by external provider id and is wired into the home rows incl. Continue Watching (`row_data_source.dart:1664`, the single-server path Sipflix boxes actually use), search, and the multi-server repo. REMAINING: (a) `library_browse_screen.dart` does no dedup at all; (b) once two library entries collapse, the detail screen only offers versions inside the *winning* item — the separate 4K entry is unreachable. The version picker itself exists upstream (`item_detail_screen.dart:6277/9381`) but only lists that item's `mediaSources`.

**Not started**

- [ ] Homepage collection carousels — the feature is fully upstream (`HomeRowType.collections`, `HomeSectionType.collections`), but the section ships **disabled** (`home_section_config.dart:223`). Turning it on for the fleet is a default-value change, not a port.
- [ ] Direct-Jellyseerr client for Emby — confirmed still proxy-only: `seerr_http_client.dart:59/63` builds every URL as `<jellyfinBaseUrl>/Moonfin/Seerr/...` and authenticates with a Jellyfin token, i.e. it needs the Moonfin *Jellyfin plugin* we don't have on Emby. Seerr is off by default (`seerr_preferences.dart:27`), so nothing is visibly broken today.
- [ ] RAM-adaptive defaults for low-end boxes — no memory detection anywhere in `lib/` or `android/app/src/`. The fleet defaults above already cover the practical goal; this item is only about doing it *dynamically* per device.
- [ ] Hide Seerr where not applicable on Emby — currently only soft-hidden by its default-off preference, not hard-gated on `ServerType`. Low priority while Seerr stays off.

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
