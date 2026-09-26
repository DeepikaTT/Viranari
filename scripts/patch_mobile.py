from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'mobile'
manifest = root / 'android/app/src/main/AndroidManifest.xml'
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
    insert = '\n    '.join(p for p in permissions if p not in text)
    if insert:
        marker = text.find('>', text.find('<manifest'))
        text = text[: marker + 1] + '\n    ' + insert + text[marker + 1 :]
    text = text.replace('    <uses-permission android:name="android.permission.SEND_SMS" />\n', '')
    text = text.replace('android:label="viranari_app"', 'android:label="ViraNari"')
    if 'android:usesCleartextTraffic=' not in text:
        text = text.replace('<application\n', '<application\n        android:usesCleartextTraffic="true"\n', 1)
    manifest.write_text(text)

main_activity = root / 'android/app/src/main/kotlin/com/viranari/viranari_app/MainActivity.kt'
if main_activity.exists():
    main_activity.write_text(r'''package com.viranari.viranari_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val bridge = "com.viranari.viranari_app/notifications"
    private val sosChannel = "viranari_incoming_sos"
    private val notificationPermissionRequest = 9201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bridge)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(null)
                    }
                    "showIncomingSosNotification" -> {
                        val alertId = call.argument<String>("alertId") ?: "incoming"
                        val senderName = call.argument<String>("senderName") ?: "Trusted contact"
                        val silentMode = call.argument<Boolean>("silentMode") ?: false
                        val latitude = call.argument<Double>("latitude")
                        val longitude = call.argument<Double>("longitude")
                        showIncomingSos(alertId, senderName, silentMode, latitude, longitude)
                        result.success(null)
                    }
                    "showNearbyEmergencyNotification" -> {
                        val alertId = call.argument<String>("alertId") ?: "nearby"
                        val personName = call.argument<String>("personName") ?: "Responder"
                        val distanceM = call.argument<Int>("distanceM") ?: 0
                        val forVictim = call.argument<Boolean>("forVictim") ?: false
                        showNearbyEmergency(alertId, personName, distanceM, forVictim)
                        result.success(null)
                    }
                    "cancelIncomingSosNotification" -> {
                        val alertId = call.argument<String>("alertId") ?: "incoming"
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        manager.cancel(notificationId(alertId))
                        manager.cancel(nearbyNotificationId(alertId))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            sosChannel,
            "ViraNari emergency alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming SOS alerts from your Trusted Circle"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 250, 500, 250, 800)
            enableLights(true)
            lightColor = Color.RED
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationPermissionRequest,
            )
        }
    }

    private fun showIncomingSos(
        alertId: String,
        senderName: String,
        silentMode: Boolean,
        latitude: Double?,
        longitude: Double?,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId(alertId),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val locationText = if (latitude != null && longitude != null) {
            " • ${"%.5f".format(latitude)}, ${"%.5f".format(longitude)}"
        } else {
            ""
        }
        val title = if (silentMode) "ViraNari SILENT SOS" else "ViraNari SOS"
        val body = "$senderName needs your attention$locationText"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, sosChannel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText("$body\nOpen ViraNari to accept and start Live Track."))
            .setContentIntent(pendingIntent)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setVibrate(longArrayOf(0, 500, 250, 500, 250, 800))
            .setLights(Color.RED, 800, 500)

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(notificationId(alertId), builder.build())
    }

    private fun showNearbyEmergency(
        alertId: String,
        personName: String,
        distanceM: Int,
        forVictim: Boolean,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            nearbyNotificationId(alertId),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (forVictim) "Responder is nearby" else "You are close to the victim"
        val body = if (forVictim) {
            "$personName is about $distanceM m away. Keep the emergency active until you are together."
        } else {
            "You are about $distanceM m from the victim. Open ViraNari for the latest live GPS."
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, sosChannel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setPriority(Notification.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setVibrate(longArrayOf(0, 220, 120, 220))

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(nearbyNotificationId(alertId), builder.build())
    }

    private fun notificationId(alertId: String): Int = 41000 + (alertId.hashCode() and 0x3fff)
    private fun nearbyNotificationId(alertId: String): Int = 57000 + (alertId.hashCode() and 0x3fff)
}
''')

plist = root / 'ios/Runner/Info.plist'
if plist.exists():
    text = plist.read_text()
    additions = []
    if 'NSLocationWhenInUseUsageDescription' not in text:
        additions.append(
            '\t<key>NSLocationWhenInUseUsageDescription</key>\n'
            '\t<string>ViraNari uses your location when you trigger an SOS so trusted contacts can find you.</string>\n'
        )
    if 'NSLocationAlwaysAndWhenInUseUsageDescription' not in text:
        additions.append(
            '\t<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>\n'
            '\t<string>During an active emergency, ViraNari can continue sharing your live location with your trusted circle.</string>\n'
        )
    if 'UIBackgroundModes' not in text:
        additions.append(
            '\t<key>UIBackgroundModes</key>\n'
            '\t<array>\n'
            '\t\t<string>location</string>\n'
            '\t</array>\n'
        )
    if additions:
        text = text.replace('</dict>', ''.join(additions) + '</dict>', 1)
        plist.write_text(text)

print('Mobile platform files patched for ViraNari v1.8.7 clean emergency actions + SOS/proximity notifications.')
