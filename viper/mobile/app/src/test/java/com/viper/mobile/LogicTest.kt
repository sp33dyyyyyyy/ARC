package com.viper.mobile

import com.viper.mobile.net.PairingPayload
import com.viper.mobile.net.PinnedTrustManager
import com.viper.mobile.voice.extractCommand
import com.viper.mobile.voice.pcmToWav
import org.junit.Assert.*
import org.junit.Test

class LogicTest {
    private val fp = (0 until 32).joinToString(":") { "%02X".format(it) }

    @Test fun parsesValidPairingCode() {
        val p = PairingPayload.parse("""{"v":1,"app":"viper","name":"DESKTOP","hosts":["192.168.1.20","100.64.0.5"],"port":47801,"fp":"$fp","token":"abc","exp":${System.currentTimeMillis() + 60000}}""")
        assertEquals(listOf("192.168.1.20", "100.64.0.5"), p.hosts)
        assertEquals(47801, p.port)
        assertEquals("abc", p.token)
    }

    @Test fun acceptsBase64AndLinkForms() {
        val json = """{"v":1,"app":"viper","name":"PC","hosts":["10.0.2.2"],"port":47801,"fp":"$fp","token":"t1","exp":0}"""
        val b64 = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(json.toByteArray())
        assertEquals("t1", PairingPayload.parse(b64).token)
        assertEquals(listOf("10.0.2.2"), PairingPayload.parse("viper://pair?c=$b64").hosts)
        assertThrows(IllegalArgumentException::class.java) { PairingPayload.parse("hello world") }
    }

    @Test fun rejectsForeignQrCodes() {
        assertThrows(IllegalArgumentException::class.java) { PairingPayload.parse("""{"v":1,"app":"other","hosts":["1.2.3.4"],"port":1,"fp":"$fp","token":"x"}""") }
        assertThrows(IllegalArgumentException::class.java) { PairingPayload.parse("""{"v":1,"app":"viper","hosts":["1.2.3.4"],"port":1,"fp":"AA:BB","token":"x"}""") }
    }

    @Test fun fingerprintNormalisation() {
        assertEquals(PinnedTrustManager.normalize("aa:bb:cc"), "AABBCC")
        assertEquals(64, PinnedTrustManager.sha256Hex(byteArrayOf(1, 2, 3)).length)
    }

    @Test fun wakeWordExtraction() {
        assertEquals("open spotify", extractCommand("Viper, open Spotify."))
        assertEquals("what time is it", extractCommand("Hey Viper what time is it"))
        assertEquals("", extractCommand("viper"))
        assertEquals("check my email", extractCommand("wiper check my email"))
        assertNull(extractCommand("the weather is nice today and the viper is a snake"))
    }

    @Test fun wavHeader() {
        val wav = pcmToWav(ByteArray(3200))
        assertEquals("RIFF", String(wav.copyOfRange(0, 4)))
        assertEquals("WAVE", String(wav.copyOfRange(8, 12)))
        assertEquals(44 + 3200, wav.size)
    }
}
