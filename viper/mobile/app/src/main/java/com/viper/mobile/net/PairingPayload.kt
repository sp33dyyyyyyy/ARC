package com.viper.mobile.net

import org.json.JSONObject

/** Contents of the QR code shown by the desktop app. */
data class PairingPayload(val name: String, val hosts: List<String>, val port: Int, val fingerprint: String, val token: String, val expiresAt: Long) {
    companion object {
        fun parse(text: String): PairingPayload {
            val o = JSONObject(text.trim())
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
