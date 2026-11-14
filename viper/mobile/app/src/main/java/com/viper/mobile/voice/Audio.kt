package com.viper.mobile.voice

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.speech.tts.TextToSpeech
import kotlinx.coroutines.*
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.sqrt

const val RATE = 16000

fun pcmToWav(pcm: ByteArray, rate: Int = RATE): ByteArray {
    val b = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
    b.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVE".toByteArray()).put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
        .putInt(rate).putInt(rate * 2).putShort(2).putShort(16).put("data".toByteArray()).putInt(pcm.size).put(pcm)
    return b.array()
}

fun rms(buf: ShortArray, n: Int): Double { var s = 0.0; for (i in 0 until n) { val v = buf[i] / 32768.0; s += v * v }; return sqrt(s / maxOf(1, n)) }

/**
 * Microphone capture at 16 kHz mono. Push-to-talk via start()/stop(); hands-free via
 * listen(), which segments speech with an adaptive energy VAD and hands each utterance
 * (as WAV) to the callback. Audio is only sent to the paired PC, never to a cloud service.
 */
class Recorder(private val scope: CoroutineScope) {
    private var job: Job? = null
    private val pcm = ByteArrayOutputStream()
    @Volatile var level = 0f; private set
    var onLevel: ((Float) -> Unit)? = null

    @SuppressLint("MissingPermission")
    private fun open(): AudioRecord {
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, RATE))
        if (rec.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("Microphone unavailable")
        return rec
    }

    fun start() {
        stop(); pcm.reset()
        job = scope.launch(Dispatchers.IO) {
            val rec = open(); val buf = ShortArray(1600)
            rec.startRecording()
            try {
                while (isActive) {
                    val n = rec.read(buf, 0, buf.size); if (n <= 0) continue
                    level = (rms(buf, n) * 10).toFloat().coerceIn(0f, 1f); onLevel?.invoke(level)
                    val bb = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN); for (i in 0 until n) bb.putShort(buf[i]); pcm.write(bb.array())
                }
            } finally { rec.stop(); rec.release(); level = 0f; onLevel?.invoke(0f) }
        }
    }
    suspend fun stopAndGetWav(): ByteArray? { job?.cancelAndJoin(); job = null; val data = pcm.toByteArray(); return if (data.size < RATE) null else pcmToWav(data) }
    fun stop() { job?.cancel(); job = null }

    /** Continuous VAD-gated listening; returns when cancelled. */
    fun listen(sensitivity: Double = 0.5, onUtterance: suspend (ByteArray) -> Unit) {
        stop()
        job = scope.launch(Dispatchers.IO) {
            val rec = open(); val buf = ShortArray(480) // 30 ms frames
            var noise = 0.004; var inSpeech = false; var silenceMs = 0; var speechMs = 0
            val pre = ArrayDeque<ByteArray>(); val utt = ByteArrayOutputStream()
            rec.startRecording()
            try {
                while (isActive) {
                    val n = rec.read(buf, 0, buf.size); if (n <= 0) continue
                    val r = rms(buf, n); level = (r * 10).toFloat().coerceIn(0f, 1f); onLevel?.invoke(level)
                    val bb = ByteBuffer.allocate(n * 2).order(ByteOrder.LITTLE_ENDIAN); for (i in 0 until n) bb.putShort(buf[i]); val frame = bb.array()
                    val loud = r > maxOf(0.006, noise * (4.5 - sensitivity * 3))
                    if (!inSpeech && !loud) noise = noise * 0.995 + r * 0.005
                    pre.addLast(frame); while (pre.size > 12) pre.removeFirst()
                    if (loud) { speechMs += 30; silenceMs = 0; if (!inSpeech && speechMs > 90) { inSpeech = true; utt.reset(); pre.forEach { utt.write(it) } } }
                    else { speechMs = maxOf(0, speechMs - 30); if (inSpeech) silenceMs += 30 }
                    if (inSpeech) {
                        utt.write(frame)
                        if (silenceMs > 900 || utt.size() > RATE * 2 * 15) {
                            inSpeech = false; silenceMs = 0; speechMs = 0
                            val data = utt.toByteArray()
                            if (data.size > RATE * 2 * 0.35) { val wav = pcmToWav(data); launch { onUtterance(wav) } }
                        }
                    }
                }
            } finally { rec.stop(); rec.release(); level = 0f; onLevel?.invoke(0f) }
        }
    }
}

/** Plays VIPER's voice: the PC's Piper WAV when available, otherwise Android's own TTS (British English). */
class Speaker(private val context: Context) {
    private var player: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    @Volatile var speaking = false; private set
    var onSpeaking: ((Boolean) -> Unit)? = null

    init { tts = TextToSpeech(context) { s -> ttsReady = s == TextToSpeech.SUCCESS; if (ttsReady) tts?.language = Locale.UK } }

    fun playWav(bytes: ByteArray, onDone: () -> Unit = {}) {
        stop()
        val f = File(context.cacheDir, "viper-speech.wav"); f.writeBytes(bytes)
        player = MediaPlayer().apply {
            setDataSource(f.absolutePath); prepare()
            setOnCompletionListener { speaking = false; onSpeaking?.invoke(false); onDone() }
            start()
        }
        speaking = true; onSpeaking?.invoke(true)
    }
    fun speakLocal(text: String, onDone: () -> Unit = {}) {
        if (!ttsReady) { onDone(); return }
        stop(); speaking = true; onSpeaking?.invoke(true)
        tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?) { speaking = false; onSpeaking?.invoke(false); onDone() }
            @Deprecated("Deprecated in Java") override fun onError(id: String?) { speaking = false; onSpeaking?.invoke(false); onDone() }
        })
        tts?.speak(text.replace(Regex("```[\\s\\S]*?```"), " code shown on screen ").replace(Regex("[*#`_>|]"), ""), TextToSpeech.QUEUE_FLUSH, null, "viper")
    }
    fun stop() { try { player?.stop(); player?.release() } catch (_: Exception) { }; player = null; tts?.stop(); if (speaking) { speaking = false; onSpeaking?.invoke(false) } }
    fun shutdown() { stop(); tts?.shutdown() }
}

/** Accepts the wake phrase and common mis-hearings of it. Returns the command after the wake word, "" for wake-only, or null if absent. */
fun extractCommand(transcript: String, wakeWords: List<String> = listOf("hey viper", "viper")): String? {
    val norm = transcript.lowercase().replace(Regex("[^a-z0-9 ]"), " ").replace(Regex("\\s+"), " ").trim()
    for (w in wakeWords.sortedByDescending { it.length }) for (v in listOf(w, w.replace("viper", "vyper"), w.replace("viper", "wiper"), w.replace("viper", "piper"))) {
        val i = norm.indexOf(v)
        if (i in 0..12) return norm.substring(i + v.length).trim()
    }
    return null
}
