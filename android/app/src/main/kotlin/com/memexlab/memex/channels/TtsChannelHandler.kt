package com.memexlab.memex.channels

import android.app.Activity
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Handles `com.memexlab.memex/tts` MethodChannel: the system speech engine for
 * the duplex voice screen (F7-03).
 *
 * `speak` answers `true` when the utterance ends by itself and `false` when it
 * was stopped. The engine is created on the first `speak` and released by
 * `shutdown`.
 */
class TtsChannelHandler(private val activity: Activity) {

    companion object {
        private const val CHANNEL = "com.memexlab.memex/tts"

        fun register(flutterEngine: FlutterEngine, activity: Activity) {
            val handler = TtsChannelHandler(activity)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "speak" -> handler.speak(
                            call.argument<String>("text") ?: "",
                            call.argument<String>("locale"),
                            result,
                        )
                        "stop" -> {
                            handler.stop()
                            result.success(null)
                        }
                        "shutdown" -> {
                            handler.shutdown()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }
    }

    private var tts: TextToSpeech? = null
    private var ready = false
    private var pending: MethodChannel.Result? = null
    private var utterance = 0

    private fun speak(text: String, locale: String?, result: MethodChannel.Result) {
        finish(false) // a new utterance replaces the one in progress
        pending = result
        val id = (++utterance).toString()
        val engine = tts
        if (engine != null && ready) {
            start(engine, text, locale, id)
            return
        }
        tts?.shutdown()
        ready = false
        tts = TextToSpeech(activity.applicationContext) { status ->
            // Stopped or replaced while the engine was starting: stay silent.
            if (utterance.toString() != id || pending == null) return@TextToSpeech
            val created = tts
            if (status == TextToSpeech.SUCCESS && created != null) {
                ready = true
                start(created, text, locale, id)
            } else {
                fail("TTS_INIT_FAILED", "TextToSpeech init status $status")
            }
        }
    }

    private fun start(engine: TextToSpeech, text: String, locale: String?, id: String) {
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) = onMain(utteranceId) { finish(true) }

            override fun onStop(utteranceId: String?, interrupted: Boolean) =
                onMain(utteranceId) { finish(false) }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) =
                onMain(utteranceId) { fail("TTS_FAILED", "speech engine error") }
        })
        if (locale != null) engine.language = Locale.forLanguageTag(locale)
        // shortcut: text beyond the engine limit (4000 chars) is cut, not queued;
        // split into sentences if long replies show up.
        val spoken = text.take(TextToSpeech.getMaxSpeechInputLength())
        if (engine.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) {
            fail("TTS_FAILED", "speak was rejected")
        }
    }

    /** Engine callbacks arrive on a binder thread; ignore those of older utterances. */
    private fun onMain(utteranceId: String?, action: () -> Unit) {
        activity.runOnUiThread {
            if (utteranceId == utterance.toString()) action()
        }
    }

    private fun stop() {
        utterance++ // invalidates a pending engine start and late callbacks
        tts?.stop()
        finish(false)
    }

    private fun shutdown() {
        stop()
        tts?.shutdown()
        tts = null
        ready = false
    }

    private fun finish(completed: Boolean) {
        pending?.success(completed)
        pending = null
    }

    private fun fail(code: String, message: String) {
        pending?.error(code, message, null)
        pending = null
    }
}
