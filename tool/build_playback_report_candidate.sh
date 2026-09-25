#!/usr/bin/env bash
# Run under a durable systemd unit for operator builds; this script never
# publishes an OTA manifest or installs on a customer device.
set -euo pipefail
report_flutter="${SIPFLIX_FLUTTER_BIN:-flutter}"
report_endpoint="${SIPFLIX_PLAYBACK_REPORT_URL:-https://playback.sipflix.net/v1/playback-failures}"
"$report_flutter" clean
"$report_flutter" pub get
"$report_flutter" build apk --release --flavor androidTv \
  --target-platform android-arm,android-arm64 \
  --dart-define=MOONFIN_FORCE_TV=true \
  --dart-define=DISTRIBUTION_CHANNEL=android_tv_apk \
  --dart-define="SIPFLIX_PLAYBACK_REPORT_URL=$report_endpoint"
python3 - "$report_endpoint" <<'PY'
import hashlib, sys, zipfile
from pathlib import Path
apk = Path('build/app/outputs/flutter-apk/app-androidtv-release.apk')
with zipfile.ZipFile(apk) as archive:
    for abi in ('armeabi-v7a', 'arm64-v8a'):
        binary = archive.read(f'lib/{abi}/libapp.so')
        for marker in (sys.argv[1], 'replacement_requested',
                       'The video file is missing on our server', 'attemptId'):
            assert marker.encode() in binary or marker.encode('utf-16-le') in binary, (abi, marker)
        # The operator harness must never become the customer release.
        assert b'TEST PREVIEW' not in binary
        assert 'TEST PREVIEW'.encode('utf-16-le') not in binary
        print(abi, 'reporting markers verified; preview harness absent')
print('APK bytes:', apk.stat().st_size)
print('SHA256:', hashlib.sha256(apk.read_bytes()).hexdigest())
PY
