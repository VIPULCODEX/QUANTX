package com.quantx.cyber_intel_app

import kotlin.math.sqrt

/**
 * Pure, Android-free scoring for the Live Attack Observer's automation check
 * (ported from re_pipeline/event_sequence.py's automation branch). Extracted
 * from LiveAttackObserver so it runs as a plain JVM unit test.
 */
object AutomationScoring {
    const val HUMAN_MIN_MEDIAN_MS = 120L   // sustained intervals below this are non-human
    const val HIGH_CONF_MEDIAN_MS = 60L    // and below this, with low variance, unambiguous
    const val LOW_COV = 0.35               // bots are regular: low coefficient of variation
    const val MIN_ACTION_EVENTS = 5        // need a sustained run, not one fast tap

    data class Result(
        val confidence: String,
        val medianMs: Long,
        val cov: Double,
        val events: Int
    )

    /** Score a run of action timestamps (ms), or null if nothing is reportable. */
    fun score(times: List<Long>): Result? {
        if (times.size < MIN_ACTION_EVENTS) return null
        val intervals = ArrayList<Long>(times.size - 1)
        for (i in 1 until times.size) intervals.add(times[i] - times[i - 1])
        if (intervals.isEmpty()) return null

        val median = medianOf(intervals)
        if (median > HUMAN_MIN_MEDIAN_MS) return null   // human-paced; nothing to report

        val cov = coefficientOfVariation(intervals)
        val confidence = if (median <= HIGH_CONF_MEDIAN_MS && cov <= LOW_COV) "high" else "medium"
        return Result(confidence, median, cov, times.size)
    }

    fun medianOf(values: List<Long>): Long {
        val sorted = values.sorted()
        val n = sorted.size
        return if (n % 2 == 1) sorted[n / 2]
        else (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    fun coefficientOfVariation(values: List<Long>): Double {
        if (values.size < 2) return 1.0
        val mean = values.average()
        if (mean <= 0) return 1.0
        val variance = values.sumOf { (it - mean) * (it - mean) } / values.size
        return sqrt(variance) / mean
    }

    // Android has no ApplicationInfo finance category, so a financial target is
    // classified from package-name hints. The package name is on-device evidence
    // and NEVER leaves the device - only the bucketed class is emitted.
    private val FINANCIAL_HINTS = listOf(
        "bank", "upi", "wallet", "paytm", "phonepe", "gpay", "paypal",
        "finance", "credit", "debit", "netbank", "mobilebank"
    )

    fun classifyTarget(pkg: String?): String {
        val p = pkg?.lowercase() ?: return "other"
        return if (FINANCIAL_HINTS.any { p.contains(it) }) "financial" else "other"
    }
}
