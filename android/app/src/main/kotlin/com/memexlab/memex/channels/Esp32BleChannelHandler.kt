package com.memexlab.memex.channels

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.memexlab.memex.Esp32BleManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `com.memexlab.memex/esp32_ble` (F16): MethodChannel bridge between Dart
 * [Esp32BleBridgeService] and native Android BLE GATT / notification listener.
 */
object Esp32BleChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/esp32_ble"
    private const val REQ_BLE_PERMS = 1601

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var manager: Esp32BleManager? = null

    fun emitNotification(app: String, title: String, body: String) {
        mainHandler.post {
            channel?.invokeMethod(
                "onNotification",
                mapOf("app" to app, "title" to title, "body" to body),
            )
        }
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        val ble = manager ?: Esp32BleManager(
            context = activity.applicationContext,
            onLineReceived = { line ->
                channel?.invokeMethod("onBleLine", line)
            },
            onConnectionChanged = { connected ->
                channel?.invokeMethod("onConnectionChanged", connected)
            },
        ).also { manager = it }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanAndConnect" -> {
                        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong()) ?: 10_000L
                        ble.scanAndConnect(timeoutMs) { ok, err ->
                            if (ok) {
                                result.success(true)
                            } else {
                                result.error("ble_connect", err ?: "connect_failed", null)
                            }
                        }
                    }
                    "disconnect" -> {
                        ble.disconnect()
                        result.success(null)
                    }
                    "isConnected" -> result.success(ble.isConnected)
                    "readStatus" -> ble.readStatus { text, err ->
                        if (text != null) {
                            result.success(text)
                        } else {
                            result.error("ble_read", err ?: "read_failed", null)
                        }
                    }
                    "writeJson" -> {
                        val payload = call.argument<String>("payload")
                        if (payload.isNullOrEmpty()) {
                            result.error("ble_args", "missing_payload", null)
                        } else {
                            ble.writeJson(payload) { ok, err ->
                                if (ok) result.success(true)
                                else result.error("ble_write", err ?: "write_failed", null)
                            }
                        }
                    }
                    "hasBlePermissions" -> result.success(hasBlePermissions(activity))
                    "requestBlePermissions" -> {
                        requestBlePermissions(activity)
                        result.success(hasBlePermissions(activity))
                    }
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

    private fun hasBlePermissions(activity: Activity): Boolean {
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        return perms.all {
            ContextCompat.checkSelfPermission(activity, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBlePermissions(activity: Activity) {
        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        ActivityCompat.requestPermissions(activity, perms, REQ_BLE_PERMS)
    }
}
