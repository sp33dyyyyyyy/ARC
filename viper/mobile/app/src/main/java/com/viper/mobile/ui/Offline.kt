package com.viper.mobile.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viper.mobile.ViperApp
import com.viper.mobile.net.Conn
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Disconnected mode: honest state, last connection, reconnect and a real step-by-step diagnosis. */
@Composable
fun OfflinePanel(app: ViperApp, modifier: Modifier = Modifier) {
    val conn by app.client.state.collectAsState(); val err by app.client.lastError.collectAsState()
    val retryAt by app.client.nextRetryAt.collectAsState(); val net by app.networkUp.collectAsState()
    val scope = rememberCoroutineScope()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); delay(1000) } }
    var diag by remember { mutableStateOf<List<Pair<String, Boolean>>?>(null) }; var running by remember { mutableStateOf(false) }
    val last = app.store.lastConnected
    Column(modifier.fillMaxWidth().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("VIPER is currently offline.", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center, modifier = Modifier.testTag("offline-title"))
        Text(if (last > 0) "Last connected ${fmtTime(last)}" else "Not connected since pairing", color = Ink2, fontSize = 13.sp)
        Text(when {
            !net -> "This phone has no network connection."
            conn == Conn.CONNECTING -> "Trying to reach ${app.store.pairing?.serverName ?: "your PC"}…"
            retryAt > now -> "Retrying automatically in ${(retryAt - now + 999) / 1000} s."
            else -> "Waiting to retry."
        }, color = Mist, fontSize = 12.5.sp, textAlign = TextAlign.Center)
        err?.let { Text(it, color = Mist, fontSize = 11.5.sp, textAlign = TextAlign.Center) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VButton("Reconnect", { app.client.reconnectNow() }, primary = true, enabled = conn != Conn.CONNECTING)
            VButton(if (running) "Checking…" else "Connection diagnostics", { running = true; scope.launch { diag = app.client.diagnose(net); running = false } }, enabled = !running)
        }
        diag?.let { lines -> Panel(title = "Diagnostics") { lines.forEach { (t, ok) -> Row(Modifier.padding(vertical = 3.dp)) { Text(if (ok) "✓ " else "✕ ", color = if (ok) Ink else Mist); Text(t, fontSize = 13.sp, color = if (ok) Ink2 else Ink) } } } }
        Text("While offline, messages you send are queued and delivered when the connection returns.", color = Mist, fontSize = 11.5.sp, textAlign = TextAlign.Center)
    }
}
