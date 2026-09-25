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
        '<uses-permission android:name="android.permission.SEND_SMS" />',
    ]
    insert = "\n    ".join(p for p in permissions if p not in text)
    if insert:
        marker = text.find(">", text.find("<manifest"))
        text = text[: marker + 1] + "\n    " + insert + text[marker + 1 :]
    text = text.replace('android:label="viranari_app"', 'android:label="ViraNari"')
    if 'android:usesCleartextTraffic=' not in text:
        text = text.replace('<application\n', '<application\n        android:usesCleartextTraffic="true"\n', 1)
    manifest.write_text(text)

main_activity = root / "android/app/src/main/kotlin/com/viranari/viranari_app/MainActivity.kt"
if main_activity.exists():
    main_activity.write_text(r'''package com.viranari.viranari_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val smsChannel = "viranari/sms"

    private fun smsCapability(): Map<String, Any> {
        val capable = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)
        val telephony = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val simReady = telephony.simState == TelephonyManager.SIM_STATE_READY
        val defaultSubId = SubscriptionManager.getDefaultSmsSubscriptionId()
        return mapOf(
            "capable" to capable,
            "sim_ready" to simReady,
            "default_subscription_id" to defaultSubId,
            "subscription_ready" to (defaultSubId != SubscriptionManager.INVALID_SUBSCRIPTION_ID)
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "smsCapability" -> result.success(smsCapability())
                "sendSms" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
                        result.error("SMS_PERMISSION", "SEND_SMS permission is not granted.", null)
                        return@setMethodCallHandler
                    }

                    val capability = smsCapability()
                    if (capability["capable"] != true || capability["sim_ready"] != true) {
                        result.error("SMS_UNAVAILABLE", "No SMS-capable SIM is ready.", null)
                        return@setMethodCallHandler
                    }
                    if (capability["subscription_ready"] != true) {
                        result.error("SMS_SUBSCRIPTION", "No default SMS SIM is selected. Choose a default SMS SIM in Android settings.", null)
                        return@setMethodCallHandler
                    }

                    val recipients = call.argument<List<String>>("recipients") ?: emptyList()
                    val message = call.argument<String>("message") ?: ""
                    if (recipients.isEmpty() || message.isBlank()) {
                        result.error("SMS_ARGUMENTS", "Recipients and message are required.", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val subId = SubscriptionManager.getDefaultSmsSubscriptionId()
                        @Suppress("DEPRECATION")
                        val smsManager = SmsManager.getSmsManagerForSubscriptionId(subId)
                        var dispatched = 0
                        recipients.distinct().forEach { number ->
                            val parts = smsManager.divideMessage(message)
                            if (parts.size > 1) {
                                smsManager.sendMultipartTextMessage(number, null, parts, null, null)
                            } else {
                                smsManager.sendTextMessage(number, null, message, null, null)
                            }
                            dispatched++
                        }
                        result.success(dispatched)
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", e.message ?: "SMS dispatch failed", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
''')

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

print("Mobile platform files patched for ViraNari v1.4 Reliable Response.")
