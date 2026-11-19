package com.memexlab.memex

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.LocusId
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/** An Android conversation bubble, posted only on an explicit user action. */
object ChatBubble {
    private const val CHANNEL_ID = "chat_bubble"
    private const val SHORTCUT_ID = "chat_bubble_conversation"
    private const val NOTIFICATION_ID = 1508

    fun status(activity: Activity): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "unsupported"
        val manager = activity.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled() ||
            manager.getNotificationChannel(CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE
        ) return "notifications"
        val notification = manager.activeNotifications.firstOrNull { it.id == NOTIFICATION_ID }
            ?.notification ?: return "off"
        return if (notification.flags and Notification.FLAG_BUBBLE != 0) "active" else "posted"
    }

    fun show(activity: Activity, expand: Boolean = false): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "unsupported"
        if (status(activity) == "notifications") return "notifications"
        val manager = activity.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID, activity.getString(R.string.chat_bubble_channel), NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { setSound(null, null) },
        )
        val title = activity.getString(R.string.chat_bubble_app)
        val user = Person.Builder().setName(activity.getString(R.string.chat_bubble_user))
            .setKey("local_user").build()
        val assistant = Person.Builder().setName(title).setBot(true).setKey(SHORTCUT_ID).build()
        val intent = Intent(activity, ChatBubbleActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .putExtra(FloatingChatActivity.EXTRA_MODE, "bubble")
        val icon = Icon.createWithResource(activity, R.mipmap.ic_launcher)
        val shortcut = ShortcutInfo.Builder(activity, SHORTCUT_ID)
            .setShortLabel(title)
            .setIcon(icon)
            .setLongLived(true)
            .setLocusId(LocusId(SHORTCUT_ID))
            // A shortcut with only bots is ineligible for Android conversation bubbles.
            .setPersons(arrayOf(user, assistant))
            .setCategories(setOf("android.shortcut.conversation"))
            .setIntent(intent)
            .build()
        activity.getSystemService(ShortcutManager::class.java).pushDynamicShortcut(shortcut)

        val pending = PendingIntent.getActivity(
            activity, NOTIFICATION_ID, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val bubble = Notification.BubbleMetadata.Builder(pending, icon)
            .setDesiredHeight(560)
            .setAutoExpandBubble(expand)
            .setSuppressNotification(expand)
            .build()
        manager.notify(
            NOTIFICATION_ID,
            Notification.Builder(activity, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_todo_notification)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setShortcutId(SHORTCUT_ID)
                .setStyle(
                    Notification.MessagingStyle(user).addMessage(
                        activity.getString(R.string.chat_bubble_notification),
                        System.currentTimeMillis(), assistant,
                    ),
                )
                .setContentIntent(pending)
                .setOnlyAlertOnce(true)
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setBubbleMetadata(bubble)
                .build(),
        )
        return "posted"
    }

    fun hide(activity: Activity): String {
        activity.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        return "off"
    }

    fun openSettings(activity: Activity, notifications: Boolean = false) {
        val action = if (notifications) Settings.ACTION_APP_NOTIFICATION_SETTINGS
            else Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS
        try {
            activity.startActivity(Intent(action).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
        } catch (_: ActivityNotFoundException) {
            activity.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(android.net.Uri.fromParts("package", activity.packageName, null)),
            )
        }
    }
}

/** The system embeds this Activity in the bubble task. */
class ChatBubbleActivity : FloatingChatActivity() {
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.opaque
}
