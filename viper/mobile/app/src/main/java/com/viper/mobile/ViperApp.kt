package com.viper.mobile

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.viper.mobile.data.Store
import com.viper.mobile.net.Conn
import com.viper.mobile.net.Event
import com.viper.mobile.net.ViperClient
import com.viper.mobile.voice.Recorder
import com.viper.mobile.voice.Speaker
import com.viper.mobile.voice.extractCommand
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import org.json.JSONObject
import java.util.UUID

data class Msg(val localId: String, val role: String, val text: String, val status: String = "done", val tools: List<String> = emptyList(), val requestId: String? = null)

class ViperApp : Application() {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    lateinit var store: Store; private set
    lateinit var client: ViperClient; private set
    lateinit var speaker: Speaker; private set
    lateinit var recorder: Recorder; private set

    val messages = MutableStateFlow<List<Msg>>(emptyList())
    val notifications = MutableStateFlow<List<JSONObject>>(emptyList())
    val pendingConfirm = MutableStateFlow<JSONObject?>(null)
    val pendingSms = MutableStateFlow<JSONObject?>(null)
    val thinking = MutableStateFlow(false)
    val listening = MutableStateFlow(false)
    val speaking = MutableStateFlow(false)
    val micLevel = MutableStateFlow(0f)
    val transcript = MutableStateFlow("")
    val coreState = MutableStateFlow("offline")
    val snapshot = MutableStateFlow<JSONObject?>(null)
    var foreground = false; private set
    private val voiceRequests = mutableSetOf<String>()
    private var awaitingCommandUntil = 0L

    override fun onCreate() {
        super.onCreate()
        instance = this
        store = Store(this)
        client = ViperClient(store, scope)
        speaker = Speaker(this).also { it.onSpeaking = { s -> speaking.value = s } }
        recorder = Recorder(scope).also { it.onLevel = { l -> micLevel.value = l } }
        createChannels()
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) { foreground = true; client.connect() }
            override fun onStop(owner: LifecycleOwner) { foreground = false; if (!store.stayConnected && !store.handsFree) client.disconnect() }
        })
        scope.launch { client.events.collect { handleEvent(it) } }
        scope.launch {
            combine(client.state, thinking, listening, speaking, pendingConfirm) { c, t, l, s, pc ->
                when { c != Conn.ONLINE -> "offline"; pc != null -> "warning"; s -> "speaking"; l -> "listening"; t -> "thinking"; else -> "idle" }
            }.collect { coreState.value = it }
        }
        scope.launch { client.state.collect { if (it == Conn.ONLINE) refreshSnapshot() } }
    }

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_ALERTS, "VIPER alerts", NotificationManager.IMPORTANCE_HIGH).apply { description = "Notifications sent by VIPER on your PC" })
        nm.createNotificationChannel(NotificationChannel(CH_SERVICE, "VIPER connection", NotificationManager.IMPORTANCE_LOW).apply { description = "Shown while VIPER Mobile stays connected or listens hands-free" })
    }

    fun notifyUser(title: String, body: String, id: Int = (System.currentTimeMillis() % 100000).toInt()) {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(this, CH_ALERTS).setSmallIcon(R.drawable.ic_stat_viper).setContentTitle(title).setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body)).setContentIntent(pi).setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH).build()
        NotificationManagerCompat.from(this).notify(id, n)
    }

    private fun handleEvent(e: Event) {
        val d = e.data
        when (e.type) {
            "notification" -> {
                notifications.update { (listOf(d) + it).take(100) }
                store.lastNotificationTs = maxOf(store.lastNotificationTs, d.optLong("created_at", System.currentTimeMillis()))
                if (!foreground || d.optBoolean("missed")) notifyUser("VIPER: ${d.optString("title")}", d.optString("body"))
            }
            "chat.token" -> { thinking.value = false; updateByRequest(d.optString("requestId")) { it.copy(text = it.text + d.optString("text"), status = "streaming") } }
            "chat.tool" -> updateByRequest(d.optString("requestId")) { m ->
                val label = d.optString("name").replace('_', ' ') + if (d.optString("state") == "running") "…" else " — " + (d.optString("summary").ifBlank { d.optString("state") })
                m.copy(tools = m.tools.filter { !it.startsWith(d.optString("name").replace('_', ' ')) } + label)
            }
            "chat.done" -> {
                thinking.value = false
                val rid = d.optString("requestId")
                val content = d.optJSONObject("message")?.optString("content") ?: ""
                if (!d.optBoolean("silent")) updateByRequest(rid) { it.copy(text = content, status = "done") } else { speaker.stop(); updateByRequest(rid) { it.copy(text = "(stopped)", status = "done") } }
                if (rid in voiceRequests) { voiceRequests.remove(rid); if (store.speakReplies && content.isNotBlank() && !d.optBoolean("silent")) speak(content) }
            }
            "chat.error", "chat.cancelled" -> { thinking.value = false; updateByRequest(d.optString("requestId")) { it.copy(text = d.optString("error", "Stopped"), status = "error") } }
            "confirm.request" -> { pendingConfirm.value = d; if (!foreground) notifyUser("Approval needed", d.optString("title")) }
            "confirm.closed" -> if (pendingConfirm.value?.optString("id") == d.optString("id")) pendingConfirm.value = null
            "system.sample" -> snapshot.value = d
            "voice.stop" -> speaker.stop()
            "sms.send" -> { pendingSms.value = d; if (!foreground) notifyUser("Your PC wants to send an SMS", "To ${d.optString("to")}. Open VIPER Mobile to approve or decline.") }
            "transfer.available" -> notifyUser("File ready from your PC", d.optString("name"))
            "queue.sent" -> messages.update { list -> list.map { if (it.localId == d.optString("localId")) it.copy(requestId = d.optString("requestId"), status = "streaming", text = "") else it } }.also { store.conversationId = d.optString("conversationId") }
        }
    }
    private fun updateByRequest(rid: String, f: (Msg) -> Msg) = messages.update { list -> list.map { if (it.requestId == rid && it.role == "viper") f(it) else it } }

    // ---------- chat ----------
    fun send(text: String, voice: Boolean = false, attachments: org.json.JSONArray? = null) {
        if (text.isBlank() && attachments == null) return
        val localId = UUID.randomUUID().toString()
        messages.update { it + Msg(UUID.randomUUID().toString(), "user", text.ifBlank { "(image)" }) }
        val body = JSONObject().put("text", text).put("voice", voice).put("localId", localId)
        store.conversationId?.let { body.put("conversationId", it) }
        attachments?.let { body.put("attachments", it) }
        if (client.state.value != Conn.ONLINE) {
            store.enqueue(body)
            messages.update { it + Msg(localId, "viper", "Your PC isn't reachable right now. This request is queued and will be sent when the connection returns.", status = "queued") }
            return
        }
        messages.update { it + Msg(localId, "viper", "", status = "streaming") }
        thinking.value = true
        scope.launch {
            try {
                val r = client.post("/api/v1/chat", body)
                val rid = r.getString("requestId"); store.conversationId = r.getString("conversationId")
                if (voice) voiceRequests.add(rid)
                messages.update { list -> list.map { if (it.localId == localId) it.copy(requestId = rid) else it } }
                for (ev in client.replay(rid)) handleEvent(ev)
            } catch (e: Exception) {
                thinking.value = false
                messages.update { list -> list.map { if (it.localId == localId) it.copy(text = "Could not send: ${e.message}", status = "error") else it } }
            }
        }
    }
    fun newConversation() { store.conversationId = null; messages.value = emptyList() }
    fun cancel() { val rid = messages.value.lastOrNull { it.status == "streaming" }?.requestId ?: return; scope.launch { runCatching { client.post("/api/v1/chat/cancel", JSONObject().put("requestId", rid)) } } }

    fun speak(text: String) {
        scope.launch {
            if (store.usePcVoice && client.state.value == Conn.ONLINE) {
                try { val wav = client.postForBytes("/api/v1/voice/speak", JSONObject().put("text", text)); speaker.playWav(wav); return@launch } catch (_: Exception) { }
            }
            speaker.speakLocal(text)
        }
    }

    // ---------- voice ----------
    fun pttStart(): Boolean { if (!hasMic()) return false; speaker.stop(); recorder.start(); listening.value = true; return true }
    fun pttStop() {
        listening.value = false
        scope.launch {
            val wav = recorder.stopAndGetWav() ?: return@launch
            transcribeAndSend(wav, requireWake = false)
        }
    }
    private suspend fun transcribe(wav: ByteArray): String? = try {
        transcript.value = "Transcribing…"
        client.postBytes("/api/v1/voice/transcribe", wav, "audio/wav").optString("text").trim().ifBlank { null }
    } catch (e: Exception) { transcript.value = "Speech recognition unavailable: ${e.message}"; null }

    suspend fun transcribeAndSend(wav: ByteArray, requireWake: Boolean) {
        if (client.state.value != Conn.ONLINE) { transcript.value = "PC offline — voice needs the PC's speech engine."; return }
        val text = transcribe(wav) ?: return
        if (!requireWake || System.currentTimeMillis() < awaitingCommandUntil) { awaitingCommandUntil = 0; transcript.value = text; send(text, voice = true); return }
        val cmd = extractCommand(text) ?: run { transcript.value = "(heard, no wake word) $text"; return }
        if (cmd.isBlank()) { awaitingCommandUntil = System.currentTimeMillis() + 8000; transcript.value = "Listening…"; speaker.speakLocal("Yes?"); return }
        transcript.value = text; send(cmd, voice = true)
    }
    fun startHandsFree() { if (!hasMic()) return; listening.value = true; recorder.listen { wav -> transcribeAndSend(wav, requireWake = true) } }
    fun stopHandsFree() { recorder.stop(); listening.value = false }
    fun hasMic() = ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    // ---------- approvals ----------
    fun answerConfirm(approved: Boolean) {
        val c = pendingConfirm.value ?: return; pendingConfirm.value = null
        scope.launch { runCatching { client.post("/api/v1/confirm/${c.getString("id")}", JSONObject().put("approved", approved)) } }
    }
    fun answerSms(approved: Boolean) {
        val s = pendingSms.value ?: return; pendingSms.value = null
        scope.launch {
            var result = JSONObject().put("id", s.optString("id")).put("sent", false)
            if (approved && store.smsBridge && ContextCompat.checkSelfPermission(this@ViperApp, android.Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                try {
                    val sms = if (Build.VERSION.SDK_INT >= 31) getSystemService(SmsManager::class.java) else @Suppress("DEPRECATION") SmsManager.getDefault()
                    val parts = sms.divideMessage(s.optString("body"))
                    sms.sendMultipartTextMessage(s.optString("to"), null, parts, null, null)
                    result.put("sent", true)
                } catch (e: Exception) { result.put("error", e.message) }
            } else if (approved) result.put("error", "SMS bridge disabled or permission missing on the phone")
            else result.put("error", "Declined on phone")
            runCatching { client.post("/api/v1/sms/result", result) }
        }
    }

    suspend fun refreshSnapshot() { runCatching { snapshot.value = client.getObj("/api/v1/system/snapshot") } }

    companion object {
        const val CH_ALERTS = "viper_alerts"; const val CH_SERVICE = "viper_service"
        lateinit var instance: ViperApp; private set
    }
}
