package com.quantx.cyber_intel_app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure JVM tests for the Live Attack Observer's automation scorer. */
class AutomationScoringTest {

    private fun at(vararg intervals: Long): List<Long> {
        val out = ArrayList<Long>()
        var t = 0L
        out.add(t)
        for (i in intervals) {
            t += i
            out.add(t)
        }
        return out
    }

    @Test
    fun fastRegularRunIsHighConfidence() {
        val r = AutomationScoring.score(at(50, 50, 50, 50, 50))
        assertNotNull(r)
        assertEquals("high", r!!.confidence)
        assertEquals(50L, r.medianMs)
        assertEquals(0.0, r.cov, 1e-9)
        assertEquals(6, r.events)
    }

    @Test
    fun moderatelyFastRegularRunIsMediumConfidence() {
        val r = AutomationScoring.score(at(100, 100, 100, 100))
        assertEquals("medium", r!!.confidence)
        assertEquals(100L, r.medianMs)
    }

    @Test
    fun alternatingFastIntervalsWithLowVarianceAreHigh() {
        // intervals 40,60,40,60 -> median 50, mean 50, sd 10, cov 0.2
        val r = AutomationScoring.score(at(40, 60, 40, 60))
        assertEquals("high", r!!.confidence)
        assertEquals(50L, r.medianMs)
        assertEquals(0.2, r.cov, 1e-9)
    }

    @Test
    fun fastButIrregularRunIsOnlyMedium() {
        // intervals 10,110,20,100,15 -> median 20 but cov ~0.87
        val r = AutomationScoring.score(at(10, 110, 20, 100, 15))
        assertEquals("medium", r!!.confidence)
        assertEquals(20L, r.medianMs)
        assertTrue(r.cov > AutomationScoring.LOW_COV)
    }

    @Test
    fun humanPacedRunIsNotReported() {
        assertNull(AutomationScoring.score(at(300, 350, 250, 400)))
    }

    @Test
    fun medianBoundaryIsInclusiveAt120() {
        assertNotNull(AutomationScoring.score(at(120, 120, 120, 120)))
        assertNull(AutomationScoring.score(at(121, 121, 121, 121)))
    }

    @Test
    fun tooFewEventsAreNotReported() {
        assertNull(AutomationScoring.score(listOf(0L, 10L, 20L, 30L)))   // 4 events
        assertNull(AutomationScoring.score(emptyList()))
    }

    @Test
    fun medianOfOddAndEvenLengths() {
        assertEquals(5L, AutomationScoring.medianOf(listOf(5L)))
        assertEquals(2L, AutomationScoring.medianOf(listOf(3L, 1L, 2L)))
        assertEquals(2L, AutomationScoring.medianOf(listOf(1L, 2L, 3L, 4L)))   // (2+3)/2 in integers
    }

    @Test
    fun coefficientOfVariationEdgeCases() {
        assertEquals(0.0, AutomationScoring.coefficientOfVariation(listOf(10L, 10L, 10L)), 1e-9)
        assertEquals(0.5, AutomationScoring.coefficientOfVariation(listOf(10L, 30L)), 1e-9)
        assertEquals(1.0, AutomationScoring.coefficientOfVariation(listOf(10L)), 1e-9)
        assertEquals(1.0, AutomationScoring.coefficientOfVariation(listOf(0L, 0L)), 1e-9)
    }

    @Test
    fun targetClassUsesPackageHintsAndNeverNull() {
        assertEquals("financial", AutomationScoring.classifyTarget("com.paytm.app"))
        assertEquals("financial", AutomationScoring.classifyTarget("COM.MyBank.App"))
        assertEquals("other", AutomationScoring.classifyTarget("com.games.fun"))
        assertEquals("other", AutomationScoring.classifyTarget(null))
    }
}
