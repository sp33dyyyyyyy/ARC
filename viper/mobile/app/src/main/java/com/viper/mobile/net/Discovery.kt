package com.viper.mobile.net

import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException

/**
 * Finds the paired PC on the local network after its IP address changed. The phone broadcasts the
 * PC's certificate fingerprint; only the PC with that certificate answers (and the connection that
 * follows is still pinned to the certificate, so a spoofed answer cannot impersonate the PC).
 */
object Discovery {
    const val DEFAULT_PORT = 47802

    fun request(fingerprint: String): ByteArray = JSONObject().put("viper", "discover").put("fp", PinnedTrustManager.normalize(fingerprint).lowercase()).toString().toByteArray()

    /** Parses a reply; returns (port, name) or null if it is not a VIPER answer. */
    fun parseReply(bytes: ByteArray, len: Int = bytes.size): Pair<Int, String>? = try {
        val o = JSONObject(String(bytes, 0, len, Charsets.UTF_8))
        if (o.optString("viper") == "here" && o.optInt("port") in 1..65535) o.getInt("port") to o.optString("name", "PC") else null
    } catch (_: Exception) { null }

    data class Found(val host: String, val port: Int, val name: String)

    /** Broadcast (and unicast to known hosts); returns the first PC that answers within [timeoutMs]. */
    fun find(fingerprint: String, knownHosts: List<String>, port: Int = DEFAULT_PORT, timeoutMs: Int = 1500): Found? {
        DatagramSocket().use { s ->
            s.broadcast = true; s.soTimeout = timeoutMs
            val msg = request(fingerprint)
            val targets = (listOf("255.255.255.255") + knownHosts.map { it.substringBeforeLast('.') + ".255" } + knownHosts).distinct()
            for (t in targets) runCatching { s.send(DatagramPacket(msg, msg.size, InetAddress.getByName(t), port)) }
            val buf = ByteArray(512)
            val deadline = System.currentTimeMillis() + timeoutMs
            while (System.currentTimeMillis() < deadline) {
                val p = DatagramPacket(buf, buf.size)
                try { s.receive(p) } catch (_: SocketTimeoutException) { return null }
                val r = parseReply(p.data, p.length) ?: continue
                return Found(p.address.hostAddress ?: continue, r.first, r.second)
            }
        }
        return null
    }
}

/** Reconnect delays: exponential, capped, with jitter so many phones do not retry in lock-step. */
object Backoff {
    const val START = 1000L; const val MAX = 30000L
    fun next(current: Long): Long = (current * 2).coerceAtMost(MAX)
    fun withJitter(delay: Long, rnd: Double = Math.random()): Long = (delay * (0.8 + 0.4 * rnd)).toLong()
}
