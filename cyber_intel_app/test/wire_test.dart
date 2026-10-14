// Property test for Finding.toWire(): whatever the native layer hands over,
// the transmittable form has exactly {code, facets}, and facet values come only
// from the registry vocabulary. The vocabulary is read from
// test/fixtures/facet_schema.json, generated from the server registry
// (cybersecurity_friend/export_schema.py; a pytest fails if it drifts).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:cyber_intel_app/services/scan_service.dart';

const _secrets = [
  'com.mybank.private.9876',
  'HomeNet-4B-Sharma',
  '192.168.1.77',
  '/data/data/x/y',
];

void main() {
  final schema = jsonDecode(File('test/fixtures/facet_schema.json').readAsStringSync())
      as Map<String, dynamic>;
  final codes = (schema['codes'] as Map<String, dynamic>);

  test('toWire emits only code and facets, never evidence', () {
    final rng = Random(20261009);
    final codeList = codes.keys.toList();

    for (var i = 0; i < 2000; i++) {
      final code = codeList[rng.nextInt(codeList.length)];
      final facetSchema = (codes[code] as Map<String, dynamic>);

      final facets = <String, dynamic>{};
      for (final entry in facetSchema.entries) {
        if (rng.nextBool()) {
          final values = (entry.value as Map)['values'] as List;
          facets[entry.key] = values[rng.nextInt(values.length)];
        }
      }
      final evidence = List.generate(
          rng.nextInt(4), (_) => _secrets[rng.nextInt(_secrets.length)]);

      final finding = Finding(code: code, facets: facets, evidence: evidence);
      final wire = finding.toWire();

      expect(wire.keys.toSet(), {'code', 'facets'});
      expect(wire['code'], code);

      final sent = wire['facets'] as Map<String, dynamic>;
      for (final entry in sent.entries) {
        final spec = facetSchema[entry.key] as Map<String, dynamic>?;
        expect(spec, isNotNull, reason: 'undeclared facet ${entry.key}');
        expect((spec!['values'] as List).contains(entry.value), isTrue,
            reason: '${entry.key}=${entry.value} not in registry vocabulary');
      }

      final encoded = jsonEncode(wire);
      for (final secret in _secrets) {
        expect(encoded.contains(secret), isFalse);
      }
    }
  });

  test('toWire does not widen when native supplies extra map keys', () {
    final f = Finding.fromNative({
      'code': 'A11Y_UNTRUSTED_SERVICE',
      'facets': {'count': '1'},
      'evidence': [_secrets[0]],
      'package': _secrets[0],
    });
    expect(f.toWire().keys.toSet(), {'code', 'facets'});
    expect(jsonEncode(f.toWire()).contains(_secrets[0]), isFalse);
  });
}
