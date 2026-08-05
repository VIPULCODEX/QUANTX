package com.quantx.cyber_intel_app

/**
 * Pure, Android-free scoring for Mode 1 (the no-permission takeover-capability
 * detector). Kept deliberately free of any android.* reference so it runs as a
 * plain JVM unit test — no emulator, no device — and so the novel, zero-risk
 * detection logic is actually covered by tests (see TakeoverScoringTest).
 *
 * TakeoverProfile (the Android side) reads a service's declared capabilities
 * off the device and hands them here as a CapabilityProfile; this file decides
 * the finding. Mirrors re_pipeline/capability_profile.py so the on-device
 * classifier and the offline research scorer cannot silently diverge.
 */
data class CapabilityProfile(
    val canRetrieveWindowContent: Boolean = false,
    val canPerformGestures: Boolean = false,
    val hasNotificationListener: Boolean = false,
    val requestsOverlay: Boolean = false,
    val fromStoreOrSystem: Boolean = false,
) {
    /** Distinct account-takeover techniques these capabilities enable, as the
     *  taxonomy labels shared with the server registry (_BEHAVIOR_CATEGORY). */
    fun techniques(): List<String> {
        val out = mutableListOf<String>()
        // Auto-tap subsumes screen-read (it needs content retrieval too), so
        // report the single, more severe technique rather than both.
        if (canPerformGestures && canRetrieveWindowContent) out.add("a11y_auto_tap")
        else if (canRetrieveWindowContent) out.add("a11y_screen_read")
        if (requestsOverlay) out.add("overlay_phish")
        if (hasNotificationListener) out.add("notif_intercept")
        return out
    }
}

object TakeoverScoring {

    // Worst technique first, for choosing the dominant reported category.
    private val TECHNIQUE_RANK = mapOf(
        "a11y_auto_tap" to 3,
        "overlay_phish" to 2,
        "notif_intercept" to 1,
        "a11y_screen_read" to 0,
    )

    fun rank(category: String): Int = TECHNIQUE_RANK[category] ?: -1

    /**
     * Score a capability profile → (category, confidence), or null if nothing
     * takeover-shaped is declared.
     *
     * confidence scales with the number of confluent takeover techniques:
     *   1 technique   → "medium" (a single scary capability; often benign)
     *   2+ techniques → "high"   (the confluence real trojans exhibit)
     * A store/system install is far more likely a legitimate tool, so it
     * downgrades one step (high→medium, medium→low) — the same rule as the
     * offline scorer's `src` downgrade.
     */
    fun classify(p: CapabilityProfile): Pair<String, String>? {
        val techniques = p.techniques()
        if (techniques.isEmpty()) return null
        val category = techniques.maxByOrNull { rank(it) } ?: return null
        var confidence = if (techniques.size >= 2) "high" else "medium"
        if (p.fromStoreOrSystem) {
            confidence = if (confidence == "high") "medium" else "low"
        }
        return category to confidence
    }
}
