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

    // Pure scoring lives in TakeoverScoring (Android-free, unit-tested). This
    // object only reads the capability fields off the device and hands them over.

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

            val profile = CapabilityProfile(
                canRetrieveWindowContent = canContent,
                canPerformGestures = canGestures,
                hasNotificationListener = notifListeners.contains(pkg),
                requestsOverlay = requestsOverlay(ctx, pkg),
                fromStoreOrSystem = isStoreInstalled(ctx, pkg)
            )

            val result = TakeoverScoring.classify(profile) ?: continue
            val (category, _) = result
            val rank = TakeoverScoring.rank(category)
            if (rank > bestRank) {
                bestRank = rank
                best = result
                val label = appInfo?.let { pm.getApplicationLabel(it).toString() } ?: pkg
                bestEvidence = "$label  ($pkg) → " + profile.techniques().joinToString(", ")
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
