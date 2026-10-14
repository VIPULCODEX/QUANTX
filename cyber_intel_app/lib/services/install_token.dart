import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Random per-install identifier, sent as `X-Install-Token`.
///
/// The backend uses it for rate limiting and replay control only. It comes
/// from a CSPRNG on first run and is derived from nothing about the device, so
/// it cannot be recomputed from an IMEI, Android ID, account or hardware
/// property. Reinstalling the app produces a new one.
class InstallToken {
  static const _prefsKey = 'quantx_install_token';
  static final _valid = RegExp(r'^[0-9a-f]{32,64}$');
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var token = prefs.getString(_prefsKey);
    if (token == null || !_valid.hasMatch(token)) {
      final rng = Random.secure();
      token = List.generate(
        32,
        (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await prefs.setString(_prefsKey, token);
    }
    _cached = token;
    return token;
  }

  static Future<Map<String, String>> headers() async => {
        'Content-Type': 'application/json',
        'X-Install-Token': await get(),
      };
}
