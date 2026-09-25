from pathlib import Path

root = Path(__file__).resolve().parents[1] / "mobile"
manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    text = manifest.read_text()
    permissions = [
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
        '<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    ]
    insert = "\n    ".join(p for p in permissions if p not in text)
    if insert:
        marker = text.find(">", text.find("<manifest"))
        text = text[: marker + 1] + "\n    " + insert + text[marker + 1 :]
    text = text.replace('android:label="viranari_app"', 'android:label="ViraNari"')
    if 'android:usesCleartextTraffic=' not in text:
        text = text.replace('<application\n', '<application\n        android:usesCleartextTraffic="true"\n', 1)
    manifest.write_text(text)

plist = root / "ios/Runner/Info.plist"
if plist.exists():
    text = plist.read_text()
    additions = []
    if "NSLocationWhenInUseUsageDescription" not in text:
        additions.append(
            "\t<key>NSLocationWhenInUseUsageDescription</key>\n"
            "\t<string>ViraNari uses your location when you trigger an SOS so trusted contacts can find you.</string>\n"
        )
    if "NSLocationAlwaysAndWhenInUseUsageDescription" not in text:
        additions.append(
            "\t<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>\n"
            "\t<string>During an active emergency, ViraNari can continue sharing your live location with your trusted circle.</string>\n"
        )
    if "UIBackgroundModes" not in text:
        additions.append(
            "\t<key>UIBackgroundModes</key>\n"
            "\t<array>\n"
            "\t\t<string>location</string>\n"
            "\t</array>\n"
        )
    if additions:
        text = text.replace("</dict>", "".join(additions) + "</dict>", 1)
        plist.write_text(text)

print("Mobile platform files patched for ViraNari v1.2 local development.")
