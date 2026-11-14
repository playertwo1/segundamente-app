package com.memexlab.memex.channels

import android.app.Activity
import com.memexlab.memex.widget.SegundaMenteWidgetProvider
import com.memexlab.memex.widget.TodoWidgetSnapshot
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `com.memexlab.memex/todo_widget` (F15-05): Dart pushes the widget's Todo snapshot (only the
 * fields the widget shows, see TodoWidgetSnapshotService) and this side stores it in the app's
 * private preferences, then redraws the widget.
 */
object TodoWidgetChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/todo_widget"

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        val context = activity.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSnapshot" -> {
                    val json = call.arguments as? String
                    if (json == null) {
                        result.error("bad_snapshot", "The Todo snapshot must be a JSON string.", null)
                    } else {
                        TodoWidgetSnapshot.save(context, json)
                        SegundaMenteWidgetProvider.refreshAll(context)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
