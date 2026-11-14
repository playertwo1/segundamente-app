package com.memexlab.memex.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

/**
 * Home-screen widget "Segunda Mente" (F15-03). Its taps only open the F15-02 floating chat:
 * it reads no app data, so it shows no personal content and needs no network or periodic update.
 */
class SegundaMenteWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) manager.updateAppWidget(id, WidgetLayouts.views(context))
    }
}
