package com.viper.mobile.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

/** Pairing credentials and preferences, encrypted with an Android Keystore key. */
data class Pairing(val deviceId: String, val secret: String, val hosts: List<String>, val port: Int, val fingerprint: String, val serverName: String) {
    val authHeader get() = "Bearer $deviceId.$secret"
}

@Suppress("DEPRECATION")
class Store(context: Context) {
    private val prefs: SharedPreferences = try {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(context, "viper_secure", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV, EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    } catch (e: Exception) {
        // Keystore unavailable (very rare): refuse to store secrets in plain text.
        throw IllegalStateException("Secure storage is unavailable on this device", e)
    }

    var pairing: Pairing?
        get() {
            val j = prefs.getString("pairing", null) ?: return null
            return try {
                val o = JSONObject(j)
                val hosts = o.getJSONArray("hosts").let { a -> List(a.length()) { a.getString(it) } }
                Pairing(o.getString("deviceId"), o.getString("secret"), hosts, o.getInt("port"), o.getString("fp"), o.optString("serverName", "PC"))
            } catch (e: Exception) { null }
        }
        set(p) {
            if (p == null) { prefs.edit().remove("pairing").apply(); return }
            val o = JSONObject().put("deviceId", p.deviceId).put("secret", p.secret).put("hosts", JSONArray(p.hosts)).put("port", p.port).put("fp", p.fingerprint).put("serverName", p.serverName)
            prefs.edit().putString("pairing", o.toString()).apply()
        }

    /** A host the user typed (e.g. a VPN address) is tried first. */
    var hostOverride: String
        get() = prefs.getString("hostOverride", "") ?: ""
        set(v) = prefs.edit().putString("hostOverride", v.trim()).apply()
    var lastHost: String
        get() = prefs.getString("lastHost", "") ?: ""
        set(v) = prefs.edit().putString("lastHost", v).apply()
    var usePcVoice: Boolean
        get() = prefs.getBoolean("usePcVoice", true)
        set(v) = prefs.edit().putBoolean("usePcVoice", v).apply()
    var speakReplies: Boolean
        get() = prefs.getBoolean("speakReplies", true)
        set(v) = prefs.edit().putBoolean("speakReplies", v).apply()
    var stayConnected: Boolean
        get() = prefs.getBoolean("stayConnected", false)
        set(v) = prefs.edit().putBoolean("stayConnected", v).apply()
    var handsFree: Boolean
        get() = prefs.getBoolean("handsFree", false)
        set(v) = prefs.edit().putBoolean("handsFree", v).apply()
    var smsBridge: Boolean
        get() = prefs.getBoolean("smsBridge", false)
        set(v) = prefs.edit().putBoolean("smsBridge", v).apply()
    var lastNotificationTs: Long
        get() = prefs.getLong("lastNotifTs", System.currentTimeMillis())
        set(v) = prefs.edit().putLong("lastNotifTs", v).apply()
    var conversationId: String?
        get() = prefs.getString("conversationId", null)
        set(v) = prefs.edit().putString("conversationId", v).apply()

    // ---- offline queue (requests the user made while the PC was unreachable) ----
    fun queue(): List<JSONObject> {
        val a = JSONArray(prefs.getString("queue", "[]"))
        return List(a.length()) { a.getJSONObject(it) }
    }
    fun enqueue(item: JSONObject) {
        val a = JSONArray(prefs.getString("queue", "[]")); a.put(item)
        prefs.edit().putString("queue", a.toString()).apply()
    }
    fun setQueue(items: List<JSONObject>) = prefs.edit().putString("queue", JSONArray(items).toString()).apply()
}
