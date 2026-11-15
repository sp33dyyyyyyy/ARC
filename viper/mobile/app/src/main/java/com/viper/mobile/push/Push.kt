package com.viper.mobile.push

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.viper.mobile.ViperApp
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import kotlin.coroutines.resume

/**
 * Optional push through Firebase Cloud Messaging so VIPER can reach the phone while the app is
 * closed. It uses the PC owner's own Firebase project: the PC sends the client configuration over
 * the paired, encrypted link, so nothing about it is baked into the app. Without it, notifications
 * arrive only while VIPER Mobile is connected (app open, or the "Stay connected" service running).
 */
object Push {
    private const val TAG = "VIPER-push"

    /** Initialise Firebase from the stored configuration (called at app start, also when started by a push). */
    fun init(ctx: Context): Boolean {
        val cfg = (ctx.applicationContext as ViperApp).store.pushConfig?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return false
        if (FirebaseApp.getApps(ctx).isNotEmpty()) return true
        return try {
            FirebaseApp.initializeApp(ctx, FirebaseOptions.Builder().setProjectId(cfg.getString("projectId")).setApplicationId(cfg.getString("appId"))
                .setApiKey(cfg.getString("apiKey")).setGcmSenderId(cfg.getString("senderId")).build()); true
        } catch (e: Exception) { Log.w(TAG, "Firebase init failed: ${e.message}"); false }
    }

    /** Fetch the PC's push configuration and register this phone's token. Returns a status line for Settings. */
    suspend fun register(app: ViperApp): String {
        val cfg = try { app.client.getObj("/api/v1/device/push-config") } catch (e: Exception) { return "Could not ask the PC: ${e.message}" }
        if (cfg.optString("provider") != "fcm") {
            if (app.store.pushConfig != null) { app.store.pushConfig = null; runCatching { app.client.post("/api/v1/device/push", JSONObject().put("token", JSONObject.NULL)) } }
            return "Push is not set up on the PC — notifications arrive while VIPER Mobile is connected."
        }
        val changed = app.store.pushConfig?.let { JSONObject(it).optString("appId") != cfg.optString("appId") } ?: true
        app.store.pushConfig = cfg.toString()
        if (changed && FirebaseApp.getApps(app).isNotEmpty()) return "Push configuration changed — restart VIPER Mobile to apply it."
        if (!init(app)) return "Firebase could not start with the PC's configuration."
        val token = try { suspendCancellableCoroutine<String?> { c -> FirebaseMessaging.getInstance().token.addOnCompleteListener { t -> c.resume(if (t.isSuccessful) t.result else null) } } } catch (e: Exception) { null }
            ?: return "Could not get a push token (Google Play services missing or offline)."
        app.store.pushToken = token
        if (app.store.pushRegisteredToken != token) {
            try { app.client.post("/api/v1/device/push", JSONObject().put("provider", "fcm").put("token", token)); app.store.pushRegisteredToken = token } catch (e: Exception) { return "Could not register with the PC: ${e.message}" }
        }
        return "Push notifications are on: VIPER can reach this phone while the app is closed."
    }
}

/** Receives data-only pushes and shows them with the same channels, actions and deep links as live notifications. */
class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        val app = application as ViperApp
        app.store.pushToken = token; app.store.pushRegisteredToken = null
        app.scope.launch { if (app.client.state.value == com.viper.mobile.net.Conn.ONLINE) Push.register(app) }
    }
    override fun onMessageReceived(message: RemoteMessage) {
        val app = application as ViperApp
        val d = message.data
        val n = JSONObject()
        for ((k, v) in d) n.put(k, v)
        if (n.optString("id").isBlank()) return
        app.showNotification(n, fromPush = true)
    }
}
