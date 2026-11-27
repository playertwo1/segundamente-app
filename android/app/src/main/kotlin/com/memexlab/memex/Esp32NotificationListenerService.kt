package com.memexlab.memex

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.memexlab.memex.channels.Esp32BleChannelHandler

/**
 * Optional notification listener for F16-04: forwards selected notifications
 * (calls, WhatsApp, SMS/messages, Calendar) to `Esp32BleChannelHandler` so Dart
 * applies user app filters and HMAC-signs packets to `SegundaMente-Placa`.
 */
class Esp32NotificationListenerService : NotificationListenerService() {

    companion object {
        fun mapPackageToAppTag(pkg: String): String? = when (pkg) {
            "com.whatsapp", "com.whatsapp.w4b" -> "whatsapp"
            "com.google.android.dialer",
            "com.samsung.android.incallui",
            "com.android.incallui" -> "call"
            "com.google.android.apps.messaging",
            "com.samsung.android.messaging",
            "com.android.mms" -> "msg"
            "com.google.android.calendar",
            "com.samsung.android.calendar" -> "calendar"
            else -> null
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return
        val appTag = mapPackageToAppTag(sbn.packageName ?: return) ?: return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim().orEmpty()
        if (title.isEmpty() && body.isEmpty()) return

        Esp32BleChannelHandler.emitNotification(app = appTag, title = title, body = body)
    }
}
