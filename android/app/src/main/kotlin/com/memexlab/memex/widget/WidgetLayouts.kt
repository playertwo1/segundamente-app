package com.memexlab.memex.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.SizeF
import android.widget.RemoteViews
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.R

/**
 * Chooses the widget's RemoteViews. Every size uses the small layout for now.
 * F15-04 and F15-05 add their layouts to the map below (key = the smallest size, in dp, that the
 * layout fits). On API 26-30 there is one layout only, so a size-specific layout there also needs
 * an onAppWidgetOptionsChanged override in the provider.
 */
internal object WidgetLayouts {
    private const val MODE_TYPE = "type"
    private const val MODE_TALK = "talk"
    private const val REQUEST_TYPE = 1
    private const val REQUEST_TALK = 2

    // Same as minWidth x minHeight in res/xml/segundamente_widget_info.xml.
    private val SMALL_MIN = SizeF(200f, 60f)

    fun views(context: Context): RemoteViews {
        val small = small(context)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            RemoteViews(mapOf(SMALL_MIN to small))
        } else {
            small
        }
    }

    private fun small(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_small).apply {
            setOnClickPendingIntent(R.id.widget_chat_type, floatingChat(context, MODE_TYPE, REQUEST_TYPE))
            setOnClickPendingIntent(R.id.widget_chat_talk, floatingChat(context, MODE_TALK, REQUEST_TALK))
        }

    // Same target and extra as the chat_type / chat_talk shortcuts. Distinct request codes keep the
    // two PendingIntents apart, since Intent equality ignores extras.
    private fun floatingChat(context: Context, mode: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, FloatingChatActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .putExtra(FloatingChatActivity.EXTRA_MODE, mode)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
