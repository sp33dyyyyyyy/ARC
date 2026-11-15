package com.viper.mobile.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viper.mobile.ViperApp
import com.viper.mobile.net.Conn
import com.viper.mobile.notify.NotifyLogic
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** The same five categories as VIPER on the PC. Items are the screens available on the phone. */
val MOBILE_CATEGORIES = listOf(
    "prompt" to "Prompt", "make" to "Make", "manage" to "Manage", "intel" to "Intelligence", "settings" to "Settings",
)
val CATEGORY_ITEMS = mapOf(
    "prompt" to listOf("chat" to "Chat", "vision" to "Live Vision — camera & image analysis"),
    "make" to listOf("agent" to "AI Coding Agent", "code" to "Code assistant"),
    "manage" to listOf("pc" to "PC Control", "tasks" to "Background Tasks", "notifications" to "Notifications", "reminders" to "Reminders & scheduled tasks", "automations" to "Automations", "files" to "File transfer"),
    "intel" to listOf("models" to "AI status & models"),
)

@Composable
fun CategoryMenu(category: String, title: String, open: (String) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(14.dp)) {
        Text(title.uppercase(), fontSize = 13.sp, letterSpacing = 3.sp, color = Ink2); Spacer(Modifier.height(10.dp))
        CATEGORY_ITEMS[category].orEmpty().forEach { (id, label) ->
            Text(label, Modifier.fillMaxWidth().clickable { open(id) }.padding(vertical = 15.dp).testTag("item-$id"), style = MaterialTheme.typography.titleMedium); HorizontalDivider(color = Line)
        }
    }
}

/** MANAGE → Background Tasks: what VIPER is doing right now on the PC. */
@Composable
fun TasksScreen(app: ViperApp, back: () -> Unit, openRun: (String) -> Unit) {
    val conn by app.client.state.collectAsState()
    var tasks by remember { mutableStateOf<List<JSONObject>>(emptyList()) }; var error by remember { mutableStateOf<String?>(null) }
    suspend fun load() { try { val o = app.client.getObj("/api/v1/tasks"); val a = o.optJSONArray("tasks") ?: JSONArray(); val ai = o.optJSONArray("ai") ?: JSONArray()
        tasks = List(a.length()) { a.getJSONObject(it) } + List(ai.length()) { ai.getJSONObject(it).put("state", "running").put("kind", "ai") }; error = null } catch (e: Exception) { error = e.message } }
    LaunchedEffect(conn) { if (conn == Conn.ONLINE) while (true) { load(); delay(4000) } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Background Tasks", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (conn != Conn.ONLINE) { OfflinePanel(app); return@Column }
            error?.let { Text(it, color = Ink) }
            if (tasks.isEmpty()) Text("Nothing running on your PC.", color = Mist)
            tasks.forEach { t ->
                val link = t.optJSONObject("link")
                Panel(Modifier.clickable(enabled = link?.optString("type") == "agent_run") { openRun(link!!.optString("id")) }) {
                    Text(t.optString("label").ifBlank { t.optString("task", "AI request") })
                    Text("${t.optString("state")}${t.optString("detail").takeIf { it.isNotBlank() }?.let { " · $it" } ?: ""}", color = Mist, fontSize = 12.sp)
                    if (t.optString("state") == "running") { Spacer(Modifier.height(6.dp)); if (t.has("progress")) Meter(t.optDouble("progress").toFloat()) else LinearProgressIndicator(Modifier.fillMaxWidth(), color = Ink, trackColor = Line) }
                }
            }
        }
    }
}

/** INTELLIGENCE → AI status: which engine and models the PC is using. */
@Composable
fun ModelsScreen(app: ViperApp, back: () -> Unit) {
    val conn by app.client.state.collectAsState()
    var status by remember { mutableStateOf<JSONObject?>(null) }; var models by remember { mutableStateOf(JSONArray()) }; var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(conn) { if (conn == Conn.ONLINE) try { status = app.client.getObj("/api/v1/models/status"); models = app.client.getArr("/api/v1/models") } catch (e: Exception) { error = e.message } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("AI status", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (conn != Conn.ONLINE) { OfflinePanel(app); return@Column }
            error?.let { Text(it, color = Ink) }
            status?.let { s -> Panel(title = "Engine") {
                KV("Active engine", s.optString("active"))
                val roles = s.optJSONObject("roles")
                listOf("chat" to "Chat", "code" to "Coding", "vision" to "Vision").forEach { (k, l) -> KV(l, roles?.optJSONObject(k)?.optString("model")?.ifBlank { null } ?: "automatic") }
            } }
            Panel(title = "Installed models") {
                if (models.length() == 0) Text("None reported.", color = Mist)
                for (i in 0 until models.length()) { val m = models.getJSONObject(i)
                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(7.dp).clip(CircleShape).background(if (m.optBoolean("loaded")) Ink else Line2)); Spacer(Modifier.width(8.dp))
                        Column(Modifier.weight(1f)) { Text(m.optString("name"), fontSize = 14.sp); Text(listOf(m.optString("backend"), m.optString("parameterSize")).filter { it.isNotBlank() }.joinToString(" · "), color = Mist, fontSize = 11.5.sp) }
                    }
                }
            }
        }
    }
}

/** MANAGE → Notifications: history with read/unread; tapping opens what it refers to. */
@Composable
fun NotificationHistoryScreen(app: ViperApp, back: () -> Unit, openLink: (String, JSONObject?) -> Unit) {
    val live by app.notifications.collectAsState(); val scope = rememberCoroutineScope(); val conn by app.client.state.collectAsState()
    var history by remember { mutableStateOf<List<JSONObject>>(emptyList()) }; var unreadOnly by remember { mutableStateOf(false) }
    suspend fun load() { runCatching { val a = app.client.getArr("/api/v1/notifications"); history = List(a.length()) { a.getJSONObject(it) } } }
    LaunchedEffect(conn) { if (conn == Conn.ONLINE) load() }
    LaunchedEffect(Unit) { app.client.events.filter { it.type == "notification" || it.type == "notifications.read" }.collect { load() } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Notifications", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                FilterChip(!unreadOnly, { unreadOnly = false }, { Text("All") }); FilterChip(unreadOnly, { unreadOnly = true }, { Text("Unread") })
                Spacer(Modifier.weight(1f))
                TextButton({ scope.launch { runCatching { app.client.post("/api/v1/notifications/all/read") }; load() } }, enabled = conn == Conn.ONLINE) { Text("Mark all read", color = Ink2) }
            }
            val all = (history + live).distinctBy { it.optString("id") }.sortedByDescending { it.optLong("created_at") }.filter { !unreadOnly || !it.optBoolean("read") }
            if (all.isEmpty()) Text(if (unreadOnly) "No unread notifications." else "No notifications.", color = Mist)
            all.forEach { n ->
                val read = n.optBoolean("read")
                Row(Modifier.fillMaxWidth().clickable {
                    scope.launch { if (!read) runCatching { app.client.post("/api/v1/notifications/${n.optString("id")}/read") }; load() }
                    openLink("open", NotifyLogic.link(n))
                }.padding(vertical = 8.dp).testTag("notif-${n.optString("kind")}"), verticalAlignment = Alignment.Top) {
                    Box(Modifier.padding(top = 6.dp).size(7.dp).clip(CircleShape).background(if (read) Line2 else Ink)); Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(n.optString("title"), color = if (read) Ink2 else Ink)
                        if (n.optString("body").isNotBlank()) Text(n.optString("body"), color = Ink2, fontSize = 13.sp)
                        Text(fmtTime(n.optLong("created_at")), color = Mist, fontSize = 11.sp)
                    }
                }
                HorizontalDivider(color = Line)
            }
        }
    }
}
