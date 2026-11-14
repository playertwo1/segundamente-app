package com.memexlab.memex

import android.app.Activity
import android.util.Log
import androidx.fragment.app.FragmentActivity
import com.memexlab.memex.channels.ChannelRegistrar
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * One Flutter engine shared by MainActivity and FloatingChatActivity (F15-02).
 * Two engines would mean two Dart isolates with their own task executor and SQLite.
 */
object SharedFlutterEngine {
    const val ID = "segundamente_main"
    private const val TAG = "SharedFlutterEngine"
    // FlutterFragmentActivity.TAG_FLUTTER_FRAGMENT is private; this is its value.
    private const val FLUTTER_FRAGMENT_TAG = "flutter_fragment"

    fun ensure(activity: Activity): String {
        val cache = FlutterEngineCache.getInstance()
        if (!cache.contains(ID)) {
            val engine = FlutterEngine(activity.applicationContext)
            // Channels must exist before Dart's main() runs, or early calls find no handler.
            ChannelRegistrar.registerAll(engine, activity)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ID, engine)
        }
        return ID
    }

    /**
     * Detaches the host's Flutter fragment synchronously, so its FlutterView stops rendering
     * into the shared engine before the next host attaches to it, then finishes the host.
     */
    fun releaseHost(host: FragmentActivity?) {
        if (host == null || host.isDestroyed) return
        try {
            host.supportFragmentManager.findFragmentByTag(FLUTTER_FRAGMENT_TAG)?.let { fragment ->
                host.supportFragmentManager.beginTransaction().remove(fragment).commitNowAllowingStateLoss()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not detach the Flutter fragment of ${host.javaClass.simpleName}", e)
        }
        host.finish()
    }
}
