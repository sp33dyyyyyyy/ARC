package com.viper.mobile.notify

import org.json.JSONArray
import org.json.JSONObject

/**
 * Pure notification rules (no Android types) so they can be unit-tested:
 * which channel a VIPER notification uses, which action buttons it gets, a stable Android
 * notification id derived from the PC's notification id, and duplicate suppression.
 */
object NotifyLogic {
    const val CH_INPUT = "viper_input"
    const val CH_APPROVAL = "viper_approval"
    const val CH_CODE = "viper_code"
    const val CH_TASKS = "viper_tasks"
    const val CH_SYSTEM = "viper_system"
    const val CH_GENERAL = "viper_general"

    /** id, user-visible name, description, high importance? */
    val CHANNELS = listOf(
        Triple(CH_INPUT, "Input required", "VIPER needs an answer from you to continue a task") to true,
        Triple(CH_APPROVAL, "Approval requests", "VIPER asks before doing something sensitive") to true,
        Triple(CH_CODE, "Code Agent", "Builds finished, projects ready for review") to true,
        Triple(CH_TASKS, "Tasks and downloads", "Tasks, downloads and reminders that finished") to false,
        Triple(CH_SYSTEM, "System alerts", "Problems on your PC that need attention") to true,
        Triple(CH_GENERAL, "General", "Other messages from VIPER") to false,
    )

    fun channelFor(kind: String?, category: String?): String = when (kind) {
        "input_required" -> CH_INPUT
        "approval_required" -> CH_APPROVAL
        "code_complete", "project_complete" -> CH_CODE
        "task_complete", "download_complete" -> CH_TASKS
        "error", "system_alert" -> CH_SYSTEM
        else -> when (category) { "input" -> CH_INPUT; "approval" -> CH_APPROVAL; "code" -> CH_CODE; "system" -> CH_SYSTEM; "reminder", "automation", "research" -> CH_TASKS; else -> CH_GENERAL }
    }

    /**
     * Action buttons as (actionId, label). "open"/"view"/"respond"/"review" open the app at the linked
     * screen; "dismiss" only removes the notification — it never approves or declines anything.
     */
    fun actionsFor(n: JSONObject): List<Pair<String, String>> {
        val fromPc = parseActions(n.opt("actions"))
        if (fromPc.isNotEmpty()) return fromPc.filter { it.first in KNOWN_ACTIONS }
        return when (n.optString("kind")) {
            "input_required" -> listOf("respond" to "Respond", "view" to "View Task")
            "approval_required" -> listOf("review" to "Review Request", "dismiss" to "Dismiss")
            "code_complete", "project_complete" -> listOf("view" to "View Results", "open" to "Open VIPER")
            else -> emptyList()
        }
    }
    private val KNOWN_ACTIONS = setOf("respond", "view", "review", "dismiss", "open")
    private fun parseActions(raw: Any?): List<Pair<String, String>> {
        val arr = when (raw) { is JSONArray -> raw; is String -> runCatching { JSONArray(raw) }.getOrNull(); else -> null } ?: return emptyList()
        return (0 until arr.length()).mapNotNull { i -> arr.optJSONArray(i)?.let { a -> if (a.length() >= 2) a.getString(0) to a.getString(1) else null } }
    }

    fun link(n: JSONObject): JSONObject? = when (val l = n.opt("link")) { is JSONObject -> l; is String -> runCatching { JSONObject(l) }.getOrNull(); else -> null }

    /** Stable, positive id so the same PC notification always replaces itself instead of stacking. */
    fun androidId(serverId: String): Int = (serverId.hashCode() and 0x3fffffff) + 1000

    fun isHigh(n: JSONObject): Boolean = n.optString("priority") in setOf("high", "urgent") || channelFor(n.optString("kind"), n.optString("category")) in setOf(CH_INPUT, CH_APPROVAL, CH_SYSTEM)

    /** Short text for the notification body: never longer than the PC's own phrase + detail. */
    fun text(n: JSONObject): String = n.optString("body").ifBlank { n.optString("phrase") }.take(400)
}

/** Remembers which PC notifications were already shown (live socket, missed list and push can all deliver the same one). */
class Deduper(private val capacity: Int = 300, initial: Collection<String> = emptyList()) {
    private val seen = LinkedHashSet<String>(initial)
    @Synchronized fun firstTime(id: String): Boolean {
        if (id.isBlank()) return true
        if (!seen.add(id)) return false
        while (seen.size > capacity) seen.remove(seen.first())
        return true
    }
    @Synchronized fun snapshot(): List<String> = seen.toList()
}
