package com.quantx.cyber_intel_app

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/**
 * QuantX Scanner Accessibility Service
 *
 * How it works:
 * 1. Android fires AccessibilityEvents when the user navigates in a browser.
 * 2. We walk the view tree to find the URL bar node.
 * 3. We extract the URL string and send it to the QuantX backend PhishSense API.
 * 4. If the risk score >= 60, we fire a system notification to warn the user.
 *
 * The user enables this explicitly in:
 *   Settings → Accessibility → QuantX Web Scanner → Enable
 */
class QuantXScannerService : AccessibilityService() {

    companion object {
        private const val TAG = "QuantX.Scanner"
        private const val CHANNEL_ID = "quantx_scanner_channel"
        private const val NOTIF_ID_BASE = 9000
        private const val PREFS_NAME = "quantx_scanner_prefs"
        private const val PREF_SCANNER_ON = "scanner_enabled"
        private const val PREF_BACKEND_URL = "backend_url"
        private const val RISK_THRESHOLD = 60
        // Debounce: don't re-scan the same URL within 10 seconds
        private const val DEBOUNCE_MS = 10_000L

        /** Called from Flutter via MethodChannel to toggle the scanner. */
        fun setScannerEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(PREF_SCANNER_ON, enabled).apply()
            Log.d(TAG, "Scanner toggled: $enabled")
        }

        fun isScannerEnabled(context: Context): Boolean =
            prefs(context).getBoolean(PREF_SCANNER_ON, false)

        fun setBackendUrl(context: Context, url: String) {
            prefs(context).edit().putString(PREF_BACKEND_URL, url).apply()
        }

        private fun prefs(ctx: Context): SharedPreferences =
            ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val httpClient = OkHttpClient()
    private var lastScannedUrl = ""
    private var lastScanTime = 0L

    // ──────────────────────────────────────────────────────────────────────────
    // Lifecycle
    // ──────────────────────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        createNotificationChannel()
        Log.i(TAG, "QuantX Scanner Service connected.")
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
        Log.i(TAG, "QuantX Scanner Service destroyed.")
    }

    override fun onInterrupt() {
        Log.w(TAG, "QuantX Scanner Service interrupted.")
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Core Event Handler
    // ──────────────────────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Respect the user's ON/OFF toggle
        if (!isScannerEnabled(applicationContext)) return

        val eventType = event.eventType
        if (eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val rootNode = rootInActiveWindow ?: return

        // Extract URL from the browser's address bar
        val url = extractUrlFromNode(rootNode) ?: return
        rootNode.recycle()

        // Debounce: skip if we scanned this URL recently
        val now = System.currentTimeMillis()
        if (url == lastScannedUrl && (now - lastScanTime) < DEBOUNCE_MS) return
        lastScannedUrl = url
        lastScanTime = now

        Log.d(TAG, "Scanning URL: $url")

        // Run scan in background coroutine
        serviceScope.launch {
            scanUrl(url)
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // URL Extraction — walks the accessibility view tree to find URL bar
    // ──────────────────────────────────────────────────────────────────────────

    private fun extractUrlFromNode(node: AccessibilityNodeInfo): String? {
        // Common resource-ids for URL bars across browsers
        val urlBarIds = listOf(
            "com.android.chrome:id/url_bar",
            "org.mozilla.firefox:id/mozac_browser_toolbar_url_view",
            "com.microsoft.emmx:id/url_bar",
            "com.opera.browser:id/url_field",
            "com.brave.browser:id/url_bar",
            "com.duckduckgo.mobile.android:id/omnibarTextInput",
            "com.sec.android.app.sbrowser:id/location_bar_edit_text"
        )

        for (id in urlBarIds) {
            val nodes = node.findAccessibilityNodeInfosByViewId(id)
            if (nodes.isNotEmpty()) {
                val text = nodes[0].text?.toString()
                nodes.forEach { it.recycle() }
                if (!text.isNullOrBlank() && (text.startsWith("http") || text.startsWith("www"))) {
                    return text
                }
            }
        }

        // Fallback: search all text nodes for something that looks like a URL
        return findUrlInSubtree(node)
    }

    private fun findUrlInSubtree(node: AccessibilityNodeInfo): String? {
        val text = node.text?.toString()
        if (!text.isNullOrBlank() && (text.startsWith("http://") || text.startsWith("https://"))) {
            return text
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val result = findUrlInSubtree(child)
            child.recycle()
            if (result != null) return result
        }
        return null
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Network: Send URL to QuantX PhishSense API
    // ──────────────────────────────────────────────────────────────────────────

    private suspend fun scanUrl(url: String) {
        val backendUrl = prefs(applicationContext)
            .getString(PREF_BACKEND_URL, "https://vipulcdex-quantx.hf.space") ?: return

        val body = JSONObject().put("text", url).toString()
            .toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("$backendUrl/api/security/phishing")
            .post(body)
            .build()

        try {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    Log.w(TAG, "API error: ${response.code}")
                    return
                }
                val json = JSONObject(response.body?.string() ?: return)
                val riskScore = json.optInt("risk_score", 0)
                val prediction = json.optString("prediction", "safe")
                val aiExplanation = json.optString("ai_explanation", "")

                Log.i(TAG, "Scan result: $prediction ($riskScore%) for $url")

                if (riskScore >= RISK_THRESHOLD && prediction != "safe") {
                    withContext(Dispatchers.Main) {
                        showThreatNotification(url, prediction, riskScore, aiExplanation)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Scan network error: ${e.message}")
        }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Notification
    // ──────────────────────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "QuantX Threat Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Real-time phishing and scam alerts from QuantX AI"
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun showThreatNotification(
        url: String,
        prediction: String,
        riskScore: Int,
        explanation: String
    ) {
        val label = prediction.replace("_", " ").uppercase()
        val displayUrl = if (url.length > 55) url.take(52) + "..." else url

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ QuantX Threat Detected: $label")
            .setContentText("Risk $riskScore% — $displayUrl")
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("$explanation\n\nURL: $url")
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID_BASE + url.hashCode() % 1000, notification)
    }
}
