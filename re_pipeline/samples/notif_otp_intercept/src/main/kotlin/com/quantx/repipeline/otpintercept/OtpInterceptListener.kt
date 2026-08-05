package com.quantx.repipeline.otpintercept

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.regex.Pattern

/**
 * TTP reproduction: read and dismiss OTP-shaped notifications via
 * NotificationListenerService — the interception step banking trojans use to
 * complete a takeover after auto-tapping through a transfer flow.
 *
 * Ground truth (ttp.json): matches notification text against a generic
 * "N-digit code" pattern (never a real bank's format), logs only the boolean
 * "otp_pattern_matched" locally, and cancels the notification. Deliberately
 * never logs the matched digits themselves, extending the project's own
 * facet-bucketing discipline to the sample's own local logging.
 */
class OtpInterceptListener : NotificationListenerService() {

    private val otpPattern = Pattern.compile("\\b\\d{4,8}\\b")

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val text = sbn.notification.extras
            .getCharSequence("android.text")?.toString().orEmpty()
        if (otpPattern.matcher(text).find()) {
            Log.d(TAG, "otp_pattern_matched=true (digits not logged)")
            cancelNotification(sbn.key)
        }
    }

    companion object {
        private const val TAG = "OtpInterceptListener"
    }
}
