package com.memexlab.memex.channels

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `com.memexlab.memex/esp32_notif` (F17): MethodChannel bridge between Dart
 * [Esp32MqttNotificationForwarder] and the native notification listener.
 * The listener posts the selected notifications here; Dart applies the user's
 * app filter and publishes them to the board over MQTT.
 */
object Esp32NotificationChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/esp32_notif"

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun emitNotification(app: String, title: String, body: String) {
        mainHandler.post {
            channel?.invokeMethod(
                "onNotification",
                mapOf("app" to app, "title" to title, "body" to body),
            )
        }
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNotificationAccess" -> {
                        val enabled = Settings.Secure.getString(
                            activity.contentResolver,
                            "enabled_notification_listeners",
                        ).orEmpty()
                        result.success(enabled.contains(activity.packageName))
                    }
                    "openNotificationAccessSettings" -> {
                        activity.startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK,
                            ),
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
