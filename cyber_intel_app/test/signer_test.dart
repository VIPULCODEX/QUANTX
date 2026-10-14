import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cyber_intel_app/services/payload_signer.dart';

void main() {
  test('HMAC-SHA256 matches RFC 4231 test case 2', () {
    final mac = PayloadSigner.hmacHex(
        utf8.encode('Jefe'), utf8.encode('what do ya want for nothing?'));
    expect(mac,
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
  });

  test('signature matches the server implementation (shared vector)', () {
    // Same inputs as cybersecurity_friend/test_signing.py::test_shared_vector.
    final key = List<int>.generate(32, (_) => 0xab);
    final body = utf8.encode(
        '{"want_ai":true,"findings":[{"code":"DEV_OPTIONS_ENABLED","facets":{}}]}');
    expect(PayloadSigner.signatureFor(key, 'nonce-0001abc', body),
        '31636f035765cddde3bc0b5cb49fa3465eb1c803117bd25bbc2443fb25fb17c8');
  });
}
