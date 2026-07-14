import 'package:flutter/services.dart';

/// ScannerService — Dart bridge to the native Kotlin QuantXScannerService
/// via the MethodChannel 'com.quantx.cyber_intel_app/scanner'.
///
/// Usage:
///   final enabled = await ScannerService.isScannerEnabled();
///   await ScannerService.setScannerEnabled(true);
class ScannerService {
  static const _channel =
      MethodChannel('com.quantx.cyber_intel_app/scanner');

  /// Returns whether the background scanner is currently enabled.
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
    } catch (_) {}
  }

  /// Update the backend URL the scanner uses for API calls.
  static Future<void> setBackendUrl(String url) async {
    try {
      await _channel.invokeMethod('setBackendUrl', {'url': url});
    } catch (_) {}
  }

  /// Opens Android Accessibility Settings so the user can enable the service.
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }
}
