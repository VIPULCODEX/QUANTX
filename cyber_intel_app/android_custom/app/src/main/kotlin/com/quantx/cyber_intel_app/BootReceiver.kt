package com.quantx.cyber_intel_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BootReceiver — Logs that the device has rebooted.
 * The Accessibility Service is re-enabled automatically by Android
 * if the user had previously granted permission.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d("QuantX.Boot", "Device booted. Accessibility Service will auto-reconnect if enabled.")
        }
    }
}
