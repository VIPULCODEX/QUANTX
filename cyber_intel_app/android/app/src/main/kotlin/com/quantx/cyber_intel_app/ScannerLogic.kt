package com.quantx.cyber_intel_app

/**
 * Pure, Android-free decision logic extracted from SecurityScanner so it runs
 * as a plain JVM unit test. SecurityScanner still performs the I/O (reading
 * /proc, querying PackageManager, reading Build fields) and hands the raw
 * strings here.
 */
object ScannerLogic {

    // Substrings that appear in /proc/self/maps when an instrumentation
    // framework has injected itself into this process.
    val HOOK_SIGNATURES = mapOf(
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

    data class HookScan(val hits: Set<String>, val framework: String)

    /** Scan memory-map lines for injected-agent signatures (case-insensitive). */
    fun scanMapsLines(lines: Sequence<String>): HookScan {
        val hits = linkedSetOf<String>()
        var framework = "unknown"
        for (line in lines) {
            val lower = line.lowercase()
            for ((needle, fw) in HOOK_SIGNATURES) {
                if (lower.contains(needle)) {
                    hits.add(needle)
                    framework = fw
                }
            }
        }
        return HookScan(hits, framework)
    }

    /**
     * Value of a "TracerPid:" line in /proc/self/status, or null if the line is
     * something else. An unparseable value counts as 0 (no tracer).
     */
    fun tracerPid(line: String): Int? {
        if (!line.startsWith("TracerPid:")) return null
        return line.substringAfter(':').trim().toIntOrNull() ?: 0
    }

    fun emulatorEvidence(fingerprint: String, model: String, hardware: String): List<String> {
        val evidence = mutableListOf<String>()
        val fp = fingerprint.lowercase()
        val m = model.lowercase()
        val hw = hardware.lowercase()

        if (fp.startsWith("generic") || fp.contains("vbox") || fp.contains("test-keys")) {
            evidence.add("fingerprint: ${fingerprint.take(40)}")
        }
        if (hw == "goldfish" || hw == "ranchu" || hw.contains("vbox")) {
            evidence.add("hardware: $hardware")
        }
        if (m.contains("emulator") || m.contains("android sdk")) {
            evidence.add("model: $model")
        }
        return evidence
    }

    data class RootScan(val method: String, val evidence: List<String>)

    /** Combine what the filesystem probes found into a root verdict, or null. */
    fun classifyRoot(
        suFound: List<String>,
        magiskFound: List<String>,
        testKeys: Boolean
    ): RootScan? {
        val evidence = mutableListOf<String>()
        suFound.forEach { evidence.add("su binary: $it") }
        magiskFound.forEach { evidence.add("magisk: $it") }
        if (testKeys) evidence.add("build signed with test-keys")
        if (evidence.isEmpty()) return null
        val method = when {
            magiskFound.isNotEmpty() -> "magisk"
            suFound.isNotEmpty() -> "other"
            else -> "unknown"
        }
        return RootScan(method, evidence)
    }

    /**
     * Package names from an ENABLED_ACCESSIBILITY_SERVICES-style value
     * ("pkg/Class:pkg2/Class2"), excluding blanks and this app's own package.
     * A package holding two services appears twice, as before the extraction.
     */
    fun servicePackages(raw: String, ownPackage: String): List<String> =
        raw.split(':')
            .map { it.substringBefore('/').trim() }
            .filter { it.isNotEmpty() && it != ownPackage }

    fun isStoreInstaller(installer: String?): Boolean =
        installer != null && installer.contains("com.android.vending")

    fun srcFacet(sawSideload: Boolean): String = if (sawSideload) "unknown" else "play"

    fun isDebugSignature(subject: String): Boolean =
        subject.contains("Android Debug", ignoreCase = true)
}
