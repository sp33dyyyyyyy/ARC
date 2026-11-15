package com.viper.mobile.net

import android.util.Log
import com.viper.mobile.data.Pairing
import com.viper.mobile.data.Store
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

enum class Conn { UNPAIRED, CONNECTING, ONLINE, OFFLINE }
data class Event(val type: String, val data: JSONObject)
class ApiException(val status: Int, message: String) : IOException(message)

/**
 * Connection to the paired PC: HTTPS REST + a WebSocket event stream, both pinned to the PC's
 * certificate and authenticated with the per-device secret. Reconnects with backoff, tries each
 * known address (LAN / VPN), flushes the offline queue and fetches missed notifications.
 */
class ViperClient(private val store: Store, private val scope: CoroutineScope) {
    val state = MutableStateFlow(if (store.pairing == null) Conn.UNPAIRED else Conn.OFFLINE)
    val events = MutableSharedFlow<Event>(extraBufferCapacity = 512)
    val lastError = MutableStateFlow<String?>(null)
    /** When the next automatic reconnect attempt happens (0 = none scheduled). */
    val nextRetryAt = MutableStateFlow(0L)
    private val recent = ArrayDeque<Event>()
    private var client: OkHttpClient? = null
    private var ws: WebSocket? = null
    private var host: String? = null
    private var reconnectJob: Job? = null
    private var backoff = Backoff.START
    private var wanted = false

    private fun pairing(): Pairing? = store.pairing

    private fun buildClient(p: Pairing): OkHttpClient {
        val tm = PinnedTrustManager(p.fingerprint)
        return OkHttpClient.Builder()
            .sslSocketFactory(tm.socketFactory(), tm)
            // Identity is established by the pinned certificate, not by hostname (LAN IPs change).
            .hostnameVerifier { _, _ -> true }
            .connectTimeout(6, TimeUnit.SECONDS).readTimeout(5, TimeUnit.MINUTES).writeTimeout(2, TimeUnit.MINUTES)
            .pingInterval(25, TimeUnit.SECONDS)
            .build()
    }

    fun base(): String = "https://${host ?: candidateHosts().first()}:${pairing()!!.port}"
    private fun candidateHosts(): List<String> {
        val p = pairing() ?: return emptyList()
        return (listOf(store.hostOverride, store.lastHost).filter { it.isNotBlank() } + p.hosts).distinct()
    }

    fun connect() {
        val p = pairing() ?: run { state.value = Conn.UNPAIRED; return }
        wanted = true
        if (state.value == Conn.ONLINE || state.value == Conn.CONNECTING) return
        client = client ?: buildClient(p)
        state.value = Conn.CONNECTING
        scope.launch(Dispatchers.IO) {
            // Find a reachable address first (LAN or VPN).
            var found: String? = null
            for (h in candidateHosts()) {
                try {
                    val req = Request.Builder().url("https://$h:${p.port}/api/v1/hello").build()
                    client!!.newBuilder().connectTimeout(3, TimeUnit.SECONDS).build().newCall(req).execute().use { if (it.isSuccessful) found = h }
                } catch (e: Exception) { lastError.value = e.message }
                if (found != null) break
            }
            if (found == null) {
                // The PC's address may have changed (new DHCP lease): ask the LAN who has our PC's certificate.
                val d = runCatching { Discovery.find(p.fingerprint, p.hosts) }.getOrNull()
                if (d != null && d.port == p.port) {
                    try {
                        val req = Request.Builder().url("https://${d.host}:${p.port}/api/v1/hello").build()
                        client!!.newBuilder().connectTimeout(3, TimeUnit.SECONDS).build().newCall(req).execute().use { if (it.isSuccessful) found = d.host }
                        if (found != null && d.host !in p.hosts) store.pairing = p.copy(hosts = listOf(d.host) + p.hosts.take(7))
                    } catch (e: Exception) { lastError.value = e.message }
                }
            }
            if (found == null) { state.value = Conn.OFFLINE; scheduleReconnect(); return@launch }
            host = found; store.lastHost = found!!
            val req = Request.Builder().url("wss://$found:${p.port}/api/v1/ws").header("Authorization", p.authHeader).build()
            ws = client!!.newWebSocket(req, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    state.value = Conn.ONLINE; backoff = Backoff.START; lastError.value = null; nextRetryAt.value = 0
                    store.lastConnected = System.currentTimeMillis()
                    scope.launch { onOnline() }
                }
                override fun onMessage(webSocket: WebSocket, text: String) {
                    try {
                        val o = JSONObject(text)
                        val e = Event(o.getString("type"), o.optJSONObject("data") ?: JSONObject())
                        if (e.type.startsWith("chat.")) synchronized(recent) { recent.addLast(e); while (recent.size > 400) recent.removeFirst() }
                        events.tryEmit(e)
                    } catch (_: Exception) { }
                }
                // The PC closes with 4001 when it revokes this phone. OkHttp reports the peer's close in
                // onClosing; answer it and act at once instead of waiting for the socket to time out.
                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    webSocket.close(1000, null)
                    if (code == 4001) revoked()
                }
                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (code == 4001 || state.value == Conn.UNPAIRED) { revoked(); return }
                    if (state.value == Conn.ONLINE) store.lastConnected = System.currentTimeMillis()
                    state.value = Conn.OFFLINE; scheduleReconnect()
                }
                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (response?.code == 401) { revoked("The PC no longer recognises this phone. Pair again."); return }
                    if (state.value == Conn.UNPAIRED) return
                    if (state.value == Conn.ONLINE) store.lastConnected = System.currentTimeMillis()
                    lastError.value = t.message; state.value = Conn.OFFLINE; scheduleReconnect()
                }
            })
        }
    }

    private fun revoked(msg: String = "This phone's access was revoked on the PC. Pair again to reconnect.") {
        wanted = false; reconnectJob?.cancel(); ws = null
        lastError.value = msg; store.pairing = null; client = null; host = null
        state.value = Conn.UNPAIRED
    }

    fun disconnect() { wanted = false; reconnectJob?.cancel(); ws?.close(1000, "bye"); ws = null; if (state.value != Conn.UNPAIRED) state.value = Conn.OFFLINE }
    private fun scheduleReconnect() {
        if (!wanted) return
        reconnectJob?.cancel()
        val wait = Backoff.withJitter(backoff)
        nextRetryAt.value = System.currentTimeMillis() + wait
        reconnectJob = scope.launch { delay(wait); backoff = Backoff.next(backoff); connect() }
    }
    /** Retry immediately (user tapped Reconnect, or the phone joined a network). */
    fun reconnectNow() {
        if (pairing() == null) return
        reconnectJob?.cancel(); backoff = Backoff.START; nextRetryAt.value = 0
        if (state.value == Conn.ONLINE) return
        if (state.value == Conn.CONNECTING) state.value = Conn.OFFLINE
        connect()
    }
    fun replay(requestId: String): List<Event> = synchronized(recent) { recent.filter { it.data.optString("requestId") == requestId } }

    private suspend fun onOnline() {
        // Deliver queued requests that were made while offline.
        val q = store.queue()
        if (q.isNotEmpty()) {
            val left = mutableListOf<JSONObject>()
            for (item in q) {
                try { val r = post("/api/v1/chat", item); events.tryEmit(Event("queue.sent", JSONObject().put("localId", item.optString("localId")).put("requestId", r.getString("requestId")).put("conversationId", r.getString("conversationId")))) }
                catch (e: Exception) { left.add(item) }
            }
            store.setQueue(left)
        }
        // Notifications missed while disconnected.
        try {
            val arr = getArr("/api/v1/notifications/since/${store.lastNotificationTs}")
            for (i in 0 until arr.length()) events.tryEmit(Event("notification", arr.getJSONObject(i).put("missed", true)))
        } catch (_: Exception) { }
    }

    // ---------- REST ----------
    private fun request(path: String, method: String, body: RequestBody?): Request {
        val p = pairing() ?: throw ApiException(0, "Not paired")
        return Request.Builder().url(base() + path).header("Authorization", p.authHeader).method(method, body).build()
    }
    private suspend fun exec(req: Request): String = withContext(Dispatchers.IO) {
        val c = client ?: buildClient(pairing()!!).also { client = it }
        c.newCall(req).execute().use { r ->
            val text = r.body?.string() ?: ""
            if (!r.isSuccessful) {
                val msg = try { JSONObject(text).optString("error", "HTTP ${r.code}") } catch (_: Exception) { "HTTP ${r.code}" }
                throw ApiException(r.code, msg)
            }
            text
        }
    }
    suspend fun getObj(path: String) = JSONObject(exec(request(path, "GET", null)))
    suspend fun getArr(path: String) = JSONArray(exec(request(path, "GET", null)))
    suspend fun post(path: String, body: JSONObject = JSONObject()): JSONObject {
        val t = exec(request(path, "POST", body.toString().toRequestBody(JSON)))
        return if (t.trim().startsWith("{")) JSONObject(t) else JSONObject().put("result", t)
    }
    suspend fun patch(path: String, body: JSONObject) = JSONObject(exec(request(path, "PATCH", body.toString().toRequestBody(JSON))))
    suspend fun delete(path: String) { exec(request(path, "DELETE", null)) }
    suspend fun postBytes(path: String, bytes: ByteArray, contentType: String): JSONObject = JSONObject(exec(request(path, "POST", bytes.toRequestBody(contentType.toMediaType()))))
    suspend fun postForBytes(path: String, body: JSONObject): ByteArray = withContext(Dispatchers.IO) {
        val c = client ?: buildClient(pairing()!!)
        c.newCall(request(path, "POST", body.toString().toRequestBody(JSON))).execute().use { r -> if (!r.isSuccessful) throw ApiException(r.code, "HTTP ${r.code}"); r.body!!.bytes() }
    }
    suspend fun getBytes(path: String): ByteArray = withContext(Dispatchers.IO) {
        val c = client ?: buildClient(pairing()!!)
        c.newCall(request(path, "GET", null)).execute().use { r -> if (!r.isSuccessful) throw ApiException(r.code, "HTTP ${r.code}"); r.body!!.bytes() }
    }

    /** Pair with a PC using a scanned QR payload. Tries each advertised address. */
    suspend fun pair(payload: PairingPayload, deviceName: String, onStatus: (String) -> Unit = {}): Pairing = withContext(Dispatchers.IO) {
        if (payload.expiresAt in 1 until System.currentTimeMillis()) throw ApiException(410, "This pairing code has expired. Show a new one on the PC.")
        val tm = PinnedTrustManager(payload.fingerprint)
        // The PC asks its owner to approve the phone before answering, so wait up to two minutes.
        val c = OkHttpClient.Builder().sslSocketFactory(tm.socketFactory(), tm).hostnameVerifier { _, _ -> true }.connectTimeout(5, TimeUnit.SECONDS).readTimeout(120, TimeUnit.SECONDS).build()
        onStatus("Waiting for you to approve this phone on the PC…")
        var lastErr: Exception? = null
        val hosts = (listOf(store.hostOverride).filter { it.isNotBlank() } + payload.hosts).distinct()
        for (h in hosts) {
            try {
                val body = JSONObject().put("token", payload.token).put("deviceName", deviceName).put("platform", "android").toString().toRequestBody(JSON)
                c.newCall(Request.Builder().url("https://$h:${payload.port}/api/v1/pair").post(body).build()).execute().use { r ->
                    val t = r.body?.string() ?: ""
                    if (!r.isSuccessful) throw ApiException(r.code, try { JSONObject(t).optString("error") } catch (_: Exception) { "HTTP ${r.code}" })
                    val o = JSONObject(t)
                    val p = Pairing(o.getString("deviceId"), o.getString("secret"), payload.hosts, payload.port, payload.fingerprint, o.optString("serverName", payload.name))
                    store.pairing = p; store.lastHost = h
                    client = buildClient(p); host = h
                    state.value = Conn.OFFLINE
                    return@withContext p
                }
            } catch (e: ApiException) { throw e } catch (e: Exception) { lastErr = e; Log.w("VIPER", "pair via $h failed: ${e.message}") }
        }
        throw IOException("Could not reach the PC at ${hosts.joinToString()}. Check that both devices are on the same network (or VPN). ${lastErr?.message ?: ""}")
    }

    /** Step-by-step connection check for the offline screen. Each line is a real test result. */
    suspend fun diagnose(networkUp: Boolean): List<Pair<String, Boolean>> = withContext(Dispatchers.IO) {
        val out = mutableListOf<Pair<String, Boolean>>()
        val p = pairing() ?: return@withContext listOf("This phone is not paired" to false)
        out += (if (networkUp) "Phone has a network connection" else "Phone has no network connection (Wi-Fi or mobile data)") to networkUp
        val tm = PinnedTrustManager(p.fingerprint)
        val c = OkHttpClient.Builder().sslSocketFactory(tm.socketFactory(), tm).hostnameVerifier { _, _ -> true }.connectTimeout(3, TimeUnit.SECONDS).readTimeout(5, TimeUnit.SECONDS).build()
        for (h in candidateHosts()) {
            val tcp = try { java.net.Socket().use { it.connect(java.net.InetSocketAddress(h, p.port), 3000) }; true } catch (_: Exception) { false }
            if (!tcp) { out += "$h:${p.port} — no answer (PC off, VIPER closed, phone link off, different network or firewall)" to false; continue }
            out += "$h:${p.port} — reachable" to true
            try {
                c.newCall(Request.Builder().url("https://$h:${p.port}/api/v1/hello").build()).execute().use { out += "$h — certificate matches the paired PC" to it.isSuccessful }
            } catch (e: javax.net.ssl.SSLException) { out += "$h — certificate does NOT match the paired PC (different machine)" to false; continue }
            catch (e: Exception) { out += "$h — secure connection failed: ${e.message}" to false; continue }
            try {
                c.newCall(Request.Builder().url("https://$h:${p.port}/api/v1/notifications/since/${System.currentTimeMillis()}").header("Authorization", p.authHeader).build()).execute().use {
                    out += when (it.code) { 200 -> "$h — this phone is still authorised" to true; 401 -> "$h — the PC no longer recognises this phone (revoked). Pair again." to false; else -> "$h — unexpected answer HTTP ${it.code}" to false }
                }
            } catch (e: Exception) { out += "$h — authorisation check failed: ${e.message}" to false }
        }
        val d = runCatching { Discovery.find(p.fingerprint, p.hosts) }.getOrNull()
        out += (if (d != null) "Found the PC on this network at ${d.host}" else "PC not found by LAN discovery (normal over VPN or mobile data)") to (d != null)
        out
    }

    fun forget() { disconnect(); store.pairing = null; client = null; host = null; state.value = Conn.UNPAIRED }

    companion object { val JSON = "application/json; charset=utf-8".toMediaType() }
}
