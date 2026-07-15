package com.quantx.cyber_intel_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — Flutter host activity.
 * Exposes a MethodChannel so Flutter/Dart can:
 *   - Toggle the background scanner ON/OFF
 *   - Check if the scanner is currently enabled
 *   - Update the backend URL
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.quantx.cyber_intel_app/scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setScannerEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        QuantXScannerService.setScannerEnabled(applicationContext, enabled)
                        result.success(null)
                    }
                    "isScannerEnabled" -> {
                        result.success(QuantXScannerService.isScannerEnabled(applicationContext))
                    }
                    "setBackendUrl" -> {
                        val url = call.argument<String>("url") ?: ""
                        QuantXScannerService.setBackendUrl(applicationContext, url)
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        // Direct the user to Android Accessibility Settings to enable the service
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS
                        )
                        intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
