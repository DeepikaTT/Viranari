#!/usr/bin/env fish
set -l serial (adb devices | awk '$2 == "device" && $1 ~ /^emulator-/ {print $1; exit}')
if test -z "$serial"
    echo "No running Android emulator found."
    exit 1
end

# Generic demo route. `adb emu geo fix` takes LONGITUDE first, then LATITUDE.
set -l route \
  "78.4867 17.3850" \
  "78.4873 17.3855" \
  "78.4880 17.3860" \
  "78.4888 17.3867" \
  "78.4897 17.3875" \
  "78.4906 17.3883" \
  "78.4916 17.3891"

echo "Simulating live GPS movement on $serial ..."
for point in $route
    set -l parts (string split ' ' $point)
    set -l lon $parts[1]
    set -l lat $parts[2]
    echo "GPS -> $lat, $lon"
    adb -s $serial emu geo fix $lon $lat >/dev/null
    sleep 4
end

echo "Route complete. Live Track should show changing GPS, marker movement and trail growth."
