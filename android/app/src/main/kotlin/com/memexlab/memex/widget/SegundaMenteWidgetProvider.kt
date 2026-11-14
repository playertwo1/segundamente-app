package com.memexlab.memex.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle

/**
 * Home-screen widget "Segunda Mente" (F15-03, F15-04). Its taps only open the floating sheet
 * (chat or capture): it reads no app data, so it shows no personal content and needs no network
 * or periodic update.
 */
class SegundaMenteWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) {
            manager.updateAppWidget(id, WidgetLayouts.views(context, minHeightDp(manager.getAppWidgetOptions(id))))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        manager.updateAppWidget(appWidgetId, WidgetLayouts.views(context, minHeightDp(newOptions)))
    }

    private fun minHeightDp(options: Bundle): Int =
        options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
}
