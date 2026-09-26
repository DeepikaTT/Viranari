#!/usr/bin/env fish
set SCRIPT_DIR (dirname (status filename))
set ROOT (realpath "$SCRIPT_DIR/..")
set MOBILE "$ROOT/mobile"
set TMP (mktemp -d)

if not type -q flutter
    echo "Flutter is not on PATH. Confirm 'flutter --version' works first."
    exit 1
end

cp -r "$MOBILE/lib" "$TMP/lib"
cp "$MOBILE/pubspec.yaml" "$TMP/pubspec.yaml"
cp "$MOBILE/analysis_options.yaml" "$TMP/analysis_options.yaml"

cd "$MOBILE"; or exit 1
flutter create --platforms=android,ios --org com.viranari --project-name viranari_app .; or exit 1
rm -rf "$MOBILE/lib"
cp -r "$TMP/lib" "$MOBILE/lib"
cp "$TMP/pubspec.yaml" "$MOBILE/pubspec.yaml"
cp "$TMP/analysis_options.yaml" "$MOBILE/analysis_options.yaml"
python3 "$ROOT/scripts/patch_mobile.py"; or exit 1
rm -f "$MOBILE/test/widget_test.dart"
flutter pub get; or exit 1

echo
echo "ViraNari v1.6.0 mobile wrapper is ready."
echo "Android emulator local-backend URL defaults to http://10.0.2.2:3000"
echo "Local: flutter run --dart-define=VIRANARI_API_BASE=http://10.0.2.2:3000"
echo "VPS:   flutter run --dart-define=VIRANARI_API_BASE=https://YOUR-API-DOMAIN --dart-define=VIRANARI_EMERGENCY_NUMBER=112"
echo "Location/native permission changes require a full rebuild if the Android wrapper already existed."
