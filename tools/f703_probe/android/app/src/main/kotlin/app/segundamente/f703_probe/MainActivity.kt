package app.segundamente.f703_probe

import android.media.AudioAttributes
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Probe only: the system speech engine with a selectable audio usage, so the
 * echo canceller can be compared against media and voice-call playback.
 * `speak` answers {startMs, completed} when the utterance ends or is stopped.
 */
class MainActivity : FlutterActivity() {
    private var tts: TextToSpeech? = null
    private var pending: MethodChannel.Result? = null
    private var utterance = 0
    private var askedAt = 0L
    private var startMs = -1L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "f703/tts")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> speak(
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("voiceCall") ?: false,
                        result,
                    )
                    "stop" -> {
                        utterance++
                        tts?.stop()
                        finish(false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun speak(text: String, voiceCall: Boolean, result: MethodChannel.Result) {
        finish(false)
        pending = result
        val id = (++utterance).toString()
        val engine = tts
        if (engine != null) {
            start(engine, text, voiceCall, id)
            return
        }
        tts = TextToSpeech(applicationContext) { status ->
            val created = tts
            if (status == TextToSpeech.SUCCESS && created != null && id == utterance.toString()) {
                start(created, text, voiceCall, id)
            } else {
                pending?.error("TTS_INIT_FAILED", "status $status", null)
                pending = null
            }
        }
    }

    private fun start(engine: TextToSpeech, text: String, voiceCall: Boolean, id: String) {
        engine.language = Locale.forLanguageTag("pt-BR")
        engine.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(
                    if (voiceCall) AudioAttributes.USAGE_VOICE_COMMUNICATION
                    else AudioAttributes.USAGE_MEDIA
                )
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                startMs = SystemClock.elapsedRealtime() - askedAt
            }

            override fun onDone(utteranceId: String?) = main(utteranceId) { finish(true) }

            override fun onStop(utteranceId: String?, interrupted: Boolean) =
                main(utteranceId) { finish(false) }

            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) = main(utteranceId) { finish(false) }
        })
        startMs = -1
        askedAt = SystemClock.elapsedRealtime()
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
    }

    private fun main(utteranceId: String?, action: () -> Unit) = runOnUiThread {
        if (utteranceId == utterance.toString()) action()
    }

    private fun finish(completed: Boolean) {
        pending?.success(mapOf("startMs" to startMs, "completed" to completed))
        pending = null
    }

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
