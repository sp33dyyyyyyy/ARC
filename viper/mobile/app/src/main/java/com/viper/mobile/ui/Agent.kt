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
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private val RUN_LABEL = mapOf("queued" to "Queued", "planning" to "Planning", "running" to "Running", "needs_input" to "Needs your input", "completed" to "Completed", "failed" to "Failed", "cancelled" to "Cancelled", "interrupted" to "Interrupted")
private val STEP_LABEL = mapOf("pending" to "Pending", "running" to "Running", "complete" to "Complete", "failed" to "Failed", "needs_input" to "Needs input", "skipped" to "Skipped")

/** Code Agent projects on the PC; start a task from the phone. */
@Composable
fun AgentProjectsScreen(app: ViperApp, back: () -> Unit, openRun: (String) -> Unit) {
    val scope = rememberCoroutineScope(); val conn by app.client.state.collectAsState()
    var projects by remember { mutableStateOf<List<JSONObject>>(emptyList()) }; var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<String?>(null) }; var request by remember { mutableStateOf("") }; var newName by remember { mutableStateOf("") }; var busy by remember { mutableStateOf(false) }
    suspend fun load() { try { val a = app.client.getArr("/api/v1/agent/projects"); projects = List(a.length()) { a.getJSONObject(it) }; error = null; if (selected == null) selected = projects.firstOrNull()?.optString("id") } catch (e: Exception) { error = e.message } }
    LaunchedEffect(conn) { if (conn == Conn.ONLINE) load() }
    LaunchedEffect(Unit) { app.client.events.filter { it.type == "agent.run" || it.type == "agent.done" }.collect { load() } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Code Agent", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (conn != Conn.ONLINE) { OfflinePanel(app); return@Column }
            error?.let { Text(if (it.contains("403") || it.contains("permission", true)) "This phone does not have the Code Agent permission. Enable it on the PC in Manage → Connected Devices." else it, color = Ink) }
            Panel(title = "New task") {
                if (projects.isEmpty()) Text("No projects yet — create one below.", color = Mist, fontSize = 13.sp)
                projects.forEach { p -> Row(Modifier.fillMaxWidth().clickable { selected = p.optString("id") }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected == p.optString("id"), { selected = p.optString("id") }, colors = RadioButtonDefaults.colors(selectedColor = Ink)); Text(p.optString("name"))
                } }
                OutlinedTextField(request, { request = it }, Modifier.fillMaxWidth().testTag("agent-request"), label = { Text("What should VIPER build or change?") }, minLines = 2)
                Spacer(Modifier.height(6.dp))
                VButton(if (busy) "Starting…" else "Start", {
                    val pid = selected ?: return@VButton; busy = true
                    scope.launch { try { val r = app.client.post("/api/v1/agent/projects/$pid/runs", JSONObject().put("request", request)); request = ""; openRun(r.getString("id")) } catch (e: Exception) { error = e.message }; busy = false }
                }, Modifier.fillMaxWidth(), primary = true, enabled = !busy && request.isNotBlank() && selected != null)
            }
            Panel(title = "New project") {
                OutlinedTextField(newName, { newName = it }, Modifier.fillMaxWidth(), label = { Text("Project name") }, singleLine = true)
                Spacer(Modifier.height(6.dp))
                VButton("Create", { scope.launch { try { val p = app.client.post("/api/v1/agent/projects", JSONObject().put("name", newName)); newName = ""; selected = p.optString("id"); load() } catch (e: Exception) { error = e.message } } }, enabled = newName.isNotBlank())
            }
            projects.forEach { p ->
                val lr = p.optJSONObject("lastRun")
                Panel(Modifier.clickable(enabled = lr != null) { lr?.let { openRun(it.optString("id")) } }) {
                    Text(p.optString("name"), style = MaterialTheme.typography.titleMedium)
                    Text(p.optString("path"), color = Mist, fontSize = 11.5.sp)
                    if (lr != null) Text("${RUN_LABEL[lr.optString("status")] ?: lr.optString("status")} · ${lr.optString("request").take(80)}", color = Ink2, fontSize = 13.sp)
                }
            }
        }
    }
}

/** One agent task: plan with real step statuses, decisions, controls and the verified result. */
@Composable
fun AgentRunScreen(app: ViperApp, runId: String, back: () -> Unit) {
    val scope = rememberCoroutineScope(); val conn by app.client.state.collectAsState()
    var run by remember { mutableStateOf<JSONObject?>(null) }; var error by remember { mutableStateOf<String?>(null) }; var busy by remember { mutableStateOf(false) }
    suspend fun load() { try { run = app.client.getObj("/api/v1/agent/runs/$runId"); error = null } catch (e: Exception) { error = e.message } }
    LaunchedEffect(conn, runId) { if (conn == Conn.ONLINE) load() }
    LaunchedEffect(runId) { app.client.events.filter { it.type.startsWith("agent.") && (it.data.optString("runId") == runId || it.data.optString("run_id") == runId) }.collect { delay(150); load() } }
    fun act(what: String) { busy = true; scope.launch { try { app.client.post("/api/v1/agent/runs/$runId/$what"); load() } catch (e: Exception) { error = e.message }; busy = false } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Task", back)
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (conn != Conn.ONLINE) { OfflinePanel(app); return@Column }
            error?.let { Text(it, color = Ink) }
            val r = run ?: run { LinearProgressIndicator(Modifier.fillMaxWidth(), color = Ink, trackColor = Line); return@Column }
            val plan = r.optJSONObject("plan"); val status = if (r.optBoolean("paused")) "paused" else r.optString("status")
            val live = r.optBoolean("live") && status !in setOf("completed", "failed", "cancelled")
            Text(plan?.optString("title")?.ifBlank { null } ?: "Planning…", style = MaterialTheme.typography.titleLarge)
            Text(r.optString("request"), color = Mist, fontSize = 12.5.sp)
            Row(verticalAlignment = Alignment.CenterVertically) { Tag(if (status == "paused") "Paused" else RUN_LABEL[status] ?: status, on = live); Spacer(Modifier.width(8.dp)); plan?.optString("stack")?.takeIf { it.isNotBlank() }?.let { Tag(it) } }
            r.optJSONObject("decision")?.takeIf { it.optString("status") == "open" }?.let { d ->
                Panel(Modifier.testTag("agent-decision"), title = "I need your input") {
                    Text(d.optString("question"))
                    Spacer(Modifier.height(6.dp))
                    val opts = runCatching { JSONArray(d.optString("options")) }.getOrNull() ?: JSONArray()
                    for (i in 0 until opts.length()) { val o = opts.getString(i)
                        VButton(o, { busy = true; scope.launch { try { app.client.post("/api/v1/agent/decisions/${d.optString("id")}", JSONObject().put("answer", o)); load() } catch (e: Exception) { error = e.message }; busy = false } }, Modifier.fillMaxWidth().padding(vertical = 2.dp), primary = i == 0, enabled = !busy) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (live && !r.optBoolean("paused")) VButton("Pause", { act("pause") }, enabled = !busy)
                if (r.optBoolean("paused") || status == "interrupted") VButton("Resume", { act("resume") }, primary = true, enabled = !busy)
                if (live || r.optBoolean("paused")) VButton("Cancel", { act("cancel") }, enabled = !busy)
            }
            val steps = plan?.optJSONArray("steps")
            if (steps != null) Panel(title = "Plan") {
                for (i in 0 until steps.length()) { val s = steps.getJSONObject(i); val st = s.optString("status")
                    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
                        Box(Modifier.padding(top = 5.dp).size(9.dp).clip(CircleShape).background(if (st == "complete") Ink else if (st == "running" || st == "needs_input") Ink2 else Line2))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) { Text(s.optString("title"), fontSize = 14.sp); s.optString("detail").takeIf { it.isNotBlank() }?.let { Text(it.take(240), color = Mist, fontSize = 12.sp) } }
                        Text(STEP_LABEL[st] ?: st, color = if (st == "failed") Ink else Mist, fontSize = 12.sp)
                    }
                }
            }
            r.optJSONObject("result")?.let { res ->
                Panel(Modifier.testTag("agent-result"), title = if (res.optString("status") == "completed") "Completion criteria passed" else "Not finished") {
                    fun outcome(o: JSONObject?, none: String) = when { o == null -> none; o.optBoolean("skipped") -> "skipped"; o.optBoolean("ok") -> "passed"; else -> "failed (exit ${o.optInt("code")})" }
                    KV("Build", outcome(res.optJSONObject("build"), "no build step")); KV("Tests", outcome(res.optJSONObject("test"), "no tests")); KV("Launch", outcome(res.optJSONObject("launch"), "not checked"))
                    KV("Files created", res.optJSONArray("created")?.length()?.toString() ?: "0"); KV("Files modified", res.optJSONArray("modified")?.length()?.toString() ?: "0")
                    res.optJSONArray("remaining")?.let { a -> for (i in 0 until a.length()) Text(a.getString(i), color = Ink2, fontSize = 13.sp) }
                    Text(res.optString("path"), color = Mist, fontSize = 11.5.sp)
                }
            }
        }
    }
}
