package com.quantx.cyber_intel_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for the Mode 1 (no-permission) takeover-capability scorer.
 *
 * Pure JVM tests — no emulator, no device. They mirror the validated cases in
 * re_pipeline/capability_profile.py so the shipped on-device classifier and the
 * offline research scorer cannot silently diverge. This is the first automated
 * coverage of the Kotlin detector, whose absence CLAUDE.md flags as open.
 */
class TakeoverScoringTest {

    @Test
    fun benignProfileProducesNoFinding() {
        // No takeover-shaped capability at all → nothing is emitted.
        assertNull(TakeoverScoring.classify(CapabilityProfile()))
    }

    @Test
    fun singleContentCapabilityIsScreenReadMedium() {
        val r = TakeoverScoring.classify(
            CapabilityProfile(canRetrieveWindowContent = true)
        )
        assertEquals("a11y_screen_read" to "medium", r)
    }

    @Test
    fun gesturesPlusContentIsAutoTap() {
        val r = TakeoverScoring.classify(
            CapabilityProfile(canRetrieveWindowContent = true, canPerformGestures = true)
        )
        assertEquals("a11y_auto_tap" to "medium", r)
    }

    @Test
    fun confluenceOfTechniquesIsHigh() {
        // The shape a real trojan exhibits: reads screen, taps, overlays, reads notifs.
        val r = TakeoverScoring.classify(
            CapabilityProfile(
                canRetrieveWindowContent = true,
                canPerformGestures = true,
                hasNotificationListener = true,
                requestsOverlay = true
            )
        )
        assertEquals("a11y_auto_tap" to "high", r)
    }

    @Test
    fun dominantCategoryIsWorstTechnique() {
        // Overlay outranks notification interception when both are present.
        val r = TakeoverScoring.classify(
            CapabilityProfile(requestsOverlay = true, hasNotificationListener = true)
        )
        assertEquals("overlay_phish" to "high", r)
    }

    @Test
    fun storeInstallDowngradesConfidence() {
        // A confluence that would be "high" drops to "medium" when store-installed…
        val high = TakeoverScoring.classify(
            CapabilityProfile(
                canRetrieveWindowContent = true,
                canPerformGestures = true,
                hasNotificationListener = true,
                fromStoreOrSystem = true
            )
        )
        assertEquals("a11y_auto_tap" to "medium", high)

        // …and a single-capability "medium" drops to "low".
        val medium = TakeoverScoring.classify(
            CapabilityProfile(canRetrieveWindowContent = true, fromStoreOrSystem = true)
        )
        assertEquals("a11y_screen_read" to "low", medium)
    }
}
