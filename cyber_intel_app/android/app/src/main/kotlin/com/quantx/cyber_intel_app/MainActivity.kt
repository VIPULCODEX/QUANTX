package com.quantx.cyber_intel_app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
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
                    "getWifiSecurity" -> {
                        try {
                            result.success(getWifiSecurity())
                        } catch (e: Exception) {
                            result.error("WIFI_ERROR", e.message, null)
                        }
                    }
                    "isAccessibilityServiceEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
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

    // ── Wi-Fi security ───────────────────────────────────────────────────────
    /**
     * Read the connected network's ACTUAL security type from the system.
     *
     * The Dart side previously carried the comment "Android doesn't expose
     * security type directly via API — we ask user", and presented a manual
     * WPA3/WPA2/WEP/Open picker. That is not true on modern Android:
     *
     *   API 31+  WifiInfo.getCurrentSecurityType() reports it directly.
     *   Below    ScanResult.capabilities for the connected BSSID carries it as
     *            a string like "[WPA2-PSK-CCMP][ESS]".
     *
     * A user-supplied security type is worthless for a security audit anyway —
     * an attacker's rogue AP does not become safe because the user picked WPA3
     * from a dropdown.
     */
    @Suppress("DEPRECATION")
    private fun getWifiSecurity(): Map<String, Any?> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info: WifiInfo? = wm.connectionInfo

        val ssidRaw = info?.ssid ?: ""
        val ssid = ssidRaw.trim('"')
        val bssid = info?.bssid
        val connected = info != null &&
            ssid.isNotEmpty() &&
            ssid != "<unknown ssid>" &&
            info.networkId != -1

        var security = "UNKNOWN"
        var source = "unavailable"

        if (connected) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                security = when (info!!.currentSecurityType) {
                    WifiInfo.SECURITY_TYPE_OPEN -> "OPEN"
                    WifiInfo.SECURITY_TYPE_WEP -> "WEP"
                    WifiInfo.SECURITY_TYPE_PSK -> "WPA/WPA2 PSK"
                    WifiInfo.SECURITY_TYPE_EAP -> "WPA/WPA2 Enterprise"
                    WifiInfo.SECURITY_TYPE_SAE -> "WPA3 SAE"
                    WifiInfo.SECURITY_TYPE_OWE -> "Enhanced Open (OWE)"
                    WifiInfo.SECURITY_TYPE_WAPI_PSK -> "WAPI PSK"
                    WifiInfo.SECURITY_TYPE_WAPI_CERT -> "WAPI Cert"
                    else -> "UNKNOWN"
                }
                source = "WifiInfo.currentSecurityType"
            }
            // Pre-31, or when the API reports UNKNOWN, fall back to the
            // capability string of the matching scan result.
            if (security == "UNKNOWN" && bssid != null) {
                try {
                    val match = wm.scanResults?.firstOrNull { it.BSSID == bssid }
                    if (match != null) {
                        security = parseCapabilities(match.capabilities)
                        source = "ScanResult.capabilities"
                    }
                } catch (e: SecurityException) {
                    // scanResults needs location permission + location enabled
                    source = "denied: location permission required"
                }
            }
        }

        return mapOf(
            "connected" to connected,
            "ssid" to if (connected) ssid else null,
            "security" to security,
            "source" to source,
            "rssi" to info?.rssi,
            "linkSpeedMbps" to info?.linkSpeed,
            "frequencyMhz" to info?.frequency,
            "band" to bandOf(info?.frequency),
            "hidden" to (info?.hiddenSSID ?: false),
            "sdkInt" to Build.VERSION.SDK_INT
        )
    }

    /** e.g. "[WPA2-PSK-CCMP][RSN-PSK-CCMP][ESS]" -> "WPA/WPA2 PSK" */
    private fun parseCapabilities(caps: String?): String {
        if (caps.isNullOrBlank()) return "UNKNOWN"
        val c = caps.uppercase()
        return when {
            c.contains("WPA3") || c.contains("SAE") -> "WPA3 SAE"
            c.contains("OWE") -> "Enhanced Open (OWE)"
            c.contains("WPA2") || c.contains("RSN") -> "WPA/WPA2 PSK"
            c.contains("WPA") -> "WPA (legacy)"
            c.contains("WEP") -> "WEP"
            // [ESS] with no cipher block means no encryption at all.
            c.contains("ESS") -> "OPEN"
            else -> "UNKNOWN"
        }
    }

    private fun bandOf(freq: Int?): String? = when {
        freq == null || freq <= 0 -> null
        freq >= 5925 -> "6 GHz"
        freq >= 4900 -> "5 GHz"
        else -> "2.4 GHz"
    }

    // ── Accessibility service state ──────────────────────────────────────────
    /**
     * Whether the QuantX URL scanner is currently bound.
     *
     * ENABLED_ACCESSIBILITY_SERVICES is readable by any app with no permission
     * at all — which is why the accessibility audit is a Tier 0 capability.
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val expected = "$packageName/$packageName.QuantXScannerService"
        val enabled = android.provider.Settings.Secure.getString(
            contentResolver,
            android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
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
