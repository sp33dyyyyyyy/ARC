package com.viper.mobile

import android.Manifest
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import com.viper.mobile.net.Conn
import com.viper.mobile.net.PairingPayload
import com.viper.mobile.notify.Notifier
import kotlinx.coroutines.delay
import com.viper.mobile.ui.*
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FragmentActivity() {
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
        i?.getStringExtra(Notifier.EXTRA_ACTION)?.let { action ->
            val link = i.getStringExtra(Notifier.EXTRA_LINK)?.let { runCatching { JSONObject(it) }.getOrNull() }
            app.openFromNotification(action, link, i.getStringExtra(Notifier.EXTRA_NOTIFICATION_ID))
            i.removeExtra(Notifier.EXTRA_ACTION)
            return
        }
        val code = when (i?.action) {
            android.content.Intent.ACTION_SEND -> i.getStringExtra(android.content.Intent.EXTRA_TEXT)
            android.content.Intent.ACTION_VIEW -> i.data?.takeIf { it.scheme == "viper" && it.host == "pair" }?.toString()
            else -> null
        } ?: return
        if (app.client.state.value == Conn.UNPAIRED) { incomingCode.value = code; welcomePage.value = "pair"; pairStatus.value = "Pairing code received. Check the PC name, then tap Pair." }
    }

    fun requestSmsPermission() = perms.launch(arrayOf(Manifest.permission.SEND_SMS))

    private val welcomePage = mutableStateOf("welcome")
    private fun scanCode() = scan.launch(ScanOptions().setPrompt("Scan the VIPER pairing code").setBeepEnabled(false).setOrientationLocked(false).setDesiredBarcodeFormats(ScanOptions.QR_CODE))
    private fun pairWith(text: String) {
        welcomePage.value = "pair"
        pairStatus.value = "Pairing…"
        lifecycleScope.launch {
            pairStatus.value = try {
                val p = PairingPayload.parse(text)
                app.client.pair(p, "${Build.MANUFACTURER} ${Build.MODEL}".trim()) { msg -> runOnUiThread { pairStatus.value = msg } }
                app.client.connect(); welcomePage.value = "welcome"; ""
            } catch (e: Exception) { "Pairing failed: ${e.message}" }
        }
    }

    /**
     * Ask for the phone's screen lock (biometrics, PIN, pattern or password) before an approval is
     * sent. Phones without a screen lock fall back to the explicit tap on the review screen.
     */
    fun authenticate(title: String, done: (Boolean) -> Unit) {
        val auth = BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
        if (BiometricManager.from(this).canAuthenticate(auth) != BiometricManager.BIOMETRIC_SUCCESS) { done(true); return }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { done(true) }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { done(false) }
        })
        prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("Confirm it's you").setSubtitle(title).setAllowedAuthenticators(auth).build())
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
        val sms by app.pendingSms.collectAsState()
        if (conn == Conn.UNPAIRED) Welcome() else Main()
        sms?.let { s ->
            AlertDialog(onDismissRequest = {}, containerColor = Ink, titleContentColor = Void, textContentColor = Void,
                title = { Text("Send SMS from this phone?") },
                text = { Text("To: ${s.optString("to")}\n\n${s.optString("body")}\n\nRequested by VIPER on your PC. Carrier charges may apply.") },
                confirmButton = { Button({ if (!app.store.smsBridge) { app.store.smsBridge = true; requestSmsPermission() }; app.answerSms(true) }, colors = ButtonDefaults.buttonColors(containerColor = Void, contentColor = Ink)) { Text("Send") } },
                dismissButton = { TextButton({ app.answerSms(false) }) { Text("Decline", color = Void) } })
        }
    }

    @Composable
    fun Welcome() {
        var page by welcomePage
        val err by app.client.lastError.collectAsState()
        BackHandler(page != "welcome") { page = "welcome" }
        when (page) {
            "pair" -> PairGuideScreen({ page = "welcome" }, { scanCode() }, { pairWith(it) }, pairStatus.value, incomingCode.value)
            "settings" -> PreConnectionSettings(app) { page = "welcome" }
            else -> WelcomeScreen({ page = "pair" }, { scanCode() }, { page = "settings" }, err)
        }
    }

    @Composable
    fun Main() {
        var tab by rememberSaveable { mutableStateOf("prompt") }
        var sub by rememberSaveable { mutableStateOf<String?>(null) }
        var visionImage by remember { mutableStateOf<String?>(null) }
        var review by remember { mutableStateOf<JSONObject?>(null) }
        val conn by app.client.state.collectAsState()
        val confirm by app.pendingConfirm.collectAsState()
        val link by app.pendingLink.collectAsState()
        // An approval request arriving while the app is open goes straight to the review screen.
        LaunchedEffect(confirm?.optString("id")) { confirm?.let { if (review == null) review = it } }
        // A request answered on the PC (or that expired) must not stay on screen as if it were pending.
        val closed by app.closedConfirms.collectAsState()
        LaunchedEffect(closed, review?.optString("id")) { review?.let { r -> if (r.optString("id") in closed) { review = null; app.notifyUser("Request closed", "It was answered on your PC, or it expired.", "closed:${r.optString("id")}") } } }
        // Notification taps (deep links).
        LaunchedEffect(link) {
            val (action, l) = link ?: return@LaunchedEffect
            app.pendingLink.value = null
            when (l?.optString("type")) {
                "confirm" -> { val id = l.optString("id"); var c = confirm?.takeIf { it.optString("id") == id }
                    if (c == null) { repeat(10) { if (app.client.state.value != Conn.ONLINE) delay(500) }; c = app.loadConfirm(id) }
                    if (c != null) review = c else { tab = "manage"; sub = "notifications"; app.notifyUser("Request no longer pending", "It was answered, or it expired, on your PC.") } }
                "decision", "agent_run" -> { tab = "make"; sub = "run:${l.optString(if (l.optString("type") == "decision") "runId" else "id")}" }
                "agent_project" -> { tab = "make"; sub = "agent" }
                "system" -> { tab = "manage"; sub = "pc" }
                "download" -> { tab = "intel"; sub = "models" }
                else -> { tab = "manage"; sub = if (action == "open" && l == null) null else "notifications" }
            }
        }
        BackHandler(review != null || sub != null || tab != "prompt") { when { review != null -> review = null; sub != null -> sub = null; else -> tab = "prompt" } }
        val chatImage: () -> Unit = { imageTarget = { img -> app.send("Describe this image.", attachments = JSONArray().put(JSONObject().put("type", "image").put("name", "photo.jpg").put("data", img))) } }
        val openRun: (String) -> Unit = { id -> tab = "make"; sub = "run:$id" }
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("V I P E R", fontSize = 13.sp, letterSpacing = 3.sp, modifier = Modifier.weight(1f)); ConnBadge(conn, app.store.pairing?.serverName ?: "PC")
            }
            HorizontalDivider(color = Line)
            Box(Modifier.weight(1f)) {
                val r = review
                if (r != null) ApprovalReviewScreen(app, r, { t, done -> authenticate(t, done) }) { review = null }
                else when (val s0 = sub) {
                    "vision" -> VisionScreen(app, { sub = null }, visionImage, { imageTarget = { visionImage = it }; pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, { imageTarget = { visionImage = it }; takePhoto() })
                    "chat" -> Column { Header("Chat") { sub = null }; ChatScreen(app, { chatImage(); pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, { chatImage(); takePhoto() }) }
                    "files" -> FilesScreen(app, { sub = null }) { upload.launch(arrayOf("*/*")) }
                    "reminders" -> RemindersScreen(app) { sub = null }
                    "automations" -> AutomationsScreen(app) { sub = null }
                    "notifications" -> NotificationHistoryScreen(app, { sub = null }) { a, l -> app.openFromNotification(a, l, null) }
                    "code" -> CodeScreen(app) { sub = null }
                    "agent" -> AgentProjectsScreen(app, { sub = null }, openRun)
                    "tasks" -> TasksScreen(app, { sub = null }, openRun)
                    "models" -> ModelsScreen(app) { sub = null }
                    "pc" -> Column { Header("PC Control") { sub = null }; PcScreen(app) }
                    else -> when {
                        s0 != null && s0.startsWith("run:") -> AgentRunScreen(app, s0.removePrefix("run:")) { sub = "agent" }
                        tab == "prompt" -> PromptHome { sub = it }
                        tab == "settings" -> SettingsScreen(app) { tab = "prompt" }
                        else -> CategoryMenu(tab, MOBILE_CATEGORIES.first { it.first == tab }.second) { sub = it }
                    }
                }
            }
            NavigationBar(containerColor = Void, tonalElevation = 0.dp) {
                MOBILE_CATEGORIES.forEach { (id, label) ->
                    NavigationBarItem(selected = tab == id && sub == null && review == null, onClick = { tab = id; sub = null; review = null }, icon = { Box(Modifier.size(6.dp).background(if (tab == id) Ink else Line2)) },
                        label = { Text(label, fontSize = 11.sp, maxLines = 1) }, modifier = Modifier.testTag("tab-$id"),
                        colors = NavigationBarItemDefaults.colors(selectedTextColor = Ink, unselectedTextColor = Mist, indicatorColor = Void))
                }
            }
        }
    }

    /** PROMPT: the core and quick conversation, or the offline screen when the PC cannot be reached. */
    @Composable
    fun PromptHome(open: (String) -> Unit) {
        val conn by app.client.state.collectAsState()
        var showOffline by remember { mutableStateOf(false) }
        LaunchedEffect(conn) { if (conn == Conn.ONLINE) showOffline = false else { delay(2500); showOffline = app.client.state.value != Conn.ONLINE } }
        Column(Modifier.fillMaxSize()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton({ open("chat") }) { Text("Chat", color = Ink2) }; TextButton({ open("vision") }) { Text("Live Vision", color = Ink2) }
            }
            if (showOffline) OfflinePanel(app, Modifier.verticalScroll(rememberScrollState())) else HomeScreen(app) { open("chat") }
        }
    }
}
