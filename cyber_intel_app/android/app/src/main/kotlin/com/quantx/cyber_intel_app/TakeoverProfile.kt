package com.quantx.cyber_intel_app

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager

/**
 * Mode 1 — static capability-profile detection (Tier 0, zero permission).
 *
 * The non-rooted, always-on posture check. It reads the *declared* capability
 * profile of each enabled accessibility service — the same fields the offline
 * pipeline scores in re_pipeline/capability_profile.py — and flags a service
 * whose capabilities match a known account-takeover technique.
 *
 * This is a POSTURE signal: "an installed app is equipped for takeover." It
 * cannot say the attack is happening (that is Mode 2, LiveAttackObserver), and
 * it false-positives on legitimate accessibility tools (a screen reader, a
 * password manager) that request the same capabilities — which is why the
 * confidence scales with the CONFLUENCE of several takeover capabilities in one
 * package, and why the installer source downgrades a store/system match. A
 * single capability alone is only ever "medium".
 *
 * Emits A11Y_TAKEOVER_PROFILE with {category, confidence}. Category values are
 * the closed taxonomy shared with the server registry
 * (cybersecurity_friend/findings.py, _BEHAVIOR_CATEGORY).
 */
object TakeoverProfile {

    private data class Profile(
        val label: String,
        val pkg: String,
        val canRetrieveWindowContent: Boolean,
        val canPerformGestures: Boolean,
        val hasNotificationListener: Boolean,
        val requestsOverlay: Boolean,
        val fromStoreOrSystem: Boolean
    ) {
        /** Distinct takeover techniques this profile enables, as taxonomy labels. */
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

    // Worst technique first, for choosing the dominant reported category.
    private val TECHNIQUE_RANK = mapOf(
        "a11y_auto_tap" to 3,
        "overlay_phish" to 2,
        "notif_intercept" to 1,
        "a11y_screen_read" to 0
    )

    /** Score a profile → (category, confidence), or null if nothing takeover-shaped. */
    private fun classify(p: Profile): Pair<String, String>? {
        val techniques = p.techniques()
        if (techniques.isEmpty()) return null
        val category = techniques.maxByOrNull { TECHNIQUE_RANK[it] ?: -1 } ?: return null
        var confidence = if (techniques.size >= 2) "high" else "medium"
        // A store/system-installed match is far more likely a legitimate tool;
        // downgrade one step. Mirrors the offline scorer's `src` downgrade rule.
        if (p.fromStoreOrSystem) {
            confidence = when (confidence) {
                "high" -> "medium"
                else -> "low"
            }
        }
        return category to confidence
    }

    /**
     * Scan enabled accessibility services and return the single most severe
     * takeover-profile finding, or null. One finding is emitted for the worst
     * profile rather than one per app, keeping the wire payload bounded.
     */
    fun scan(ctx: Context): Map<String, Any?>? {
        val am = ctx.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager
            ?: return null
        val services = try {
            am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
        } catch (_: Exception) {
            return null
        } ?: return null

        val notifListeners = enabledNotificationListenerPackages(ctx)
        val pm = ctx.packageManager

        var best: Pair<String, String>? = null   // (category, confidence)
        var bestRank = -1
        var bestEvidence: String? = null

        for (info in services) {
            val pkg = info.resolveInfo?.serviceInfo?.packageName ?: continue
            if (pkg == ctx.packageName) continue

            val appInfo = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (_: Exception) {
                null
            }
            val isSystem = appInfo != null &&
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem) continue   // preinstalled components are expected to hold this

            val caps = info.capabilities
            val canContent =
                (caps and AccessibilityServiceInfo.CAPABILITY_CAN_RETRIEVE_WINDOW_CONTENT) != 0
            val canGestures = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                (caps and AccessibilityServiceInfo.CAPABILITY_CAN_PERFORM_GESTURES) != 0

            val profile = Profile(
                label = appInfo?.let { pm.getApplicationLabel(it).toString() } ?: pkg,
                pkg = pkg,
                canRetrieveWindowContent = canContent,
                canPerformGestures = canGestures,
                hasNotificationListener = notifListeners.contains(pkg),
                requestsOverlay = requestsOverlay(ctx, pkg),
                fromStoreOrSystem = isStoreInstalled(ctx, pkg)
            )

            val result = classify(profile) ?: continue
            val (category, _) = result
            val rank = TECHNIQUE_RANK[category] ?: -1
            if (rank > bestRank) {
                bestRank = rank
                best = result
                bestEvidence = "${profile.label}  (${profile.pkg}) → " +
                    profile.techniques().joinToString(", ")
            }
        }

        val (category, confidence) = best ?: return null
        return mapOf(
            "code" to "A11Y_TAKEOVER_PROFILE",
            "facets" to mapOf("category" to category, "confidence" to confidence),
            "evidence" to listOfNotNull(bestEvidence)
        )
    }

    private fun enabledNotificationListenerPackages(ctx: Context): Set<String> {
        val raw = try {
            Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners")
        } catch (_: Exception) {
            null
        } ?: return emptySet()
        return raw.split(':')
            .mapNotNull { it.substringBefore('/').trim().takeIf(String::isNotEmpty) }
            .toSet()
    }

    private fun requestsOverlay(ctx: Context, pkg: String): Boolean = try {
        val info = ctx.packageManager.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
        info.requestedPermissions?.any {
            it == android.Manifest.permission.SYSTEM_ALERT_WINDOW
        } ?: false
    } catch (_: Exception) {
        false
    }

    @Suppress("DEPRECATION")
    private fun isStoreInstalled(ctx: Context, pkg: String): Boolean {
        val installer = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                ctx.packageManager.getInstallSourceInfo(pkg).installingPackageName
            } else {
                ctx.packageManager.getInstallerPackageName(pkg)
            }
        } catch (_: Exception) {
            null
        }
        return installer != null && installer.contains("com.android.vending")
    }
}
