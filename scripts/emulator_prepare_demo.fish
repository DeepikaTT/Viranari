#!/usr/bin/env fish
set -l pkg com.viranari.viranari_app
set -l serial (adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ {print $1; exit}')

if test -z "$serial"
    echo "No running Android emulator found. Start one in Android Studio first."
    exit 1
end

echo "Using emulator: $serial"
adb -s $serial shell pm grant $pkg android.permission.ACCESS_COARSE_LOCATION 2>/dev/null; or true
adb -s $serial shell pm grant $pkg android.permission.ACCESS_FINE_LOCATION 2>/dev/null; or true
adb -s $serial shell pm grant $pkg android.permission.ACCESS_BACKGROUND_LOCATION 2>/dev/null; or true
adb -s $serial shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>/dev/null; or true
adb -s $serial shell appops set $pkg FINE_LOCATION allow 2>/dev/null; or true
adb -s $serial shell appops set $pkg COARSE_LOCATION allow 2>/dev/null; or true

echo "Emulator runtime permissions prepared. Production phones still require normal Android consent."
