package com.viper.mobile.net

import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager

/**
 * Trusts exactly one certificate: the paired PC's self-signed certificate, identified by the
 * SHA-256 fingerprint delivered in the pairing QR code. Any other certificate is rejected,
 * so a different machine on the network cannot impersonate the PC.
 */
class PinnedTrustManager(fingerprint: String) : X509TrustManager {
    private val expected = normalize(fingerprint)
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException("Client certificates are not used")
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("No certificate presented")
        val actual = sha256Hex(leaf.encoded)
        if (actual != expected) throw CertificateException("This server's certificate does not match the paired PC")
        leaf.checkValidity()
    }
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

    fun socketFactory(): SSLSocketFactory {
        val ctx = SSLContext.getInstance("TLS")
        ctx.init(null, arrayOf(this), null)
        return ctx.socketFactory
    }

    companion object {
        fun normalize(fp: String) = fp.replace(":", "").replace(" ", "").uppercase()
        fun sha256Hex(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02X".format(it) }
    }
}
