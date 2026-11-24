package com.memexlab.memex

import android.content.Intent
import android.os.Bundle
import com.memexlab.memex.channels.ChannelRegistrar
import com.memexlab.memex.channels.FloatingChatChannelHandler
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

/** Translucent chat sheet over the home screen (F15-02). Shares the engine with MainActivity. */
open class FloatingChatActivity : FlutterFragmentActivity() {

    companion object {
        const val EXTRA_MODE = "floating_chat_mode"
        var current: WeakReference<FloatingChatActivity>? = null
    }

    protected open val defaultMode: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // One engine, one host: the full app gives way to the sheet.
        SharedFlutterEngine.releaseHost(MainActivity.current?.get())
        SharedFlutterEngine.releaseHost(current?.get())
        FloatingChatChannelHandler.setPendingMode(intent?.getStringExtra(EXTRA_MODE) ?: defaultMode)
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        FloatingChatChannelHandler.setPendingMode(intent.getStringExtra(EXTRA_MODE) ?: defaultMode)
        FloatingChatChannelHandler.notifyOpen()
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }

    override fun getCachedEngineId(): String = SharedFlutterEngine.ensure(this)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ChannelRegistrar.registerAll(flutterEngine, this)
        FloatingChatChannelHandler.notifyOpen()
    }
}
