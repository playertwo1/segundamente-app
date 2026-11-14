package com.memexlab.memex.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import java.time.Instant

/**
 * Home-screen widget "Segunda Mente" (F15-03 to F15-05). Taps open the floating sheets or the
 * Todo list. The only data it reads is the Todo snapshot in its own preferences (F15-05), and
 * it refreshes on that snapshot's push, on date and time changes, and at the next due change.
 */
class SegundaMenteWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        render(context, manager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        manager.updateAppWidget(appWidgetId, WidgetLayouts.views(context, minHeightDp(newOptions)))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            ACTION_REFRESH,
            -> refreshAll(context)
        }
    }

    companion object {
        /** Inexact alarm at the next midnight or due time (F15-05); no exact-alarm permission. */
        private const val ACTION_REFRESH = "com.memexlab.memex.widget.REFRESH"
        private const val REQUEST_REFRESH = 30

        /** Redraws every placed widget from the stored snapshot and schedules the next change. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            render(context, manager, widgetIds(context, manager))
        }

        private fun render(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
            for (id in appWidgetIds) {
                manager.updateAppWidget(id, WidgetLayouts.views(context, minHeightDp(manager.getAppWidgetOptions(id))))
            }
            scheduleNextChange(context, hasWidgets = appWidgetIds.isNotEmpty())
        }

        private fun widgetIds(context: Context, manager: AppWidgetManager): IntArray =
            manager.getAppWidgetIds(ComponentName(context, SegundaMenteWidgetProvider::class.java))

        private fun scheduleNextChange(context: Context, hasWidgets: Boolean) {
            val alarms = context.getSystemService(AlarmManager::class.java)
            val pending = refreshIntent(context)
            if (!hasWidgets) {
                alarms.cancel(pending)
                return
            }
            val next = TodoWidgetSnapshot.nextChangeMillis(TodoWidgetSnapshot.load(context), Instant.now())
            alarms.set(AlarmManager.RTC, next, pending)
        }

        private fun refreshIntent(context: Context): PendingIntent {
            val intent = Intent(context, SegundaMenteWidgetProvider::class.java).setAction(ACTION_REFRESH)
            return PendingIntent.getBroadcast(
                context,
                REQUEST_REFRESH,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun minHeightDp(options: Bundle): Int =
            options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
    }
}
