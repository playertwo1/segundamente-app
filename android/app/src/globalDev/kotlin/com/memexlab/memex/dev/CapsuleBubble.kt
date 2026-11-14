package com.memexlab.memex.dev

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.content.LocusId
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.R

/** Prototype A (F15-07): conversation bubble posted by the dev-only launcher "Cápsula: bolha". */
object CapsuleBubble {
    private const val CHANNEL_ID = "f1507_bubble"
    private const val SHORTCUT_ID = "f1507_chat"
    private const val NOTIFICATION_ID = 1507
    private const val CONVERSATION_CATEGORY = "android.shortcut.conversation"
    private const val BUBBLE_HEIGHT_DP = 600

    /** False when the bubble could not be posted (notifications off, or Android below 11). */
    fun post(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            CapsuleLog.event("bubble unsupported below Android 11")
            return false
        }
        val context: Context = activity
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) {
            CapsuleLog.event("bubble blocked: notifications disabled for the app")
            return false
        }
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Cápsula de teste (bolha)", NotificationManager.IMPORTANCE_HIGH)
                .apply { setAllowBubbles(true) },
        )
        CapsuleLog.event("bubble channel ready; system bubbles allowed=${manager.areBubblesAllowed()}")

        val person = Person.Builder().setName("Segunda Mente").setBot(true).setKey(SHORTCUT_ID).build()
        // Long-lived conversation shortcut: required for the notification to count as a conversation.
        val shortcut = ShortcutInfo.Builder(context, SHORTCUT_ID)
            .setShortLabel("Segunda Mente")
            .setLongLived(true)
            .setLocusId(LocusId(SHORTCUT_ID))
            .setPersons(arrayOf(person))
            .setCategories(setOf(CONVERSATION_CATEGORY))
            .setIntent(hostIntent(context).setAction(Intent.ACTION_VIEW))
            .build()
        context.getSystemService(ShortcutManager::class.java).pushDynamicShortcut(shortcut)

        val contentIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            hostIntent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        // Started by the user's tap on the launcher: expand at once and keep the shade quiet.
        val bubble = Notification.BubbleMetadata.Builder(
            contentIntent,
            Icon.createWithResource(context, R.drawable.ic_quick_note),
        )
            .setDesiredHeight((BUBBLE_HEIGHT_DP * context.resources.displayMetrics.density).toInt())
            .setAutoExpandBubble(true)
            .setSuppressNotification(true)
            .build()
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_todo_notification)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setShortcutId(SHORTCUT_ID)
            .setStyle(
                Notification.MessagingStyle(person)
                    .addMessage("Protótipo da bolha: toque para conversar.", System.currentTimeMillis(), person),
            )
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setBubbleMetadata(bubble)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
        CapsuleLog.event("bubble posted")
        return true
    }

    /** The bubble's activity is CapsuleBubbleHostActivity; the floating-chat mode is set on the intent. */
    private fun hostIntent(context: Context): Intent =
        Intent(context, CapsuleBubbleHostActivity::class.java)
            .putExtra(FloatingChatActivity.EXTRA_MODE, "type")
}

/** Launcher entry "Cápsula: bolha" (dev only). Posts the bubble and finishes. */
class CapsuleBubbleLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!CapsuleBubble.post(this)) {
            startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
            )
        }
        finish()
    }
}
