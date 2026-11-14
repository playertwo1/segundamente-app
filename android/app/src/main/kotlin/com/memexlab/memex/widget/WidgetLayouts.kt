package com.memexlab.memex.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.MainActivity
import com.memexlab.memex.R
import java.time.Instant

/**
 * Chooses the widget's RemoteViews by size: small (chat keys, F15-03), medium (chat keys plus
 * the capture keys, F15-04) or large (both rows, the "+ tarefa" key and up to three of today's
 * tasks, F15-05). Key = the smallest size, in dp, that the layout fits. On API 26-30 there is one
 * layout per RemoteViews, so the provider picks it from the widget's min height instead.
 */
internal object WidgetLayouts {
    private const val MODE_TYPE = "type"
    private const val MODE_TALK = "talk"
    private const val MODE_NOTE = "note"
    private const val MODE_PHOTO = "photo"
    private const val MODE_PASTE = "paste"
    private const val MODE_TODO_ADD = "todo_add"
    private const val MODE_TODO_COMPLETE = "todo_complete:"
    private const val REQUEST_TYPE = 1
    private const val REQUEST_TALK = 2
    private const val REQUEST_NOTE = 3
    private const val REQUEST_PHOTO = 4
    private const val REQUEST_PASTE = 5
    private const val REQUEST_TODO_ADD = 6
    private const val REQUEST_TASK_CHECK = 10 // + row index (0..2)
    private const val REQUEST_TASK_TITLE = 20 // + row index (0..2)

    // Same as minWidth x minHeight in res/xml/segundamente_widget_info.xml.
    private val SMALL_MIN = SizeF(200f, 60f)
    private val MEDIUM_MIN = SizeF(200f, 120f)
    private val LARGE_MIN = SizeF(250f, 270f)
    private const val MEDIUM_MIN_HEIGHT_DP = 120
    private const val LARGE_MIN_HEIGHT_DP = 270

    /** [minHeightDp] is the widget's OPTION_APPWIDGET_MIN_HEIGHT; only API 26-30 reads it. */
    fun views(context: Context, minHeightDp: Int): RemoteViews {
        val rows = TodoWidgetSnapshot.rows(TodoWidgetSnapshot.load(context), Instant.now())
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> RemoteViews(
                mapOf(
                    SMALL_MIN to small(context),
                    MEDIUM_MIN to medium(context),
                    LARGE_MIN to large(context, rows),
                ),
            )
            minHeightDp >= LARGE_MIN_HEIGHT_DP -> large(context, rows)
            minHeightDp >= MEDIUM_MIN_HEIGHT_DP -> medium(context)
            else -> small(context)
        }
    }

    private fun small(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_small).apply { setChatKeys(context) }

    private fun medium(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_medium).apply {
            setChatKeys(context)
            setCaptureKeys(context)
        }

    private fun large(context: Context, rows: List<WidgetRow>): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_large).apply {
            setChatKeys(context)
            setCaptureKeys(context)
            setOnClickPendingIntent(R.id.widget_task_add, floatingChat(context, MODE_TODO_ADD, REQUEST_TODO_ADD))
            removeAllViews(R.id.widget_tasks_list)
            rows.forEachIndexed { index, row -> addView(R.id.widget_tasks_list, taskRow(context, row, index)) }
            val empty = rows.isEmpty()
            setViewVisibility(R.id.widget_tasks_list, if (empty) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.widget_tasks_empty, if (empty) View.VISIBLE else View.GONE)
        }

    /** The circle completes the task; the title opens the Todo list (memex://open_todo). */
    private fun taskRow(context: Context, row: WidgetRow, index: Int): RemoteViews {
        val task = row.task
        return RemoteViews(context.packageName, R.layout.widget_task_row).apply {
            setTextViewText(R.id.widget_task_title, task.title)
            setTextViewText(R.id.widget_task_time, timeLabel(context, row))
            setContentDescription(R.id.widget_task_check, context.getString(R.string.widget_task_complete, task.title))
            setOnClickPendingIntent(
                R.id.widget_task_check,
                floatingChat(context, MODE_TODO_COMPLETE + task.id, REQUEST_TASK_CHECK + index),
            )
            setOnClickPendingIntent(R.id.widget_task_title, openTodo(context, REQUEST_TASK_TITLE + index))
        }
    }

    /** Overdue rows show their date; a task due today with no time shows "Hoje". */
    private fun timeLabel(context: Context, row: WidgetRow): String {
        val due = row.task.dueDate
        val date = "%02d/%02d".format(due.dayOfMonth, due.monthValue)
        val time = row.task.dueTime?.let { "%02d:%02d".format(it.hour, it.minute) }
        return when {
            row.overdue -> listOfNotNull(date, time).joinToString(" ")
            else -> time ?: context.getString(R.string.widget_today)
        }
    }

    private fun RemoteViews.setChatKeys(context: Context) {
        setOnClickPendingIntent(R.id.widget_chat_type, floatingChat(context, MODE_TYPE, REQUEST_TYPE))
        setOnClickPendingIntent(R.id.widget_chat_talk, floatingChat(context, MODE_TALK, REQUEST_TALK))
    }

    private fun RemoteViews.setCaptureKeys(context: Context) {
        setOnClickPendingIntent(R.id.widget_capture_note, floatingChat(context, MODE_NOTE, REQUEST_NOTE))
        setOnClickPendingIntent(R.id.widget_capture_photo, floatingChat(context, MODE_PHOTO, REQUEST_PHOTO))
        setOnClickPendingIntent(R.id.widget_capture_paste, floatingChat(context, MODE_PASTE, REQUEST_PASTE))
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

    private fun openTodo(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("memex://open_todo"))
            .setClass(context, MainActivity::class.java)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
