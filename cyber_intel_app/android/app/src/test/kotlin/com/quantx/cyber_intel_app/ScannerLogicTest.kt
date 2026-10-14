package com.quantx.cyber_intel_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure JVM tests for the decision logic behind the Tier 0 scanner. */
class ScannerLogicTest {

    // ── hook signatures in /proc/self/maps ───────────────────────────────────
    @Test
    fun cleanMapsProduceNoHits() {
        val lines = sequenceOf(
            "7f00-7f10 r-xp 00000000 fd:00 1 /system/lib64/libandroid_runtime.so",
            "7f20-7f30 r--p 00000000 fd:00 2 /apex/com.android.runtime/lib64/bionic/libc.so"
        )
        val r = ScannerLogic.scanMapsLines(lines)
        assertTrue(r.hits.isEmpty())
        assertEquals("unknown", r.framework)
    }

    @Test
    fun fridaAgentIsDetectedCaseInsensitively() {
        val r = ScannerLogic.scanMapsLines(
            sequenceOf("7f00-7f10 r-xp 0 fd:00 1 /data/local/tmp/FRIDA-agent-64.so")
        )
        assertTrue(r.hits.contains("frida"))
        assertEquals("frida", r.framework)
    }

    @Test
    fun xposedAndLsposedAreDistinguished() {
        assertEquals(
            "xposed",
            ScannerLogic.scanMapsLines(sequenceOf("... /data/app/x/libxposed_art.so")).framework
        )
        assertEquals(
            "lsposed",
            ScannerLogic.scanMapsLines(sequenceOf("... /data/adb/lspd/liblspd.so")).framework
        )
    }

    @Test
    fun lastMatchingFrameworkWinsAndAllHitsAreKept() {
        val r = ScannerLogic.scanMapsLines(
            sequenceOf("... /tmp/frida-agent.so", "... /data/app/x/libxposed_art.so")
        )
        assertEquals("xposed", r.framework)
        assertTrue(r.hits.contains("frida") && r.hits.contains("libxposed"))
    }

    // ── TracerPid ────────────────────────────────────────────────────────────
    @Test
    fun tracerPidParsing() {
        assertEquals(0, ScannerLogic.tracerPid("TracerPid:\t0"))
        assertEquals(1234, ScannerLogic.tracerPid("TracerPid:\t1234"))
        assertEquals(0, ScannerLogic.tracerPid("TracerPid:\tgarbage"))
        assertNull(ScannerLogic.tracerPid("Pid:\t5"))
        assertNull(ScannerLogic.tracerPid("tracerpid:5"))
    }

    // ── emulator ─────────────────────────────────────────────────────────────
    @Test
    fun realPhoneHasNoEmulatorEvidence() {
        assertTrue(
            ScannerLogic.emulatorEvidence(
                "google/oriole/oriole:14/UP1A.231005.007/1:user/release-keys", "Pixel 6", "oriole"
            ).isEmpty()
        )
    }

    @Test
    fun emulatorFingerprintAndHardwareAreReported() {
        val ev = ScannerLogic.emulatorEvidence(
            "generic/sdk_gphone64_x86_64/emu64xa:14/UE1A/1:userdebug/dev-keys",
            "sdk_gphone64_x86_64",
            "ranchu"
        )
        assertEquals(2, ev.size)
        assertTrue(ev[0].startsWith("fingerprint: generic"))
        assertEquals("hardware: ranchu", ev[1])
    }

    @Test
    fun emulatorModelAndLongFingerprintTruncation() {
        val ev = ScannerLogic.emulatorEvidence("generic" + "x".repeat(100), "Android SDK built for x86", "x")
        assertEquals("fingerprint: " + ("generic" + "x".repeat(100)).take(40), ev[0])
        assertEquals("model: Android SDK built for x86", ev[1])
    }

    @Test
    fun testKeysFingerprintAloneIsEvidence() {
        val ev = ScannerLogic.emulatorEvidence("brand/dev/dev:12/A/1:userdebug/test-keys", "Pixel", "dev")
        assertEquals(1, ev.size)
    }

    // ── root ─────────────────────────────────────────────────────────────────
    @Test
    fun nothingFoundIsNotRoot() {
        assertNull(ScannerLogic.classifyRoot(emptyList(), emptyList(), false))
    }

    @Test
    fun suBinaryOnlyIsOther() {
        val r = ScannerLogic.classifyRoot(listOf("/system/bin/su"), emptyList(), false)!!
        assertEquals("other", r.method)
        assertEquals(listOf("su binary: /system/bin/su"), r.evidence)
    }

    @Test
    fun magiskWinsOverSuAndEvidenceKeepsOrder() {
        val r = ScannerLogic.classifyRoot(listOf("/sbin/su"), listOf("/data/adb/magisk"), true)!!
        assertEquals("magisk", r.method)
        assertEquals(
            listOf("su binary: /sbin/su", "magisk: /data/adb/magisk", "build signed with test-keys"),
            r.evidence
        )
    }

    @Test
    fun testKeysAloneIsUnknownMethod() {
        val r = ScannerLogic.classifyRoot(emptyList(), emptyList(), true)!!
        assertEquals("unknown", r.method)
    }

    // ── accessibility / listener settings ────────────────────────────────────
    @Test
    fun servicePackagesStripsClassesBlanksAndOwnPackage() {
        val raw = "com.a11y.one/com.a11y.one.Svc:com.x.two/.Svc2: :com.me/.Mine"
        assertEquals(listOf("com.a11y.one", "com.x.two"), ScannerLogic.servicePackages(raw, "com.me"))
    }

    @Test
    fun packageWithTwoServicesCountsTwice() {
        assertEquals(listOf("p", "p"), ScannerLogic.servicePackages("p/.A:p/.B", "me"))
    }

    @Test
    fun emptyAndOnlyOwnPackageGiveNothing() {
        assertTrue(ScannerLogic.servicePackages("", "me").isEmpty())
        assertTrue(ScannerLogic.servicePackages("me/.S", "me").isEmpty())
    }

    @Test
    fun storeInstallerAndSrcFacet() {
        assertTrue(ScannerLogic.isStoreInstaller("com.android.vending"))
        assertFalse(ScannerLogic.isStoreInstaller(null))
        assertFalse(ScannerLogic.isStoreInstaller("com.google.android.packageinstaller"))
        assertEquals("unknown", ScannerLogic.srcFacet(true))
        assertEquals("play", ScannerLogic.srcFacet(false))
    }

    // ── signature ────────────────────────────────────────────────────────────
    @Test
    fun debugSignatureSubject() {
        assertTrue(ScannerLogic.isDebugSignature("CN=Android Debug, O=Android, C=US"))
        assertTrue(ScannerLogic.isDebugSignature("cn=android debug"))
        assertFalse(ScannerLogic.isDebugSignature("CN=QuantX Release, O=QuantX"))
    }
}
