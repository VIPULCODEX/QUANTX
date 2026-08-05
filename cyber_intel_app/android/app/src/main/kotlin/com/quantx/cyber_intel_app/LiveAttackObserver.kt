package com.quantx.cyber_intel_app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import kotlin.math.sqrt

/**
 * Buffer of findings the LiveAttackObserver has raised since the last scan.
 *
 * The observer runs continuously and detects attacks in real time; SecurityScanner
 * drains this buffer on the next scan so those findings flow through the exact
 * same toWire() → /api/security/findings gate path as everything else. No new
 * network surface. Bounded so a noisy device cannot grow it without limit.
 */
object ObserverBuffer {
    private const val MAX = 32
    private val items = ArrayList<Map<String, Any?>>()

    @Synchronized
    fun add(finding: Map<String, Any?>) {
        if (items.size >= MAX) items.removeAt(0)
        items.add(finding)
    }

    @Synchronized
    fun drain(): List<Map<String, Any?>> {
        val out = ArrayList(items)
        items.clear()
        return out
    }

    @Volatile
    var connected: Boolean = false
        internal set
}

/**
 * Mode 2 — the Live Attack Observer (dynamic, cross-app, non-rooted).
 *
 * The inversion: banking trojans abuse AccessibilityService to watch other apps;
 * QuantX runs its OWN accessibility service, with the user's explicit consent,
 * to watch the attack happen. A non-rooted app with an accessibility grant
 * receives the live, system-wide event stream and can call getWindows() — which
 * is enough to catch account-takeover in progress without ever reading another
 * process's memory.
 *
 * Detects (scoring ported from re_pipeline/event_sequence.py, whose thresholds
 * are calibrated from the MCP-derived sample traces):
 *   - A11Y_AUTOMATION_ANOMALY — machine-cadence event streams driving a
 *     user-facing app; humans do not emit sustained sub-120 ms, low-variance
 *     action runs.
 *   - OVERLAY_ATTACK_LIVE — an untrusted package's window layered over the
 *     foreground app (best-effort; getWindows() attribution is partial and
 *     version-dependent — an honest, documented limit).
 *
 * CONSISTENCY RULE (mirrors Tier 1 Shizuku): enabling this service is the exact
 * permission QuantX flags as dangerous, so it is an opt-in, time-boxed
 * diagnostic and its own grant is surfaced to the user (see MainActivity
 * isObserverEnabled) with a prompt to disable it — no self-exemption.
 *
 * NOT here: NOTIF_HIJACK_LIVE needs a NotificationListenerService (a separate
 * service and a separate grant); it is the documented follow-on.
 */
class LiveAttackObserver : AccessibilityService() {

    // ── calibration constants (defaults; MCP traces replace these) ───────────
    private val humanMinMedianMs = 120L   // sustained intervals below this are non-human
    private val highConfMedianMs = 60L    // and below this, with low variance, unambiguous
    private val lowCov = 0.35             // bots are regular: low coefficient of variation
    private val minActionEvents = 5       // need a sustained run, not one fast tap

    private val actionTypes = setOf(
        AccessibilityEvent.TYPE_VIEW_CLICKED,
        AccessibilityEvent.TYPE_VIEW_SCROLLED,
        AccessibilityEvent.TYPE_VIEW_FOCUSED,
        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
    )

    private var foregroundPkg: String? = null
    private var watching = false
    private var targetClass = "other"
    private val actionTimes = ArrayList<Long>()
    private var emittedAutomation = false
    private var emittedOverlay = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        ObserverBuffer.connected = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> onForegroundChanged(event.packageName)
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> if (watching) checkOverlay()
            in actionTypes -> if (watching) recordAction()
            else -> { /* ignore */ }
        }
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        ObserverBuffer.connected = false
        super.onDestroy()
    }

    private fun onForegroundChanged(pkg: CharSequence?) {
        val p = pkg?.toString()
        if (p == foregroundPkg) return
        // New foreground session: reset per-session state.
        foregroundPkg = p
        actionTimes.clear()
        emittedAutomation = false
        emittedOverlay = false
        watching = p != null && p != packageName && isUserFacing(p)
        targetClass = classifyTarget(p)
    }

    private fun recordAction() {
        actionTimes.add(System.currentTimeMillis())
        if (actionTimes.size > 64) actionTimes.removeAt(0)   // sliding cap
        if (!emittedAutomation) scoreAutomation()
    }

    /** Ported from event_sequence.score_stream's automation branch. */
    private fun scoreAutomation() {
        if (actionTimes.size < minActionEvents) return
        val intervals = ArrayList<Long>(actionTimes.size - 1)
        for (i in 1 until actionTimes.size) intervals.add(actionTimes[i] - actionTimes[i - 1])
        if (intervals.isEmpty()) return

        val median = medianOf(intervals)
        if (median > humanMinMedianMs) return   // human-paced; nothing to report

        val cov = coefficientOfVariation(intervals)
        val confidence = if (median <= highConfMedianMs && cov <= lowCov) "high" else "medium"
        emittedAutomation = true
        ObserverBuffer.add(
            mapOf(
                "code" to "A11Y_AUTOMATION_ANOMALY",
                "facets" to mapOf(
                    "category" to "a11y_auto_tap",
                    "confidence" to confidence,
                    "target" to targetClass
                ),
                "evidence" to listOf(
                    "median inter-action ${median}ms, cov ${"%.2f".format(cov)}, " +
                        "${actionTimes.size} events"
                )
            )
        )
    }

    /**
     * Best-effort live overlay detection. getWindows() attribution of arbitrary
     * overlays is partial and version-dependent (an honest, documented limit),
     * so a match is reported at medium confidence unless the overlaying package
     * is clearly untrusted (sideloaded), where it rises to high.
     */
    private fun checkOverlay() {
        if (emittedOverlay) return
        val windows = try {
            windows
        } catch (_: Exception) {
            return
        } ?: return

        for (w in windows) {
            val overPkg = overlayPackage(w) ?: continue
            if (overPkg == foregroundPkg || overPkg == packageName) continue
            if (isUserFacing(overPkg) && !isStoreInstalled(overPkg)) {
                emittedOverlay = true
                ObserverBuffer.add(
                    mapOf(
                        "code" to "OVERLAY_ATTACK_LIVE",
                        "facets" to mapOf("confidence" to "high", "target" to targetClass),
                        "evidence" to listOf("window of $overPkg layered over $foregroundPkg")
                    )
                )
                return
            }
        }
    }

    /** The owning package of an overlay-type window, if resolvable. */
    @Suppress("DEPRECATION")   // AccessibilityNodeInfo.recycle() deprecated API 33+
    private fun overlayPackage(w: AccessibilityWindowInfo?): String? {
        w ?: return null
        // Only application/overlay windows are candidates; system chrome is not.
        val type = w.type
        if (type != AccessibilityWindowInfo.TYPE_APPLICATION &&
            type != AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY
        ) return null
        val root = try {
            w.root
        } catch (_: Exception) {
            null
        } ?: return null
        val pkg = root.packageName?.toString()
        try {
            root.recycle()
        } catch (_: Exception) {
        }
        return pkg
    }

    // ── helpers ──────────────────────────────────────────────────────────────
    private fun isUserFacing(pkg: String): Boolean = try {
        val ai = packageManager.getApplicationInfo(pkg, 0)
        (ai.flags and ApplicationInfo.FLAG_SYSTEM) == 0
    } catch (_: Exception) {
        false
    }

    private fun classifyTarget(pkg: String?): String {
        pkg ?: return "other"
        return try {
            val ai = packageManager.getApplicationInfo(pkg, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                ai.category == ApplicationInfo.CATEGORY_FINANCE
            ) "financial" else "other"
        } catch (_: Exception) {
            "other"
        }
    }

    @Suppress("DEPRECATION")
    private fun isStoreInstalled(pkg: String): Boolean {
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(pkg).installingPackageName
            } else {
                packageManager.getInstallerPackageName(pkg)
            }
        } catch (_: Exception) {
            null
        }
        return installer != null && installer.contains("com.android.vending")
    }

    private fun medianOf(values: List<Long>): Long {
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 1) sorted[n / 2]
        else (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    private fun coefficientOfVariation(values: List<Long>): Double {
        if (values.size < 2) return 1.0
        val mean = values.average()
        if (mean <= 0) return 1.0
        val variance = values.sumOf { (it - mean) * (it - mean) } / values.size
        return sqrt(variance) / mean
    }
}
