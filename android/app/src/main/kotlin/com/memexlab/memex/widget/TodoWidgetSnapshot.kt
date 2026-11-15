package com.memexlab.memex.widget

import android.content.Context
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/** One task of the Todo snapshot, as the widget shows it (F15-05). */
data class WidgetTask(
    val id: String,
    val title: String,
    val dueDate: LocalDate,
    val dueTime: LocalTime?,
    val zone: ZoneId,
)

/** A widget row: the task and whether it is overdue at the time it was chosen. */
data class WidgetRow(val task: WidgetTask, val overdue: Boolean)

/**
 * The home-screen Todo snapshot pushed by Dart (F15-05, D8). It lives in the app's
 * private preferences, so it is never read by another app. Dart sends the open,
 * dated tasks only; this side chooses the rows for "now", so the rows roll over
 * after midnight without a new push.
 */
internal object TodoWidgetSnapshot {
    // Written by AgentBackgroundPlugin (todo_widget channel), read here.
    private const val PREFS = "todo_widget_snapshot"
    private const val KEY = "snapshot"
    private const val DEFAULT_ZONE = "America/Sao_Paulo"

    const val MAX_ROWS = 3

    // Earliest date first; a task without a time after the timed ones of its day.
    private val byDue = compareBy<WidgetRow>({ it.task.dueDate }, { it.task.dueTime ?: LocalTime.MAX })

    fun load(context: Context): List<WidgetTask> =
        prefs(context).getString(KEY, null)?.let { parse(it) } ?: emptyList()

    /** Tasks from the snapshot JSON; a malformed entry is skipped, never shown. */
    fun parse(raw: String): List<WidgetTask> {
        val items = JSONObject(raw).optJSONArray("items") ?: return emptyList()
        return (0 until items.length()).mapNotNull { index ->
            try {
                val item = items.getJSONObject(index)
                WidgetTask(
                    id = item.getString("id"),
                    title = item.getString("title"),
                    dueDate = LocalDate.parse(item.getString("dueDate")),
                    dueTime = if (item.isNull("dueTime")) null else LocalTime.parse(item.getString("dueTime")),
                    zone = ZoneId.of(item.getString("timeZone")),
                )
            } catch (error: Exception) {
                null
            }
        }
    }

    /** Overdue tasks first, then today's by time, at most [MAX_ROWS], for [now]. */
    fun rows(tasks: List<WidgetTask>, now: Instant): List<WidgetRow> {
        val rows = tasks.mapNotNull { task ->
            val local = ZonedDateTime.ofInstant(now, task.zone)
            val today = local.toLocalDate()
            when {
                task.dueDate.isBefore(today) -> WidgetRow(task, overdue = true)
                task.dueDate.isAfter(today) -> null
                // Same rule as TodoScheduleCalculator.statusFor: a timed task is overdue once its time has passed.
                task.dueTime != null && !task.dueTime.isAfter(local.toLocalTime()) -> WidgetRow(task, overdue = true)
                else -> WidgetRow(task, overdue = false)
            }
        }
        val (overdue, today) = rows.partition { it.overdue }
        return (overdue.sortedWith(byDue) + today.sortedWith(byDue)).take(MAX_ROWS)
    }

    /**
     * The next instant the rows can change: midnight in a task's zone, or a due
     * time that is still ahead. The inexact alarm is set to this.
     */
    fun nextChangeMillis(tasks: List<WidgetTask>, now: Instant): Long {
        val zones = listOf(ZoneId.of(DEFAULT_ZONE)) + tasks.map { it.zone }
        val midnights = zones.map { zone ->
            ZonedDateTime.ofInstant(now, zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
        }
        val dueTimes = tasks.mapNotNull { task ->
            task.dueTime?.let { ZonedDateTime.of(task.dueDate, it, task.zone).toInstant() }
        }
        return (midnights + dueTimes).filter { it.isAfter(now) }.min().toEpochMilli()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
