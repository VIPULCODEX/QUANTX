package com.quantx.cyber_intel_app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import android.provider.Settings
import java.io.ByteArrayInputStream
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

/**
 * Tier 0 detector — runtime self-protection plus device posture.
 *
 * Everything here works on a stock, unrooted device with no special permission
 * and no setup. That constraint is what makes Tier 0 the tier that actually
 * ships to every user.
 *
 * Output is a list of finding maps whose `code` values match the server-side
 * registry in cybersecurity_friend/findings.py. The Dart layer forwards ONLY
 * those codes and their bucketed facets; the `evidence` field stays on device
 * for display and is never transmitted.
 *
 * HONEST LIMITS — these checks raise the cost of an attack, they do not stop a
 * determined one:
 *   * Frida can hook the very functions doing the Frida detection.
 *   * A repackaged APK can have these checks patched out entirely.
 *   * Detection is strongest against commodity malware and automated tooling,
 *     which is the overwhelming majority of what reaches real users.
 * Play Integrity is the only signal here that an on-device attacker cannot
 * forge, because it is attested by Google off-device — it is not wired up yet
 * (it needs a Google Cloud project), so its absence is reported rather than
 * silently treated as a pass.
 */
object SecurityScanner {

    // Substrings that appear in /proc/self/maps when an instrumentation
    // framework has injected itself into this process.
    private val HOOK_SIGNATURES = mapOf(
        "frida" to "frida",
        "gum-js-loop" to "frida",
        "gmain" to "frida",
        "linjector" to "frida",
        "xposedbridge" to "xposed",
        "libxposed" to "xposed",
        "edxposed" to "xposed",
        "lspd" to "lsposed",
        "riru" to "lsposed",
        "zygisk" to "lsposed"
    )

    private val FRIDA_PORTS = intArrayOf(27042, 27043)

    private val SU_PATHS = arrayOf(
        "/sbin/su", "/system/bin/su", "/system/xbin/su",
        "/data/local/xbin/su", "/data/local/bin/su", "/system/sd/xbin/su",
        "/system/bin/failsafe/su", "/data/local/su", "/su/bin/su"
    )

    private val MAGISK_PATHS = arrayOf(
        "/data/adb/magisk", "/data/adb/modules", "/sbin/.magisk", "/cache/.disable_magisk"
    )

    fun scan(ctx: Context): List<Map<String, Any?>> {
        val findings = mutableListOf<Map<String, Any?>>()

        detectHooks()?.let { findings.add(it) }
        detectDebugger()?.let { findings.add(it) }
        detectSignature(ctx)?.let { findings.add(it) }
        detectEmulator()?.let { findings.add(it) }
        detectRoot()?.let { findings.add(it) }
        detectDevOptions(ctx)?.let { findings.add(it) }
        detectAccessibility(ctx)?.let { findings.add(it) }
        detectNotificationListeners(ctx)?.let { findings.add(it) }

        return findings
    }

    private fun finding(
        code: String,
        facets: Map<String, Any?> = emptyMap(),
        evidence: List<String> = emptyList()
    ) = mapOf(
        "code" to code,
        "facets" to facets,
        // Stays on device. Shown in the UI so the user can act; never sent.
        "evidence" to evidence
    )

    // ── Injection / hooking ──────────────────────────────────────────────────
    /**
     * Read our own memory map and look for injected agents.
     *
     * /proc/self/maps is always readable for the calling process — no
     * permission, no root. Other processes are not visible, which is precisely
     * why cross-app detection needs Tier 2.
     */
    private fun detectHooks(): Map<String, Any?>? {
        val hits = linkedSetOf<String>()
        var framework = "unknown"

        try {
            File("/proc/self/maps").forEachLine { line ->
                val lower = line.lowercase()
                for ((needle, fw) in HOOK_SIGNATURES) {
                    if (lower.contains(needle)) {
                        hits.add(needle)
                        framework = fw
                    }
                }
            }
        } catch (_: Exception) {
            // Unreadable maps is itself unusual, but not evidence on its own.
        }

        // Frida's default control port. A listening socket here means a server
        // is running even if nothing has been injected into us yet.
        for (port in FRIDA_PORTS) {
            try {
                Socket().use { s ->
                    s.connect(InetSocketAddress("127.0.0.1", port), 180)
                    hits.add("port:$port")
                    framework = "frida"
                }
            } catch (_: Exception) {
                // Connection refused is the healthy case.
            }
        }

        if (File("/data/local/tmp/re.frida.server").exists()) {
            hits.add("frida-server binary")
            framework = "frida"
        }

        return if (hits.isEmpty()) null
        else finding("SELF_HOOK_DETECTED", mapOf("framework" to framework), hits.toList())
    }

    // ── Debugger ─────────────────────────────────────────────────────────────
    private fun detectDebugger(): Map<String, Any?>? {
        val evidence = mutableListOf<String>()

        if (Debug.isDebuggerConnected()) evidence.add("JDWP debugger attached")

        // A process may have only one tracer. Non-zero TracerPid means
        // something is already ptrace-attached to us.
        try {
            File("/proc/self/status").forEachLine { line ->
                if (line.startsWith("TracerPid:")) {
                    val pid = line.substringAfter(':').trim().toIntOrNull() ?: 0
                    if (pid != 0) evidence.add("TracerPid=$pid")
                }
            }
        } catch (_: Exception) {
        }

        return if (evidence.isEmpty()) null
        else finding("SELF_DEBUGGER_ATTACHED", evidence = evidence)
    }

    // ── Signature / repackaging ──────────────────────────────────────────────
    /**
     * Verify who signed this build.
     *
     * We cannot pin a release fingerprint yet because CI signs with the debug
     * key. What IS reliably detectable is the debug certificate itself, whose
     * subject is always "CN=Android Debug, O=Android, C=US". A debug-signed
     * build in a user's hands is a real finding: anyone can produce one, so the
     * signature proves nothing about origin.
     */
    @Suppress("DEPRECATION")
    private fun detectSignature(ctx: Context): Map<String, Any?>? {
        try {
            val pm = ctx.packageManager
            val sigBytes: ByteArray = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val info = pm.getPackageInfo(
                    ctx.packageName, PackageManager.GET_SIGNING_CERTIFICATES
                )
                info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
                    ?: return null
            } else {
                val info = pm.getPackageInfo(ctx.packageName, PackageManager.GET_SIGNATURES)
                info.signatures?.firstOrNull()?.toByteArray() ?: return null
            }

            val cert = CertificateFactory.getInstance("X.509")
                .generateCertificate(ByteArrayInputStream(sigBytes)) as X509Certificate
            val subject = cert.subjectDN.name ?: ""
            val sha = MessageDigest.getInstance("SHA-256").digest(sigBytes)
                .joinToString(":") { "%02X".format(it) }

            if (subject.contains("Android Debug", ignoreCase = true)) {
                return finding(
                    "SELF_SIGNATURE_MISMATCH",
                    evidence = listOf(
                        "Signed with the Android debug key",
                        "Subject: $subject",
                        "SHA-256: ${sha.take(47)}…"
                    )
                )
            }
        } catch (_: Exception) {
            // A signature that cannot be read at all is not proof of tampering.
        }
        return null
    }

    // ── Environment ──────────────────────────────────────────────────────────
    private fun detectEmulator(): Map<String, Any?>? {
        val evidence = mutableListOf<String>()
        val fp = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val hw = Build.HARDWARE.lowercase()

        if (fp.startsWith("generic") || fp.contains("vbox") || fp.contains("test-keys")) {
            evidence.add("fingerprint: ${Build.FINGERPRINT.take(40)}")
        }
        if (hw == "goldfish" || hw == "ranchu" || hw.contains("vbox")) {
            evidence.add("hardware: ${Build.HARDWARE}")
        }
        if (model.contains("emulator") || model.contains("android sdk")) {
            evidence.add("model: ${Build.MODEL}")
        }

        return if (evidence.isEmpty()) null
        else finding("EMULATOR_DETECTED", evidence = evidence)
    }

    private fun detectRoot(): Map<String, Any?>? {
        val evidence = mutableListOf<String>()
        var method = "unknown"

        SU_PATHS.filter { File(it).exists() }.forEach {
            evidence.add("su binary: $it"); method = "other"
        }
        MAGISK_PATHS.filter { File(it).exists() }.forEach {
            evidence.add("magisk: $it"); method = "magisk"
        }
        if (Build.TAGS?.contains("test-keys") == true) {
            evidence.add("build signed with test-keys")
        }

        return if (evidence.isEmpty()) null
        else finding("DEVICE_ROOTED", mapOf("method" to method), evidence)
    }

    private fun detectDevOptions(ctx: Context): Map<String, Any?>? {
        val evidence = mutableListOf<String>()
        try {
            val dev = Settings.Global.getInt(
                ctx.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0
            )
            val adb = Settings.Global.getInt(
                ctx.contentResolver, Settings.Global.ADB_ENABLED, 0
            )
            if (dev != 0) evidence.add("Developer options enabled")
            if (adb != 0) evidence.add("USB debugging enabled")
        } catch (_: Exception) {
        }

        return if (evidence.isEmpty()) null
        else finding("DEV_OPTIONS_ENABLED", evidence = evidence)
    }

    // ── Accessibility & notification access ──────────────────────────────────
    /**
     * The highest-value check in Tier 0.
     *
     * Accessibility access lets an app read every screen and tap on the user's
     * behalf. Essentially every Android banking trojan — Anatsa, Octo,
     * Cerberus, TeaBot, Xenomorph — pivots through it. ENABLED_ACCESSIBILITY_-
     * SERVICES is readable with no permission whatsoever.
     *
     * Our own scanner service is excluded: flagging ourselves would be noise.
     * Preinstalled system services are excluded too — the signal is
     * *user-installed* apps holding this access.
     */
    private fun detectAccessibility(ctx: Context): Map<String, Any?>? =
        enumerateSecureSetting(
            ctx,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            "A11Y_UNTRUSTED_SERVICE"
        )

    private fun detectNotificationListeners(ctx: Context): Map<String, Any?>? =
        enumerateSecureSetting(
            ctx,
            "enabled_notification_listeners",
            "NOTIF_LISTENER_UNTRUSTED"
        )

    private fun enumerateSecureSetting(
        ctx: Context,
        key: String,
        code: String
    ): Map<String, Any?>? {
        val raw = try {
            Settings.Secure.getString(ctx.contentResolver, key)
        } catch (_: Exception) {
            null
        } ?: return null
        if (raw.isBlank()) return null

        val pm = ctx.packageManager
        val flagged = mutableListOf<String>()
        var sawSideload = false

        for (entry in raw.split(':')) {
            val pkg = entry.substringBefore('/').trim()
            if (pkg.isEmpty() || pkg == ctx.packageName) continue

            val appInfo = try {
                pm.getApplicationInfo(pkg, 0)
            } catch (_: Exception) {
                null
            }
            // Preinstalled system components are expected to hold this.
            val isSystem = appInfo != null &&
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem) continue

            val label = appInfo?.let { pm.getApplicationLabel(it).toString() } ?: pkg
            val installer = installerOf(ctx, pkg)
            if (installer == null || !installer.contains("com.android.vending")) {
                sawSideload = true
            }
            flagged.add("$label  ($pkg)")
        }

        if (flagged.isEmpty()) return null
        return finding(
            code,
            mapOf(
                "count" to flagged.size,
                "src" to if (sawSideload) "unknown" else "play"
            ),
            flagged
        )
    }

    @Suppress("DEPRECATION")
    private fun installerOf(ctx: Context, pkg: String): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ctx.packageManager.getInstallSourceInfo(pkg).installingPackageName
        } else {
            ctx.packageManager.getInstallerPackageName(pkg)
        }
    } catch (_: Exception) {
        null
    }
}
