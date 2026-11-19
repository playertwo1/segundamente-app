package com.memexlab.memex.channels

import android.app.Activity
import android.content.Intent
import com.memexlab.memex.ChatBubble
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.MainActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * `com.memexlab.memex/floating_chat` (F15-02): the mode a floating-chat launch asked for,
 * plus close and open-in-app. The Dart side pulls the mode with `takePendingMode`;
 * `notifyOpen` only tells it that a mode is waiting.
 */
object FloatingChatChannelHandler {
    private const val CHANNEL = "com.memexlab.memex/floating_chat"

    private var channel: MethodChannel? = null
    private var pendingMode: String? = null

    /** Chat modes (F15-02), capture modes (F15-04) and Todo modes (F15-05); anything else means no pending mode. */
    private val MODES = setOf("type", "bubble", "talk", "note", "photo", "paste", "todo_add")
    private const val TODO_COMPLETE_PREFIX = "todo_complete:"

    fun setPendingMode(mode: String?) {
        pendingMode = mode?.takeIf {
            it in MODES || (it.startsWith(TODO_COMPLETE_PREFIX) && it.length > TODO_COMPLETE_PREFIX.length)
        }
    }

    fun notifyOpen() {
        channel?.invokeMethod("open", null)
    }

    fun notifyMainOpened() {
        channel?.invokeMethod("mainOpened", null)
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "bubbleStatus" -> result.success(ChatBubble.status(activity))
                    "hideBubble" -> result.success(ChatBubble.hide(activity))
                    "showBubble", "openBubbleSettings" -> {
                        try {
                            if (call.method == "showBubble") {
                                result.success(ChatBubble.show(activity))
                            } else {
                                ChatBubble.openSettings(activity, call.argument<Boolean>("notifications") == true)
                                result.success(null)
                            }
                        } catch (error: RuntimeException) {
                            result.error("chat_bubble", error.message, null)
                        }
                    }
                    "takePendingMode" -> {
                        result.success(pendingMode)
                        pendingMode = null
                    }
                    // Only the floating sheet may close itself or hand off to the app; never the MainActivity.
                    "close" -> {
                        if (activity is FloatingChatActivity) activity.finish()
                        result.success(null)
                    }
                    "openInApp" -> {
                        if (activity is FloatingChatActivity) {
                            activity.startActivity(
                                Intent(activity, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
