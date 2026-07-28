import 'package:flutter/services.dart';

/// Typed wrapper over the native scanner MethodChannel.
///
/// Channel calls were previously written inline at each call site with raw
/// string method names, so a typo failed silently at runtime. Everything native
/// goes through here instead.
class SecurityChannel {
  static const _channel = MethodChannel('com.quantx.cyber_intel_app/scanner');

  /// Whether Android has BOUND the accessibility service. Distinct from
  /// [isScannerEnabled]: the OS can have the service bound while our own
  /// scanning toggle is off.
  static Future<bool> isAccessibilityServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Our own on/off switch for URL scanning.
  static Future<bool> isScannerEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isScannerEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setScannerEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setScannerEnabled', {'enabled': enabled});
    } on PlatformException {
      // Non-fatal: the UI re-reads state on the next refresh.
    }
  }

  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException {
      // Nothing useful to do if the settings intent cannot be launched.
    }
  }

  static Future<void> setBackendUrl(String url) async {
    try {
      await _channel.invokeMethod('setBackendUrl', {'url': url});
    } on PlatformException {
      // Native side keeps its previous default.
    }
  }

  /// Run the Tier 0 detector.
  ///
  /// Returns raw finding maps including on-device `evidence`, which must never
  /// be forwarded — see [Finding.toWire].
  static Future<List<Map<String, dynamic>>> runTier0Scan() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('runTier0Scan');
    return (raw ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.map((k, v) => MapEntry('$k', v)))
        .toList();
  }

  /// Connected network's real security type, read from the system.
  static Future<Map<String, dynamic>> getWifiSecurity() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getWifiSecurity',
    );
    return (raw ?? {}).map((k, v) => MapEntry('$k', v));
  }

  /// Installed packages with permissions and install source.
  ///
  /// No screen calls this today — the app-audit tab was removed — but the
  /// Deep Scan tier needs package enumeration, so the native side is kept.
  static Future<List<Map<String, dynamic>>> getInstalledApps(
      {bool includeSystem = false}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'getInstalledApps',
      {'includeSystem': includeSystem},
    );
    return (raw ?? [])
        .cast<Map<dynamic, dynamic>>()
        .map((m) => m.map((k, v) => MapEntry('$k', v)))
        .toList();
  }
}
