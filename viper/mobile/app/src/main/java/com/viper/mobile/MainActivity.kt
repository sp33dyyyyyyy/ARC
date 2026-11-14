package com.viper.mobile

import android.Manifest
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.viper.mobile.net.Conn
import com.viper.mobile.net.PairingPayload
import com.viper.mobile.ui.*
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : ComponentActivity() {
    private val app get() = application as ViperApp
    private var imageTarget: ((String) -> Unit)? = null
    private var photoUri: Uri? = null
    private var pairStatus = mutableStateOf("")
    private var incomingCode = mutableStateOf("")

    private val perms = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { }
    private val scan = registerForActivityResult(ScanContract()) { r -> r.contents?.let { pairWith(it) } }
    private val pick = registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { loadImage(it) } }
    private val photo = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok -> if (ok) photoUri?.let { loadImage(it) } }
    private val upload = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let { uploadFile(it) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val want = mutableListOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
        if (Build.VERSION.SDK_INT >= 33) want += Manifest.permission.POST_NOTIFICATIONS
        perms.launch(want.toTypedArray())
        ConnectionService.update(this)
        handleIntent(intent)
        setContent { ViperTheme { Surface(Modifier.fillMaxSize(), color = Void) { Root() } } }
    }
    override fun onNewIntent(intent: android.content.Intent) { super.onNewIntent(intent); handleIntent(intent) }

    /** A pairing code shared from another app (text) or opened as a viper://pair link pre-fills the form; the user still taps Pair. */
    private fun handleIntent(i: android.content.Intent?) {
        val code = when (i?.action) {
            android.content.Intent.ACTION_SEND -> i.getStringExtra(android.content.Intent.EXTRA_TEXT)
            android.content.Intent.ACTION_VIEW -> i.data?.takeIf { it.scheme == "viper" && it.host == "pair" }?.toString()
            else -> null
        } ?: return
        if (app.client.state.value == Conn.UNPAIRED) { incomingCode.value = code; pairStatus.value = "Pairing code received. Check the PC name, then tap Pair." }
    }

    fun requestSmsPermission() = perms.launch(arrayOf(Manifest.permission.SEND_SMS))

    private fun pairWith(text: String) {
        pairStatus.value = "Pairing…"
        lifecycleScope.launch {
            pairStatus.value = try {
                val p = PairingPayload.parse(text)
                app.client.pair(p, "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                app.client.connect(); ""
            } catch (e: Exception) { "Pairing failed: ${e.message}" }
        }
    }
    private fun loadImage(uri: Uri) {
        try {
            val bmp = contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it) } ?: return
            imageTarget?.invoke(bitmapToDataUrl(bmp))
        } catch (e: Exception) { app.notifyUser("Image", "Could not read the image: ${e.message}") }
    }
    private fun takePhoto() {
        val dir = File(cacheDir, "camera").apply { mkdirs() }
        val f = File(dir, "photo.jpg"); photoUri = FileProvider.getUriForFile(this, "$packageName.files", f)
        photo.launch(photoUri!!)
    }
    private fun uploadFile(uri: Uri) {
        lifecycleScope.launch {
            try {
                var name = "upload"
                contentResolver.query(uri, null, null, null, null)?.use { c -> if (c.moveToFirst()) name = c.getString(c.getColumnIndexOrThrow(OpenableColumns.DISPLAY_NAME)) }
                val bytes = contentResolver.openInputStream(uri)!!.use { it.readBytes() }
                app.client.postBytes("/api/v1/transfer/upload?name=${Uri.encode(name)}", bytes, "application/octet-stream")
                app.notifyUser("Sent to PC", name)
            } catch (e: Exception) { app.notifyUser("Upload failed", e.message ?: "") }
        }
    }

    @Composable
    fun Root() {
        val conn by app.client.state.collectAsState()
        val confirm by app.pendingConfirm.collectAsState(); val sms by app.pendingSms.collectAsState()
        if (conn == Conn.UNPAIRED) PairScreen() else Main()
        confirm?.let { c ->
            AlertDialog(onDismissRequest = {}, containerColor = Ink, titleContentColor = Void, textContentColor = Void,
                title = { Text(c.optString("title")) },
                text = { Column(Modifier.verticalScroll(rememberScrollState())) { Text(c.optString("reason")); Spacer(Modifier.height(8.dp)); Text(c.optString("preview"), fontFamily = FontFamily.Monospace, fontSize = 12.sp) } },
                confirmButton = { Button({ app.answerConfirm(true) }, colors = ButtonDefaults.buttonColors(containerColor = Void, contentColor = Ink)) { Text("Allow once") } },
                dismissButton = { TextButton({ app.answerConfirm(false) }) { Text("Deny", color = Void) } })
        }
        sms?.let { s ->
            AlertDialog(onDismissRequest = {}, containerColor = Ink, titleContentColor = Void, textContentColor = Void,
                title = { Text("Send SMS from this phone?") },
                text = { Text("To: ${s.optString("to")}\n\n${s.optString("body")}\n\nRequested by VIPER on your PC. Carrier charges may apply.") },
                confirmButton = { Button({ if (!app.store.smsBridge) { app.store.smsBridge = true; requestSmsPermission() }; app.answerSms(true) }, colors = ButtonDefaults.buttonColors(containerColor = Void, contentColor = Ink)) { Text("Send") } },
                dismissButton = { TextButton({ app.answerSms(false) }) { Text("Decline", color = Void) } })
        }
    }

    @Composable
    fun PairScreen() {
        val incoming by incomingCode
        var manual by remember(incoming) { mutableStateOf(incoming) }
        val status by pairStatus; val err by app.client.lastError.collectAsState()
        val preview = remember(manual) { runCatching { PairingPayload.parse(manual) }.getOrNull() }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(20.dp))
            VCore("idle", 0f, Modifier.fillMaxWidth(0.7f).aspectRatio(1f))
            Text("VIPER Mobile", style = MaterialTheme.typography.headlineMedium)
            Text("On your PC open VIPER → Communications → Phone link → Show pairing code, then scan it here. Both devices must be on the same Wi-Fi or VPN.", color = Ink2, modifier = Modifier.padding(vertical = 12.dp))
            VButton("Scan pairing code", { scan.launch(ScanOptions().setPrompt("Scan the VIPER pairing code").setBeepEnabled(false).setOrientationLocked(false).setDesiredBarcodeFormats(ScanOptions.QR_CODE)) }, Modifier.fillMaxWidth(), primary = true)
            Spacer(Modifier.height(16.dp))
            OutlinedTextField(manual, { manual = it }, Modifier.fillMaxWidth(), label = { Text("Or paste the pairing code text") }, maxLines = 4)
            preview?.let { Text("PC: ${it.name} · ${it.hosts.joinToString()}", color = Ink2, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
            VButton("Pair", { pairWith(manual) }, Modifier.fillMaxWidth().padding(top = 8.dp), enabled = manual.isNotBlank())
            if (status.isNotBlank()) Text(status, color = Ink, modifier = Modifier.padding(top = 12.dp))
            err?.let { Text(it, color = Mist, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp)) }
        }
    }

    @Composable
    fun Main() {
        var tab by rememberSaveable { mutableStateOf("home") }
        var sub by rememberSaveable { mutableStateOf<String?>(null) }
        var visionImage by remember { mutableStateOf<String?>(null) }
        val conn by app.client.state.collectAsState()
        BackHandler(sub != null || tab != "home") { if (sub != null) sub = null else tab = "home" }
        val chatImage: () -> Unit = { imageTarget = { img -> app.send("Describe this image.", attachments = JSONArray().put(JSONObject().put("type", "image").put("name", "photo.jpg").put("data", img))) } }
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("V I P E R", fontSize = 13.sp, letterSpacing = 3.sp, modifier = Modifier.weight(1f)); ConnBadge(conn, app.store.pairing?.serverName ?: "PC")
            }
            HorizontalDivider(color = Line)
            Box(Modifier.weight(1f)) {
                when (sub) {
                    "vision" -> VisionScreen(app, { sub = null }, visionImage, { imageTarget = { visionImage = it }; pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, { imageTarget = { visionImage = it }; takePhoto() })
                    "files" -> FilesScreen(app, { sub = null }) { upload.launch(arrayOf("*/*")) }
                    "reminders" -> RemindersScreen(app) { sub = null }
                    "automations" -> AutomationsScreen(app) { sub = null }
                    "notifications" -> NotificationsScreen(app) { sub = null }
                    "code" -> CodeScreen(app) { sub = null }
                    "settings" -> SettingsScreen(app) { sub = null }
                    else -> when (tab) {
                        "chat" -> ChatScreen(app, { chatImage(); pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, { chatImage(); takePhoto() })
                        "pc" -> PcScreen(app)
                        "more" -> MoreMenu { sub = it }
                        else -> HomeScreen(app) { tab = "chat" }
                    }
                }
            }
            NavigationBar(containerColor = Void, tonalElevation = 0.dp) {
                listOf("home" to "Home", "chat" to "Chat", "pc" to "PC", "more" to "More").forEach { (id, label) ->
                    NavigationBarItem(selected = tab == id && sub == null, onClick = { tab = id; sub = null }, icon = { Box(Modifier.size(6.dp).background(if (tab == id) Ink else Line2)) }, label = { Text(label) },
                        colors = NavigationBarItemDefaults.colors(selectedTextColor = Ink, unselectedTextColor = Mist, indicatorColor = Void))
                }
            }
        }
    }
}
