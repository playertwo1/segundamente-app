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
 * the capture keys, F15-04) or large (both rows, the "+ Nova tarefa" row and up to three of today's
 * tasks with 48dp rows sized so rows never clip half-way, F15-05). On API 26-30 there is one
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
    private const val REQUEST_TODAY_OPEN = 7
    // Bases far above the small codes; + task id hash (24 bits), so a stale RemoteViews keeps its own task.
    private const val REQUEST_TASK_CHECK = 0x10000000
    private const val REQUEST_TASK_TITLE = 0x20000000

    // Same base breakpoints as res/xml/segundamente_widget_info.xml, plus wide medium and 1..3-row large buckets.
    private val SMALL_MIN = SizeF(200f, 60f)
    private val MEDIUM_COMPACT_MIN = SizeF(200f, 120f)
    private val MEDIUM_WIDE_MIN = SizeF(250f, 120f)
    private val LARGE_1_MIN = SizeF(250f, 250f)
    private val LARGE_2_MIN = SizeF(250f, 298f)
    private val LARGE_3_MIN = SizeF(250f, 354f)
    private const val MEDIUM_MIN_HEIGHT_DP = 120
    private const val LARGE_1_MIN_HEIGHT_DP = 250
    private const val LARGE_2_MIN_HEIGHT_DP = 298
    private const val LARGE_3_MIN_HEIGHT_DP = 354

    /** [minHeightDp] is the widget's OPTION_APPWIDGET_MIN_HEIGHT; only API 26-30 reads it. */
    fun views(context: Context, minHeightDp: Int): RemoteViews {
        val rows = TodoWidgetSnapshot.rows(TodoWidgetSnapshot.load(context), Instant.now())
        return when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> RemoteViews(
                mapOf(
                    SMALL_MIN to small(context),
                    MEDIUM_COMPACT_MIN to medium(context, compact = true),
                    MEDIUM_WIDE_MIN to medium(context, compact = false),
                    LARGE_1_MIN to large(context, rows, maxRows = 1),
                    LARGE_2_MIN to large(context, rows, maxRows = 2),
                    LARGE_3_MIN to large(context, rows, maxRows = 3),
                ),
            )
            minHeightDp >= LARGE_3_MIN_HEIGHT_DP -> large(context, rows, maxRows = 3)
            minHeightDp >= LARGE_2_MIN_HEIGHT_DP -> large(context, rows, maxRows = 2)
            minHeightDp >= LARGE_1_MIN_HEIGHT_DP -> large(context, rows, maxRows = 1)
            minHeightDp >= MEDIUM_MIN_HEIGHT_DP -> medium(context, compact = false)
            else -> small(context)
        }
    }

    internal fun visibleRowLimit(minHeightDp: Int): Int = when {
        minHeightDp >= LARGE_3_MIN_HEIGHT_DP -> 3
        minHeightDp >= LARGE_2_MIN_HEIGHT_DP -> 2
        minHeightDp >= LARGE_1_MIN_HEIGHT_DP -> 1
        else -> 0
    }

    internal fun formatTaskTimeLabel(todayLabel: String, row: WidgetRow): String {
        val due = row.task.dueDate
        val date = "%02d/%02d".format(due.dayOfMonth, due.monthValue)
        val time = row.task.dueTime?.let { "%02d:%02d".format(it.hour, it.minute) }
        return when {
            row.overdue -> listOfNotNull(date, time).joinToString(" ")
            else -> time ?: todayLabel
        }
    }

    private fun small(context: Context): RemoteViews =
        RemoteViews(context.packageName, R.layout.widget_small).apply { setChatKeys(context) }

    private fun medium(context: Context, compact: Boolean): RemoteViews =
        RemoteViews(
            context.packageName,
            if (compact) R.layout.widget_medium_compact else R.layout.widget_medium,
        ).apply {
            setChatKeys(context)
            setCaptureKeys(context)
        }

    private fun large(context: Context, rows: List<WidgetRow>, maxRows: Int): RemoteViews {
        val visibleRows = rows.take(maxRows)
        val hiddenCount = (rows.size - visibleRows.size).coerceAtLeast(0)
        return RemoteViews(context.packageName, R.layout.widget_large).apply {
            setChatKeys(context)
            setCaptureKeys(context)
            setOnClickPendingIntent(R.id.widget_task_add, floatingChat(context, MODE_TODO_ADD, REQUEST_TODO_ADD))
            setOnClickPendingIntent(R.id.widget_today_header, openTodo(context, REQUEST_TODAY_OPEN))
            setOnClickPendingIntent(R.id.widget_tasks_empty, openTodo(context, REQUEST_TODAY_OPEN))
            if (hiddenCount > 0) {
                setTextViewText(R.id.widget_tasks_overflow, context.getString(R.string.widget_tasks_more, hiddenCount))
                setViewVisibility(R.id.widget_tasks_overflow, View.VISIBLE)
            } else {
                setViewVisibility(R.id.widget_tasks_overflow, View.GONE)
            }
            removeAllViews(R.id.widget_tasks_list)
            visibleRows.forEachIndexed { index, row ->
                addView(
                    R.id.widget_tasks_list,
                    taskRow(context, row, showDivider = index < visibleRows.lastIndex),
                )
            }
            val empty = visibleRows.isEmpty()
            setViewVisibility(R.id.widget_tasks_list, if (empty) View.GONE else View.VISIBLE)
            setViewVisibility(R.id.widget_tasks_empty, if (empty) View.VISIBLE else View.GONE)
        }
    }

    /** The circle completes the task; the title opens the Todo list (memex://open_todo). */
    private fun taskRow(context: Context, row: WidgetRow, showDivider: Boolean): RemoteViews {
        val task = row.task
        val todayLabel = context.getString(R.string.widget_today)
        return RemoteViews(context.packageName, R.layout.widget_task_row).apply {
            setTextViewText(R.id.widget_task_title, task.title)
            setTextViewText(R.id.widget_task_time, formatTaskTimeLabel(todayLabel, row))
            setTextColor(
                R.id.widget_task_time,
                context.getColor(if (row.overdue) R.color.widget_amber else R.color.widget_secondary),
            )
            setViewVisibility(R.id.widget_task_divider, if (showDivider) View.VISIBLE else View.GONE)
            setContentDescription(R.id.widget_task_check, context.getString(R.string.widget_task_complete, task.title))
            setOnClickPendingIntent(
                R.id.widget_task_check,
                floatingChat(context, MODE_TODO_COMPLETE + task.id, REQUEST_TASK_CHECK + taskRequestSuffix(task.id)),
            )
            setOnClickPendingIntent(R.id.widget_task_title, openTodo(context, REQUEST_TASK_TITLE + taskRequestSuffix(task.id)))
        }
    }

    private fun taskRequestSuffix(taskId: String): Int = taskId.hashCode() and 0x00FFFFFF

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
