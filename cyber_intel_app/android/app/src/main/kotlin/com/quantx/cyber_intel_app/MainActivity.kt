package com.quantx.cyber_intel_app

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
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
                    "getInstalledApps" -> {
                        val includeSystem = call.argument<Boolean>("includeSystem") ?: false
                        try {
                            result.success(getInstalledApps(includeSystem))
                        } catch (e: Exception) {
                            result.error("PM_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Enumerate installed packages with their requested permissions.
     *
     * Replaces the `installed_apps` plugin, which was removed for causing SDK
     * mismatches. Reading PackageManager directly also gives us the requested
     * permissions and the install source — the plugin returned neither, so the
     * app audit was previously submitting empty permission lists.
     *
     * Requires QUERY_ALL_PACKAGES on Android 11+ (declared in the manifest).
     */
    @Suppress("DEPRECATION")
    private fun getInstalledApps(includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
        val packages = pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)

        return packages.mapNotNull { pkg ->
            val info: ApplicationInfo = pkg.applicationInfo ?: return@mapNotNull null
            val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && !includeSystem) return@mapNotNull null

            mapOf(
                "name" to pm.getApplicationLabel(info).toString(),
                "package" to pkg.packageName,
                "system" to isSystem,
                "permissions" to (pkg.requestedPermissions?.toList() ?: emptyList<String>()),
                "installer" to installerOf(pkg.packageName)
            )
        }
    }

    /** Install source, used to distinguish store installs from sideloads. */
    private fun installerOf(pkgName: String): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(pkgName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(pkgName)
        }
    } catch (e: Exception) {
        null
    }
}
