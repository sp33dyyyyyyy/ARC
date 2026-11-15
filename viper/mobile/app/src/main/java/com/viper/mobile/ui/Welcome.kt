package com.viper.mobile.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.viper.mobile.ViperApp
import com.viper.mobile.net.PairingPayload

/** First screen on an unpaired phone. */
@Composable
fun WelcomeScreen(onPair: () -> Unit, onScan: () -> Unit, onSettings: () -> Unit, notice: String?) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(24.dp))
        VCore("idle", 0f, Modifier.fillMaxWidth(0.62f).aspectRatio(1f))
        Spacer(Modifier.height(20.dp))
        Text("WELCOME TO VIPER MOBILE", fontSize = 19.sp, letterSpacing = 2.5.sp, textAlign = TextAlign.Center, modifier = Modifier.testTag("welcome-title"))
        Spacer(Modifier.height(8.dp))
        Text("Connect your device to your personal intelligence system.", color = Ink2, textAlign = TextAlign.Center)
        if (!notice.isNullOrBlank()) { Spacer(Modifier.height(14.dp)); Panel { Text(notice, color = Ink2, fontSize = 13.sp) } }
        Spacer(Modifier.height(28.dp))
        VButton("Pair with PC", onPair, Modifier.fillMaxWidth(), primary = true)
        Spacer(Modifier.height(10.dp))
        VButton("Scan QR Code", onScan, Modifier.fillMaxWidth())
        Spacer(Modifier.height(10.dp))
        VButton("Connection Settings", onSettings, Modifier.fillMaxWidth())
        Spacer(Modifier.height(18.dp))
        Text("The connection is encrypted and pinned to your PC's certificate. Nothing goes through the cloud.", color = Mist, fontSize = 12.sp, textAlign = TextAlign.Center)
    }
}

/** Step-by-step pairing: scan or paste the code, then wait for the PC owner to approve. */
@Composable
fun PairGuideScreen(back: () -> Unit, onScan: () -> Unit, onPair: (String) -> Unit, status: String, incoming: String) {
    var manual by remember(incoming) { mutableStateOf(incoming) }
    val preview = remember(manual) { runCatching { PairingPayload.parse(manual) }.getOrNull() }
    val waiting = status.startsWith("Waiting") || status == "Pairing…"
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Pair with PC", back)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Panel(title = "On your PC") {
                Text("1.  Open VIPER → Manage → Connected Devices.", color = Ink2)
                Text("2.  Choose “Add new device”. A QR code appears; it works once and expires after five minutes.", color = Ink2)
            }
            Panel(title = "On this phone") {
                Text("3.  Scan the code. Both devices must be on the same Wi-Fi, or connected through your VPN.", color = Ink2)
                Text("4.  Approve this phone when VIPER asks on the PC. Nothing is paired until you do.", color = Ink2)
                Spacer(Modifier.height(8.dp))
                VButton("Scan QR Code", onScan, Modifier.fillMaxWidth(), primary = true, enabled = !waiting)
            }
            OutlinedTextField(manual, { manual = it }, Modifier.fillMaxWidth(), label = { Text("Or paste the pairing code text") }, maxLines = 4)
            preview?.let { Text("PC: ${it.name} · ${it.hosts.joinToString()}", color = Ink2, fontSize = 12.sp) }
            VButton("Pair", { onPair(manual) }, Modifier.fillMaxWidth(), enabled = manual.isNotBlank() && !waiting)
            if (status.isNotBlank()) Panel {
                if (waiting) LinearProgressIndicator(Modifier.fillMaxWidth(), color = Ink, trackColor = Line)
                Text(status, modifier = Modifier.padding(top = 6.dp).testTag("pair-status"))
            }
        }
    }
}

/** Before pairing: an address to try first (e.g. the PC's VPN address). */
@Composable
fun PreConnectionSettings(app: ViperApp, back: () -> Unit) {
    var host by remember { mutableStateOf(app.store.hostOverride) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Header("Connection Settings", back)
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Panel(title = "Same network") { Text("At home, the phone finds the PC through the addresses inside the QR code. Nothing to set.", color = Ink2) }
            Panel(title = "Away from home") {
                Text("VIPER never opens ports on your router. Install a private VPN such as WireGuard or Tailscale on the PC and the phone, then enter the PC's VPN address here before pairing.", color = Ink2)
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(host, { host = it }, Modifier.fillMaxWidth(), label = { Text("PC address to try first (optional)") }, singleLine = true)
                Spacer(Modifier.height(8.dp))
                VButton("Save", { app.store.hostOverride = host; back() }, primary = true)
            }
        }
    }
}
