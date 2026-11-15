package com.viper.mobile

import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.viper.mobile.net.Backoff
import com.viper.mobile.net.Discovery
import com.viper.mobile.net.PairingPayload
import com.viper.mobile.notify.Deduper
import com.viper.mobile.notify.NotifyLogic
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NotifyPairingTest {
    /** The QR image here was produced by the PC's real pairing code (createPairing), not hand-written. */
    @Test fun decodesThePcsPairingQrCode() {
        // Luminance of every pixel of pairing-qr.png (the PNG the PC shows), with an 8-byte width/height header.
        val raw = javaClass.getResourceAsStream("/pairing-qr.lum")!!.readBytes()
        val w = java.nio.ByteBuffer.wrap(raw, 0, 8).int; val h = java.nio.ByteBuffer.wrap(raw, 4, 4).int
        val pixels = raw.copyOfRange(8, raw.size)
        val text = MultiFormatReader().decode(BinaryBitmap(HybridBinarizer(PlanarYUVLuminanceSource(pixels, w, h, 0, 0, w, h, false)))).text
        val expected = JSONObject(javaClass.getResourceAsStream("/pairing-qr.expected.json")!!.bufferedReader().readText())
        val p = PairingPayload.parse(text)
        assertEquals(expected.getInt("port"), p.port)
        assertEquals(expected.getString("fingerprint"), p.fingerprint)
        assertEquals(List(expected.getJSONArray("hosts").length()) { expected.getJSONArray("hosts").getString(it) }, p.hosts)
        // The same payload pasted as text (the "code" shown under the QR) parses to the same thing.
        assertEquals(p.token, PairingPayload.parse(expected.getString("code")).token)
    }

    @Test fun channelsFollowTheKindOfNotification() {
        assertEquals(NotifyLogic.CH_INPUT, NotifyLogic.channelFor("input_required", null))
        assertEquals(NotifyLogic.CH_APPROVAL, NotifyLogic.channelFor("approval_required", "approval"))
        assertEquals(NotifyLogic.CH_CODE, NotifyLogic.channelFor("code_complete", "code"))
        assertEquals(NotifyLogic.CH_CODE, NotifyLogic.channelFor("project_complete", null))
        assertEquals(NotifyLogic.CH_TASKS, NotifyLogic.channelFor("download_complete", null))
        assertEquals(NotifyLogic.CH_SYSTEM, NotifyLogic.channelFor("error", null))
        assertEquals(NotifyLogic.CH_SYSTEM, NotifyLogic.channelFor("system_alert", "system"))
        assertEquals(NotifyLogic.CH_TASKS, NotifyLogic.channelFor(null, "reminder"))
        assertEquals(NotifyLogic.CH_GENERAL, NotifyLogic.channelFor(null, "general"))
        assertEquals(6, NotifyLogic.CHANNELS.map { it.first.first }.toSet().size)
    }

    @Test fun actionButtonsNeverIncludeAnApproveShortcut() {
        val approval = JSONObject().put("kind", "approval_required").put("actions", JSONArray("[[\"review\",\"Review Request\"],[\"dismiss\",\"Dismiss\"]]"))
        assertEquals(listOf("review" to "Review Request", "dismiss" to "Dismiss"), NotifyLogic.actionsFor(approval))
        // An unknown action from the PC (e.g. "approve") is dropped: approving needs the review screen.
        val tampered = JSONObject().put("kind", "approval_required").put("actions", "[[\"approve\",\"Approve\"],[\"review\",\"Review Request\"]]")
        assertEquals(listOf("review" to "Review Request"), NotifyLogic.actionsFor(tampered))
        assertEquals(listOf("respond" to "Respond", "view" to "View Task"), NotifyLogic.actionsFor(JSONObject().put("kind", "input_required")))
        assertEquals(listOf("view" to "View Results", "open" to "Open VIPER"), NotifyLogic.actionsFor(JSONObject().put("kind", "code_complete")))
        assertTrue(NotifyLogic.actionsFor(JSONObject().put("kind", "task_complete")).isEmpty())
    }

    @Test fun pushPayloadLinkIsParsedFromString() {
        // FCM data values are strings; the link arrives JSON-encoded.
        val n = JSONObject().put("id", "ntf_1").put("kind", "input_required").put("link", "{\"type\":\"decision\",\"id\":\"dec_1\",\"runId\":\"run_1\"}")
        assertEquals("run_1", NotifyLogic.link(n)!!.getString("runId"))
        assertEquals("I need your input, sir.", NotifyLogic.text(JSONObject().put("body", "I need your input, sir.")))
    }

    @Test fun sameNotificationGetsTheSameAndroidIdAndIsShownOnce() {
        assertEquals(NotifyLogic.androidId("ntf_abc"), NotifyLogic.androidId("ntf_abc"))
        assertNotEquals(NotifyLogic.androidId("ntf_abc"), NotifyLogic.androidId("ntf_abd"))
        assertTrue(NotifyLogic.androidId("x") > 0)
        val d = Deduper(capacity = 3)
        assertTrue(d.firstTime("a")); assertFalse(d.firstTime("a"))
        d.firstTime("b"); d.firstTime("c"); d.firstTime("d")
        assertTrue("oldest entries are forgotten", d.firstTime("a"))
        assertEquals(listOf("c", "d", "a"), d.snapshot())
    }

    @Test fun discoveryMessagesAndBackoff() {
        val req = JSONObject(String(Discovery.request("AA:BB:" + "CC".repeat(30))))
        assertEquals("discover", req.getString("viper"))
        assertEquals("aabb" + "cc".repeat(30), req.getString("fp"))
        assertEquals(47801 to "DESKTOP", Discovery.parseReply("{\"viper\":\"here\",\"port\":47801,\"name\":\"DESKTOP\"}".toByteArray()))
        assertNull(Discovery.parseReply("{\"viper\":\"discover\"}".toByteArray()))
        assertNull(Discovery.parseReply("garbage".toByteArray()))
        var b = Backoff.START; val seq = mutableListOf<Long>(); repeat(7) { seq += b; b = Backoff.next(b) }
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L, 16000L, 30000L, 30000L), seq)
        assertEquals(800L, Backoff.withJitter(1000, 0.0)); assertEquals(1200L, Backoff.withJitter(1000, 1.0))
    }
}
