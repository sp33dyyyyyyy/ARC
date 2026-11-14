package com.viper.mobile.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viper.mobile.Msg
import com.viper.mobile.ViperApp
import com.viper.mobile.net.Conn
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

fun fmtBytes(n: Double): String { var v = n; val u = listOf("B", "KB", "MB", "GB", "TB"); var i = 0; while (v >= 1024 && i < 4) { v /= 1024; i++ }; return "%.${if (v >= 10 || i == 0) 0 else 1}f %s".format(v, u[i]) }
fun bitmapToDataUrl(b: Bitmap, max: Int = 1280): String {
    val s = minOf(1f, max.toFloat() / maxOf(b.width, b.height))
    val scaled = if (s < 1f) Bitmap.createScaledBitmap(b, (b.width * s).toInt(), (b.height * s).toInt(), true) else b
    val out = ByteArrayOutputStream(); scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
    return "data:image/jpeg;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
}

@Composable
fun ConnBadge(state: Conn, server: String) {
    val (label, on) = when (state) { Conn.ONLINE -> "Connected to $server" to true; Conn.CONNECTING -> "Connecting…" to false; Conn.OFFLINE -> "PC unreachable" to false; Conn.UNPAIRED -> "Not paired" to false }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(if (on) Ink else Line2)); Spacer(Modifier.width(8.dp)); Text(label, fontSize = 12.5.sp, color = if (on) Ink2 else Mist)
    }
}

// ---------------- Home: core + quick conversation ----------------
@Composable
fun HomeScreen(app: ViperApp, openChat: () -> Unit) {
    val core by app.coreState.collectAsState(); val level by app.micLevel.collectAsState(); val transcript by app.transcript.collectAsState()
    val msgs by app.messages.collectAsState(); val listening by app.listening.collectAsState()
    var input by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) { VCore(core, level, Modifier.fillMaxWidth(0.86f).aspectRatio(1f)) }
        Text(mapOf("idle" to "Standing by", "listening" to "Listening", "thinking" to "Thinking", "speaking" to "Speaking", "warning" to "Approval needed", "offline" to "PC offline")[core] ?: core, color = Mist, fontSize = 12.5.sp)
        if (transcript.isNotBlank()) Text(transcript, color = Ink2, modifier = Modifier.padding(top = 6.dp))
        msgs.lastOrNull { it.role == "viper" }?.let { last ->
            Panel(Modifier.padding(top = 10.dp).heightIn(max = 220.dp).verticalScroll(rememberScrollState()).clickable { openChat() }) { MarkdownText(last.text.ifBlank { "…" }) }
        }
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(input, { input = it }, Modifier.weight(1f), placeholder = { Text("Ask VIPER…") }, singleLine = true)
            Spacer(Modifier.width(8.dp))
            VButton("Send", { app.send(input); input = "" }, primary = true)
        }
        Spacer(Modifier.height(10.dp))
        PttButton(app, listening)
    }
}

@Composable
fun PttButton(app: ViperApp, listening: Boolean) {
    Box(Modifier.fillMaxWidth().height(56.dp).clip(CircleShape).background(if (listening) Ink else Glass).pointerInput(Unit) {
        detectTapGestures(onPress = { if (app.pttStart()) { tryAwaitRelease(); app.pttStop() } })
    }, contentAlignment = Alignment.Center) { Text(if (listening) "Listening — release to send" else "Hold to talk", color = if (listening) Void else Ink) }
}

// ---------------- Chat ----------------
@Composable
fun ChatScreen(app: ViperApp, pickImage: () -> Unit, takePhoto: () -> Unit) {
    val msgs by app.messages.collectAsState(); val listening by app.listening.collectAsState()
    var input by remember { mutableStateOf("") }
    val list = rememberLazyListState()
    LaunchedEffect(msgs.size, msgs.lastOrNull()?.text?.length) { if (msgs.isNotEmpty()) list.animateScrollToItem(msgs.size - 1) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Chat", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            TextButton({ app.newConversation() }) { Text("New", color = Ink) }
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = 12.dp), state = list, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (msgs.isEmpty()) item { Text("Messages sync with VIPER on your PC. Replies stream live while connected; if the PC is unreachable, requests are queued and sent later.", color = Mist) }
            items(msgs, key = { it.localId }) { MessageRow(it) }
        }
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(pickImage) { Text("Image", color = Ink2) }; TextButton(takePhoto) { Text("Camera", color = Ink2) }
            OutlinedTextField(input, { input = it }, Modifier.weight(1f), placeholder = { Text("Message") }, maxLines = 4)
            Spacer(Modifier.width(6.dp))
            if (msgs.lastOrNull()?.status == "streaming") VButton("Stop", { app.cancel() }) else VButton("Send", { app.send(input); input = "" }, primary = true)
        }
        Box(Modifier.padding(horizontal = 12.dp, vertical = 6.dp)) { PttButton(app, listening) }
    }
}

@Composable
fun MessageRow(m: Msg) {
    val mine = m.role == "user"
    Column(Modifier.fillMaxWidth()) {
        Text(if (mine) "You" else "VIPER", fontSize = 11.sp, color = Mist)
        m.tools.forEach { Text("› $it", fontSize = 12.sp, color = Ink2) }
        when {
            mine -> Text(m.text, color = Ink2)
            m.status == "streaming" && m.text.isBlank() -> LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 6.dp), color = Ink, trackColor = Line)
            else -> MarkdownText(m.text)
        }
        if (m.status == "queued") Tag("Queued — waiting for PC")
        if (m.status == "error") Tag("Not completed", on = true)
    }
}

// ---------------- PC dashboard & remote control ----------------
@Composable
fun PcScreen(app: ViperApp) {
    val snap by app.snapshot.collectAsState(); val conn by app.client.state.collectAsState()
    val scope = rememberCoroutineScope()
    var status by remember { mutableStateOf<JSONObject?>(null) }
    var models by remember { mutableStateOf<JSONArray?>(null) }
    var tasks by remember { mutableStateOf<JSONObject?>(null) }
    var msg by remember { mutableStateOf("") }
    var appName by remember { mutableStateOf("") }
    var shot by remember { mutableStateOf<Bitmap?>(null) }
    var scripts by remember { mutableStateOf<JSONArray?>(null) }
    LaunchedEffect(conn) {
        if (conn == Conn.ONLINE) runCatching {
            app.refreshSnapshot(); status = app.client.getObj("/api/v1/models/status"); models = app.client.getArr("/api/v1/models"); tasks = app.client.getObj("/api/v1/tasks"); scripts = app.client.getArr("/api/v1/approved-scripts")
        }
    }
    fun tool(name: String, args: JSONObject = JSONObject()) = scope.launch {
        msg = "Working…"
        msg = try { val r = app.client.post("/api/v1/tools/$name", JSONObject().put("args", args)); if (r.optBoolean("ok")) "Done: ${r.opt("result")?.toString()?.take(300)}" else "Not done: ${r.optString("error")}" } catch (e: Exception) { "Failed: ${e.message}" }
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Your PC", style = MaterialTheme.typography.headlineMedium)
        if (conn != Conn.ONLINE) { Text("Not connected. Readings and controls appear when the PC is reachable.", color = Mist); return@Column }
        snap?.let { s ->
            Panel(title = "Status") {
                val cpu = s.optJSONObject("cpu")?.optDouble("pct") ?: 0.0; val mem = s.optJSONObject("mem")
                KV("CPU", "${cpu.toInt()}%"); Meter((cpu / 100).toFloat())
                Spacer(Modifier.height(6.dp)); KV("Memory", "${mem?.optDouble("pct")?.toInt() ?: 0}% · ${fmtBytes(mem?.optDouble("used") ?: 0.0)}"); Meter(((mem?.optDouble("pct") ?: 0.0) / 100).toFloat())
                val disks = s.optJSONArray("disks") ?: JSONArray()
                for (i in 0 until disks.length()) { val d = disks.getJSONObject(i); Spacer(Modifier.height(6.dp)); KV("Drive ${d.optString("mount")}", "${d.optDouble("pct").toInt()}% used"); Meter((d.optDouble("pct") / 100).toFloat()) }
                val temp = s.optJSONObject("temp")
                KV("CPU temperature", temp?.optDouble("cpu")?.let { "${it.toInt()}°C" } ?: "not exposed")
                KV("Internet", if (s.optBoolean("online")) "connected" else "offline")
            }
        }
        tasks?.let { t -> val arr = t.optJSONArray("tasks") ?: JSONArray(); Panel(title = "Active tasks") { if (arr.length() == 0) Text("Nothing running.", color = Mist); for (i in 0 until arr.length()) { val x = arr.getJSONObject(i); KV(x.optString("label"), x.optString("state")) } } }
        Panel(title = "Remote commands") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VButton("Diagnostic", { app.send("Run a system diagnostic") }); VButton("Briefing", { app.send("Give me my morning briefing") }) }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VButton("Vol −", { tool("set_volume", JSONObject().put("action", "down")) }); VButton("Vol +", { tool("set_volume", JSONObject().put("action", "up")) }); VButton("Mute", { tool("set_volume", JSONObject().put("action", "mute")) }) }
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) { OutlinedTextField(appName, { appName = it }, Modifier.weight(1f), placeholder = { Text("App name") }, singleLine = true); Spacer(Modifier.width(6.dp)); VButton("Open", { tool("open_app", JSONObject().put("name", appName)) }) }
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                VButton("Screenshot", { scope.launch { msg = "Capturing…"; try { val r = app.client.post("/api/v1/vision/capture"); val b = Base64.decode(r.getString("dataUrl").substringAfter(","), Base64.DEFAULT); shot = BitmapFactory.decodeByteArray(b, 0, b.size); msg = "Screenshot captured" } catch (e: Exception) { msg = "Screenshot not taken: ${e.message}" } } })
                VButton("Explain screen", { app.send("Explain what is on my screen") })
            }
            scripts?.let { sc -> for (i in 0 until sc.length()) { val n = sc.getJSONObject(i).optString("name"); Spacer(Modifier.height(6.dp)); VButton("Run: $n", { tool("run_approved_script", JSONObject().put("name", n)) }) } }
            if (msg.isNotBlank()) Text(msg, color = Ink2, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
            shot?.let { Image(it.asImageBitmap(), "PC screenshot", Modifier.fillMaxWidth().padding(top = 8.dp)) }
        }
        Panel(title = "AI model") {
            val st = status; val roles = st?.optJSONObject("roles"); val active = st?.optString("active") ?: ""
            KV("Engine", active); KV("Chat model", roles?.optJSONObject("chat")?.optString("model")?.ifBlank { "automatic" } ?: "—")
            val arr = models ?: JSONArray()
            for (i in 0 until arr.length()) { val m = arr.getJSONObject(i); if (m.optJSONArray("capabilities")?.toString()?.contains("chat") != true) continue
                Row(Modifier.fillMaxWidth().clickable { scope.launch { runCatching { app.client.post("/api/v1/models/role", JSONObject().put("role", "chat").put("backend", m.optString("backend")).put("model", m.optString("id"))); status = app.client.getObj("/api/v1/models/status"); msg = "Chat model set to ${m.optString("id")}" } } }.padding(vertical = 6.dp)) {
                    Text(m.optString("id"), Modifier.weight(1f)); Text(m.optString("backend"), color = Mist, fontSize = 12.sp) } }
        }
    }
}
