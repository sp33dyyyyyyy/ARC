package com.viper.mobile.ui

import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viper.mobile.ViperApp
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Full review of an approval request: exactly what VIPER intends to do, who asked and the risk.
 * Approving requires the phone's screen lock / biometrics when the phone has one ([authenticate]).
 * Leaving this screen, or dismissing the notification, never approves anything.
 */
@Composable
fun ApprovalReviewScreen(app: ViperApp, req: JSONObject, authenticate: (String, (Boolean) -> Unit) -> Unit, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }; var error by remember { mutableStateOf<String?>(null) }
    fun send(approved: Boolean) { busy = true; scope.launch { error = app.answerConfirm(req, approved); busy = false; if (error == null) close() } }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Review request", close)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("I require your authorisation to proceed.", color = Ink2)
            Panel {
                Text(req.optString("title"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.testTag("review-title"))
                if (req.optString("reason").isNotBlank()) { Spacer(Modifier.height(6.dp)); Text(req.optString("reason"), color = Ink2) }
                Spacer(Modifier.height(8.dp))
                KV("Requested by", req.optString("origin").ifBlank { "VIPER" })
                KV("Risk", when (req.optString("risk")) { "destructive" -> "Destructive — cannot be undone"; "write" -> "Changes files or settings"; "network" -> "Uses the network"; "" -> "—"; else -> req.optString("risk") })
                KV("Action", req.optString("tool").replace('_', ' ').ifBlank { "—" })
            }
            if (req.optString("preview").isNotBlank()) Panel(title = "What will happen") {
                Box(Modifier.fillMaxWidth().border(1.dp, Line).horizontalScroll(rememberScrollState()).padding(10.dp)) { Text(req.optString("preview"), fontFamily = Mono, fontSize = 12.sp, color = Ink2) }
            }
            error?.let { Text("Not sent: $it", color = Ink) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                VButton(if (busy) "Sending…" else "Approve", { authenticate("Approve: ${req.optString("title").take(60)}") { ok -> if (ok) send(true) else error = "Approval cancelled — nothing was sent." } }, Modifier.weight(1f).testTag("review-approve"), primary = true, enabled = !busy)
                VButton("Deny", { send(false) }, Modifier.weight(1f).testTag("review-deny"), enabled = !busy)
            }
            Text("Closing this screen leaves the request waiting on your PC. If nobody answers, it is not carried out.", color = Mist, fontSize = 12.sp)
        }
    }
}
