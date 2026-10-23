#!/usr/bin/env bash
# Emülatörde: uygulamayı tüm izinlerle kur, test fotoğraflarını koy, entegrasyon testini çalıştır.
API="$1"
set -x
python3 .github/scripts/make_test_images.py /tmp/hcimg || exit 1
flutter build apk --debug || exit 1
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk || exit 1
adb shell mkdir -p /sdcard/DCIM/Camera
for f in hc_a.jpg hc_b.jpg hc_big.jpg; do adb push "/tmp/hcimg/$f" "/sdcard/DCIM/Camera/$f"; done
if [ "$API" -ge 30 ]; then
  adb shell content call --uri content://media --method scan_volume --arg external_primary
else
  for f in hc_a.jpg hc_b.jpg hc_big.jpg; do
    adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file:///sdcard/DCIM/Camera/$f"
  done
fi
sleep 8
WRITE=false
if [ "$API" -lt 30 ]; then WRITE=true; fi
flutter test integration_test/android_smoke_test.dart -d emulator-5554 --dart-define=HC_WRITE=$WRITE 2>&1 | tee test.txt
exit "${PIPESTATUS[0]}"
