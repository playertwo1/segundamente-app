package com.memexlab.memex.dev

import android.content.Intent
import android.os.Bundle
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.MainActivity
import com.memexlab.memex.SharedFlutterEngine
import com.memexlab.memex.channels.ChannelRegistrar
import com.memexlab.memex.channels.FloatingChatChannelHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Prototype A (F15-07): the bubble's activity. It reuses the shared engine and the chat route of
 * FloatingChatActivity, which stays in src/main. Its "close" finishes this host (the bubble collapses).
 * shortcut: "close" and "openInApp" are overridden here because the base handler only knows FloatingChatActivity.
 */
class CapsuleBubbleHostActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "com.memexlab.memex/floating_chat"
    }

    private var pendingMode: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        SharedFlutterEngine.releaseHost(MainActivity.current?.get())
        SharedFlutterEngine.releaseHost(FloatingChatActivity.current?.get())
        pendingMode = intent?.getStringExtra(FloatingChatActivity.EXTRA_MODE)
        FloatingChatChannelHandler.setPendingMode(pendingMode)
        super.onCreate(savedInstanceState)
        CapsuleLog.event("bubble host created")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingMode = intent.getStringExtra(FloatingChatActivity.EXTRA_MODE)
        FloatingChatChannelHandler.setPendingMode(pendingMode)
        FloatingChatChannelHandler.notifyOpen()
    }

    // onResume/onPause approximate "expandida" and "recolhida"; confirm the bubble visually on the S25.
    override fun onResume() {
        super.onResume()
        CapsuleLog.event("bubble expanded")
    }

    override fun onPause() {
        CapsuleLog.event("bubble collapsed")
        super.onPause()
    }

    override fun onDestroy() {
        CapsuleLog.event("bubble host destroyed")
        super.onDestroy()
    }

    override fun getCachedEngineId(): String = SharedFlutterEngine.ensure(this)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ChannelRegistrar.registerAll(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingMode" -> {
                    result.success(pendingMode)
                    pendingMode = null
                }
                "close" -> {
                    finish()
                    result.success(null)
                }
                "openInApp" -> {
                    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        FloatingChatChannelHandler.notifyOpen()
    }
}
