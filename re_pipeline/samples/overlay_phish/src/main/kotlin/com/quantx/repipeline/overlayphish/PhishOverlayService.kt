package com.quantx.repipeline.overlayphish

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/**
 * TTP reproduction: draw a TYPE_APPLICATION_OVERLAY window over the host app to
 * mimic a login screen (tapjacking / credential-overlay phishing) — the
 * technique QuantX's own OVERLAY_HOLDER_UNTRUSTED finding targets.
 *
 * Ground truth (ttp.json): renders a static, fake login form. Deliberately
 * never reads the actual text typed into the fields — only logs a boolean
 * "a submit was tapped" event locally, so this sample cannot itself become a
 * credential harvester even by accident.
 */
class PhishOverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private var overlayView: LinearLayout? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (overlayView == null) showOverlay()
        return START_STICKY
    }

    private fun showOverlay() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP }

        val view = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
            setBackgroundColor(0xE0202020.toInt())
            addView(TextView(this@PhishOverlayService).apply {
                text = "RE SAMPLE — fake login overlay (lab only, not real)"
                setTextColor(0xFFFFFFFF.toInt())
            })
            addView(EditText(this@PhishOverlayService).apply { hint = "username (never read)" })
            addView(EditText(this@PhishOverlayService).apply { hint = "password (never read)" })
            addView(Button(this@PhishOverlayService).apply {
                text = "Sign in"
                setOnClickListener {
                    // Deliberately logs only that the flow completed, never field contents.
                    Log.d(TAG, "overlay_submit_event (no field contents captured)")
                }
            })
        }
        overlayView = view
        windowManager.addView(view, params)
    }

    override fun onDestroy() {
        overlayView?.let { windowManager.removeView(it) }
        overlayView = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PhishOverlayService"
    }
}
