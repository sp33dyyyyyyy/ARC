package com.viper.mobile.net

import org.json.JSONObject

/** Contents of the QR code shown by the desktop app. */
data class PairingPayload(val name: String, val hosts: List<String>, val port: Int, val fingerprint: String, val token: String, val expiresAt: Long) {
    companion object {
        /** Accepts the QR JSON, the same JSON base64url-encoded, or a viper://pair?c=<base64url> link. */
        fun normalize(text: String): String {
            var t = text.trim()
            if (t.startsWith("viper:", ignoreCase = true)) t = java.net.URLDecoder.decode(t.substringAfter("c=", "").substringBefore('&'), "UTF-8")
            if (!t.startsWith("{")) t = try { String(java.util.Base64.getUrlDecoder().decode(t.replace("=", "").replace('+', '-').replace('/', '_')), Charsets.UTF_8) } catch (e: IllegalArgumentException) { t }
            return t
        }

        fun parse(text: String): PairingPayload {
            val o = try { JSONObject(normalize(text)) } catch (e: org.json.JSONException) { throw IllegalArgumentException("This is not a VIPER pairing code") }
            require(o.optString("app") == "viper") { "This is not a VIPER pairing code" }
            require(o.optInt("v") == 1) { "Unsupported pairing code version" }
            val hosts = o.getJSONArray("hosts").let { a -> List(a.length()) { a.getString(it) } }
            require(hosts.isNotEmpty()) { "The pairing code contains no PC address" }
            val fp = o.getString("fp")
            require(PinnedTrustManager.normalize(fp).length == 64) { "Invalid certificate fingerprint" }
            return PairingPayload(o.optString("name", "PC"), hosts, o.getInt("port"), fp, o.getString("token"), o.optLong("exp", 0))
        }
    }
}
