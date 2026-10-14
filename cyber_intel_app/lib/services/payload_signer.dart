import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'install_token.dart';

/// Optional HMAC over the request body, sent in headers so that `toWire()` and
/// the body stay exactly as they were.
///
/// The signing key is derived from a random per-install secret and the install
/// token. On its first request the install offers the key to the server
/// (trust on first use); later requests carry only the signature. This stops
/// parties who lack the key from forging or editing requests for this install.
/// It does NOT authenticate the device and does nothing against a compromised
/// phone - see docs/payload_signing.md.
class PayloadSigner {
  static const _secretKey = 'quantx_signing_secret';
  static const _registeredKey = 'quantx_signing_registered';

  static String hmacHex(List<int> key, List<int> message) =>
      Hmac(sha256, key).convert(message).toString();

  /// HMAC-SHA256(key, nonce + "\n" + body), hex. Must match signing.sign() on
  /// the server; test/signer_test.dart pins a vector shared with pytest.
  static String signatureFor(List<int> key, String nonce, List<int> bodyBytes) =>
      hmacHex(key, utf8.encode('$nonce\n') + bodyBytes);

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static String _randomHex(int bytes) {
    final rng = Random.secure();
    return _hex(List.generate(bytes, (_) => rng.nextInt(256)));
  }

  static Future<List<int>> _signingKey(SharedPreferences prefs) async {
    var secret = prefs.getString(_secretKey);
    if (secret == null || secret.length != 64) {
      secret = _randomHex(32);
      await prefs.setString(_secretKey, secret);
    }
    final token = await InstallToken.get();
    final secretBytes = List<int>.generate(
        32, (i) => int.parse(secret!.substring(i * 2, i * 2 + 2), radix: 16));
    return Hmac(sha256, secretBytes)
        .convert(utf8.encode('quantx-sign-v1:$token'))
        .bytes;
  }

  /// Headers for [bodyBytes], which must be the exact bytes that are sent.
  static Future<Map<String, String>> headers(List<int> bodyBytes,
      {bool offerKey = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _signingKey(prefs);
    final nonce = _randomHex(16);
    final out = <String, String>{
      'X-Request-Nonce': nonce,
      'X-Signature': signatureFor(key, nonce, bodyBytes),
    };
    if (offerKey || !(prefs.getBool(_registeredKey) ?? false)) {
      out['X-Install-Key'] = _hex(key);
    }
    return out;
  }

  static Future<void> markRegistered(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_registeredKey, value);
  }
}
