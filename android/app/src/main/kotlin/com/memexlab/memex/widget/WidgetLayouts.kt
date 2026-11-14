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
 * Chooses the widget's RemoteViews by size: small (chat keys, F15-03) or medium (chat keys plus
 * the capture keys, F15-04). Key = the smallest size, in dp, that the layout fits. F15-05 adds
 * the large layout here. On API 26-30 there is one layout per RemoteViews, so the provider picks
 * it from the widget's min height instead.
 */
internal object WidgetLayouts {
    private const val MODE_TYPE = "type"
    private const val MODE_TALK = "talk"
    private const val MODE_NOTE = "note"
    private const val MODE_PHOTO = "photo"
    private const val MODE_PASTE = "paste"
    private const val REQUEST_TYPE = 1
    private const val REQUEST_TALK = 2
    private const val REQUEST_NOTE = 3
    private const val REQUEST_PHOTO = 4
    private const val REQUEST_PASTE = 5

    // Same as minWidth x minHeight in res/xml/segundamente_widget_info.xml.
    private val SMALL_MIN = SizeF(200f, 60f)
    private val MEDIUM_MIN = SizeF(200f, 120f)
    private const val MEDIUM_MIN_HEIGHT_DP = 120

    /** [minHeightDp] is the widget's OPTION_APPWIDGET_MIN_HEIGHT; only API 26-30 reads it. */
    fun views(context: Context, minHeightDp: Int): RemoteViews =
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                RemoteViews(mapOf(SMALL_MIN to small(context), MEDIUM_MIN to medium(context)))
            minHeightDp >= MEDIUM_MIN_HEIGHT_DP -> medium(context)
            else -> small(context)
        }

    private fun small(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_small).apply { setChatKeys(context) }

    private fun medium(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_medium).apply {
            setChatKeys(context)
            setOnClickPendingIntent(R.id.widget_capture_note, floatingChat(context, MODE_NOTE, REQUEST_NOTE))
            setOnClickPendingIntent(R.id.widget_capture_photo, floatingChat(context, MODE_PHOTO, REQUEST_PHOTO))
            setOnClickPendingIntent(R.id.widget_capture_paste, floatingChat(context, MODE_PASTE, REQUEST_PASTE))
        }

    private fun RemoteViews.setChatKeys(context: Context) {
        setOnClickPendingIntent(R.id.widget_chat_type, floatingChat(context, MODE_TYPE, REQUEST_TYPE))
        setOnClickPendingIntent(R.id.widget_chat_talk, floatingChat(context, MODE_TALK, REQUEST_TALK))
    }

    // Same target and extra as the chat_type / chat_talk shortcuts. Distinct request codes keep the
    // PendingIntents apart, since Intent equality ignores extras.
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
