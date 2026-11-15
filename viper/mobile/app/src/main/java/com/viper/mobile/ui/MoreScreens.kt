package com.viper.mobile.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.viper.mobile.ConnectionService
import com.viper.mobile.ViperApp
import com.viper.mobile.net.Conn
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.DateFormat
import java.util.Date

@Composable
fun MoreMenu(open: (String) -> Unit) {
    val items = listOf("vision" to "Vision — camera & image analysis", "files" to "File transfer", "reminders" to "Reminders", "automations" to "Automations", "notifications" to "Notifications", "code" to "Code assistant", "settings" to "Settings & connection")
    Column(Modifier.fillMaxSize().padding(14.dp)) {
        Text("More", style = MaterialTheme.typography.headlineMedium); Spacer(Modifier.height(12.dp))
        items.forEach { (id, label) -> Text(label, Modifier.fillMaxWidth().clickable { open(id) }.padding(vertical = 14.dp), style = MaterialTheme.typography.titleMedium); HorizontalDivider(color = Line) }
    }
}

@Composable
fun Header(title: String, back: () -> Unit) = Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
    TextButton(back) { Text("‹ Back", color = Ink2) }; Text(title, style = MaterialTheme.typography.titleLarge)
}

fun fmtTime(ts: Long): String = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(ts))

@Composable
fun VisionScreen(app: ViperApp, back: () -> Unit, image: String?, pickImage: () -> Unit, takePhoto: () -> Unit) {
    val scope = rememberCoroutineScope()
    var q by remember { mutableStateOf("Describe what you see and anything noteworthy.") }
    var answer by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Vision", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Photos are analysed by the vision model on your PC.", color = Mist)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VButton("Take photo", takePhoto, primary = true); VButton("Choose image", pickImage) }
            if (image != null) Text("Image ready (${image.length / 1365} KB)", color = Ink2)
            OutlinedTextField(q, { q = it }, Modifier.fillMaxWidth(), label = { Text("Question") })
            VButton(if (busy) "Analysing…" else "Analyse", {
                if (image == null) { answer = "Take or choose a photo first."; return@VButton }
                busy = true
                scope.launch { answer = try { app.client.post("/api/v1/vision/analyze", JSONObject().put("prompt", q).put("image", image)).optString("text") } catch (e: Exception) { "Analysis failed: ${e.message}" }; busy = false }
            }, enabled = !busy && app.client.state.value == Conn.ONLINE)
            if (answer.isNotBlank()) Panel { MarkdownText(answer) }
        }
    }
}

@Composable
fun FilesScreen(app: ViperApp, back: () -> Unit, pickUpload: () -> Unit) {
    val ctx = LocalContext.current; val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf(JSONArray()) }; var msg by remember { mutableStateOf("") }
    suspend fun load() { runCatching { list = app.client.getArr("/api/v1/transfer/list") }.onFailure { msg = it.message ?: "" } }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("File transfer", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            VButton("Send a file to the PC", pickUpload, primary = true)
            Text("Files from your PC (Communications → Phone link → Send a file):", color = Mist)
            for (i in 0 until list.length()) {
                val f = list.getJSONObject(i)
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(f.optString("name")); Text("${fmtBytes(f.optDouble("size"))} · ${fmtTime(f.optLong("modified"))}", color = Mist, fontSize = 12.sp) }
                    VButton("Open", { scope.launch {
                        try {
                            val bytes = app.client.getBytes("/api/v1/transfer/file/${Uri.encode(f.optString("name"))}")
                            val dir = File(ctx.getExternalFilesDir(null), "transfers").apply { mkdirs() }
                            val out = File(dir, f.optString("name")); out.writeBytes(bytes)
                            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", out)
                            ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_VIEW).setDataAndType(uri, ctx.contentResolver.getType(uri) ?: "*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Open with"))
                        } catch (e: Exception) { msg = "Download failed: ${e.message}" }
                    } })
                }
            }
            if (list.length() == 0) Text("No files yet.", color = Mist)
            if (msg.isNotBlank()) Text(msg, color = Ink2)
        }
    }
}

@Composable
fun RemindersScreen(app: ViperApp, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf(JSONArray()) }; var text by remember { mutableStateOf("") }; var whenStr by remember { mutableStateOf("in 30 minutes") }; var msg by remember { mutableStateOf("") }
    suspend fun load() { runCatching { list = app.client.getArr("/api/v1/reminders") } }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Reminders", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), label = { Text("Remind me to…") })
            OutlinedTextField(whenStr, { whenStr = it }, Modifier.fillMaxWidth(), label = { Text("When (e.g. at 8pm, tomorrow at 9)") })
            VButton("Add reminder", { scope.launch { msg = try { app.client.post("/api/v1/reminders", JSONObject().put("text", text).put("when", whenStr)); text = ""; load(); "Reminder set." } catch (e: Exception) { e.message ?: "" } } }, primary = true)
            if (msg.isNotBlank()) Text(msg, color = Ink2)
            for (i in 0 until list.length()) { val r = list.getJSONObject(i)
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(r.optString("text")); Text("${fmtTime(r.optLong("due_at"))} · ${r.optString("status")}", color = Mist, fontSize = 12.sp) }
                    TextButton({ scope.launch { runCatching { app.client.delete("/api/v1/reminders/${r.optString("id")}") }; load() } }) { Text("Delete", color = Ink2) }
                } }
        }
    }
}

@Composable
fun AutomationsScreen(app: ViperApp, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf(JSONArray()) }; var msg by remember { mutableStateOf("") }; var nl by remember { mutableStateOf("") }
    suspend fun load() { runCatching { list = app.client.getArr("/api/v1/automations") } }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Automations", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(nl, { nl = it }, Modifier.fillMaxWidth(), label = { Text("Describe a new automation") })
            VButton("Create", { scope.launch { msg = try { app.client.post("/api/v1/automations/from-text", JSONObject().put("text", nl)).optString("reply") } catch (e: Exception) { e.message ?: "" }; nl = ""; load() } })
            if (msg.isNotBlank()) Text(msg, color = Ink2)
            for (i in 0 until list.length()) { val a = list.getJSONObject(i)
                Panel {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(a.optString("name"), Modifier.weight(1f))
                        Switch(a.optBoolean("enabled"), { v -> scope.launch { runCatching { app.client.patch("/api/v1/automations/${a.optString("id")}", JSONObject().put("enabled", v)) }; load() } }, colors = SwitchDefaults.colors(checkedTrackColor = Ink, checkedThumbColor = Void))
                    }
                    Text("Last run: ${if (a.has("last_run") && !a.isNull("last_run")) fmtTime(a.optLong("last_run")) + " · " + a.optString("last_status") else "never"}", color = Mist, fontSize = 12.sp)
                    VButton("Run now", { scope.launch { msg = try { "${a.optString("name")}: " + app.client.post("/api/v1/automations/${a.optString("id")}/run").optString("status") } catch (e: Exception) { e.message ?: "" }; load() } })
                } }
        }
    }
}

@Composable
fun NotificationsScreen(app: ViperApp, back: () -> Unit) {
    val live by app.notifications.collectAsState(); val scope = rememberCoroutineScope()
    var history by remember { mutableStateOf(JSONArray()) }
    LaunchedEffect(Unit) { runCatching { history = app.client.getArr("/api/v1/notifications") } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Notifications", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val all = (live + List(history.length()) { history.getJSONObject(it) }).distinctBy { it.optString("id") }
            if (all.isEmpty()) Text("No notifications.", color = Mist)
            all.forEach { n -> Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) { Text(n.optString("title")); if (n.optString("body").isNotBlank()) Text(n.optString("body"), color = Ink2, fontSize = 13.sp); Text("${fmtTime(n.optLong("created_at"))} · ${n.optString("priority")}", color = Mist, fontSize = 11.sp) }; HorizontalDivider(color = Line) }
            VButton("Mark all read", { scope.launch { runCatching { app.client.post("/api/v1/notifications/all/read") } } })
        }
    }
}

@Composable
fun CodeScreen(app: ViperApp, back: () -> Unit) {
    val scope = rememberCoroutineScope()
    var prompt by remember { mutableStateOf("") }; var code by remember { mutableStateOf("") }; var lang by remember { mutableStateOf("python") }
    var out by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    fun run(action: String) { busy = true; scope.launch { out = try { app.client.post("/api/v1/code/assist", JSONObject().put("action", action).put("prompt", prompt).put("selection", code.ifBlank { JSONObject.NULL }).put("language", lang)).optString("text") } catch (e: Exception) { "Failed: ${e.message}" }; busy = false } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Code assistant", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(lang, { lang = it }, Modifier.fillMaxWidth(), label = { Text("Language") }, singleLine = true)
            OutlinedTextField(prompt, { prompt = it }, Modifier.fillMaxWidth(), label = { Text("What do you need?") })
            OutlinedTextField(code, { code = it }, Modifier.fillMaxWidth().heightIn(min = 120.dp), label = { Text("Code or error (optional)") }, textStyle = LocalTextStyle.current.copy(fontFamily = Mono, fontSize = 12.sp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { VButton("Write", { run("generate") }, primary = true, enabled = !busy); VButton("Explain", { run("explain") }, enabled = !busy); VButton("Debug", { run("debug") }, enabled = !busy) }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Ink, trackColor = Line)
            if (out.isNotBlank()) Panel { MarkdownText(out) }
        }
    }
}

@Composable
fun SettingsScreen(app: ViperApp, back: () -> Unit) {
    val ctx = LocalContext.current
    val conn by app.client.state.collectAsState(); val err by app.client.lastError.collectAsState()
    var host by remember { mutableStateOf(app.store.hostOverride) }
    var stay by remember { mutableStateOf(app.store.stayConnected) }; var hands by remember { mutableStateOf(app.store.handsFree) }
    var pcVoice by remember { mutableStateOf(app.store.usePcVoice) }; var speak by remember { mutableStateOf(app.store.speakReplies) }; var sms by remember { mutableStateOf(app.store.smsBridge) }
    var confirmForget by remember { mutableStateOf(false) }
    var sounds by remember { mutableStateOf(app.store.notificationSounds) }
    val pushStatus by app.pushStatus.collectAsState()
    val p = app.store.pairing
    @Composable fun Toggle(label: String, sub: String, v: Boolean, set: (Boolean) -> Unit) = Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(label); Text(sub, color = Mist, fontSize = 12.sp) }
        Switch(v, set, colors = SwitchDefaults.colors(checkedTrackColor = Ink, checkedThumbColor = Void))
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Settings", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Panel(title = "Connection") {
                ConnBadge(conn, p?.serverName ?: "PC"); err?.let { if (conn != Conn.ONLINE) Text(it, color = Mist, fontSize = 12.sp) }
                KV("Addresses", p?.hosts?.joinToString() ?: "—"); KV("Port", p?.port?.toString() ?: "—")
                Text("Certificate pinned: ${p?.fingerprint?.take(23) ?: "—"}…", color = Mist, fontSize = 12.sp)
                OutlinedTextField(host, { host = it }, Modifier.fillMaxWidth(), label = { Text("Preferred address (e.g. VPN IP)") }, singleLine = true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { VButton("Save & reconnect", { app.store.hostOverride = host; app.client.disconnect(); app.client.connect() }); VButton("Unpair", { confirmForget = true }) }
            }
            Panel(title = "Notifications") {
                Toggle("Notification sounds", "Play the channel's sound for VIPER notifications. Turn off for silent notifications.", sounds) { sounds = it; app.store.notificationSounds = it }
                Text(pushStatus.ifBlank { "Push status is checked when the phone connects to the PC." }, color = Ink2, fontSize = 13.sp)
                Text("Without push (set up on the PC in Settings → Notifications), notifications arrive while VIPER Mobile is connected — app open, or “Stay connected” on. If the app is fully closed or the phone has no connection to the PC, they are delivered the next time it connects.", color = Mist, fontSize = 12.sp)
                Spacer(Modifier.height(6.dp))
                VButton("Notification categories", { ctx.startActivity(Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, ctx.packageName)) })
            }
            Panel(title = "Background") {
                Toggle("Stay connected", "Receive alerts while the app is closed (shows a persistent notification).", stay) { stay = it; app.store.stayConnected = it; ConnectionService.update(ctx) }
                Toggle("Hands-free wake word", "Listen for \"VIPER\" using the PC's speech engine. Uses the microphone in the background.", hands) { hands = it; app.store.handsFree = it; ConnectionService.update(ctx) }
            }
            Panel(title = "Voice") {
                Toggle("Speak replies", "Read answers aloud after voice requests.", speak) { speak = it; app.store.speakReplies = it }
                Toggle("Use the PC's voice", "Piper voice from the PC; otherwise this phone's text-to-speech.", pcVoice) { pcVoice = it; app.store.usePcVoice = it }
            }
            Panel(title = "SMS bridge") {
                Toggle("Allow the PC to send SMS through this phone", "Every message needs your approval on this phone. Carrier charges may apply.", sms) { sms = it; app.store.smsBridge = it; if (it) (ctx as? com.viper.mobile.MainActivity)?.requestSmsPermission() }
            }
        }
    }
    if (confirmForget) AlertDialog(onDismissRequest = { confirmForget = false }, confirmButton = { TextButton({ confirmForget = false; app.client.forget(); app.store.stayConnected = false; app.store.handsFree = false; ConnectionService.update(ctx); back() }) { Text("Unpair", color = Ink) } },
        dismissButton = { TextButton({ confirmForget = false }) { Text("Cancel", color = Ink2) } }, title = { Text("Unpair this phone?") }, text = { Text("The stored credentials are deleted from this phone. Revoke it on the PC too (Manage → Connected Devices).") })
}
