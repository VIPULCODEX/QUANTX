import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';

/// ScannerService — controls the native Kotlin QuantXScannerService
/// via MethodChannel for state management.
///
/// For OPENING ACCESSIBILITY SETTINGS, we use the `app_settings` package
/// directly — it has its own native integration that is more reliable
/// than a custom MethodChannel, especially before native code is fully built.
class ScannerService {
  static const _channel =
      MethodChannel('com.quantx.cyber_intel_app/scanner');

  /// Returns whether the background scanner is currently enabled.
  /// Falls back to false if MethodChannel is unavailable (e.g., on iOS or
  /// before native code is compiled).
  static Future<bool> isScannerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isScannerEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enable or disable the background web scanner.
  static Future<void> setScannerEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setScannerEnabled', {'enabled': enabled});
    } catch (_) {
      // MethodChannel not available — state persists visually in UI only
    }
  }

  /// Update the backend URL the scanner uses for API calls.
  static Future<void> setBackendUrl(String url) async {
    try {
      await _channel.invokeMethod('setBackendUrl', {'url': url});
    } catch (_) {}
  }

  /// Opens Android Accessibility Settings so the user can enable the service.
  ///
  /// Uses [AppSettings.openAccessibilitySettings] from the `app_settings`
  /// package — this is a well-tested Flutter plugin with its own native
  /// bridge, bypassing any MethodChannel issues in our custom MainActivity.
  static Future<void> openAccessibilitySettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.accessibility);
    } catch (e) {
      // Fallback: try opening general settings
      try {
        await AppSettings.openAppSettings(type: AppSettingsType.settings);
      } catch (_) {}
    }
  }
}
