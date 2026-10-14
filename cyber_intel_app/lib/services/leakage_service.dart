import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'install_token.dart';

/// Information capacity of the wire format, fetched from the backend, which
/// computes it from the same registry that validates findings.
///
/// These are upper bounds (capacity), not measured entropy of real traffic.
class LeakageInfo {
  final double payloadBitsMax;
  final int totalPayloads;
  final Map<String, double> facetBits; // code -> bits the facets can add

  const LeakageInfo(this.payloadBitsMax, this.totalPayloads, this.facetBits);

  factory LeakageInfo.fromJson(Map<String, dynamic> j) {
    final per = (j['per_code'] as Map? ?? {}).cast<String, dynamic>();
    return LeakageInfo(
      (j['payload_bits_max'] as num).toDouble(),
      (j['total_payloads'] as num).toInt(),
      {
        for (final e in per.entries)
          e.key: ((e.value as Map)['facet_bits'] as num).toDouble()
      },
    );
  }
}

class LeakageService {
  static LeakageInfo? _cached;

  /// Null if the backend cannot be reached; callers show "unavailable".
  static Future<LeakageInfo?> fetch() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final resp = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/api/security/findings/leakage'),
            headers: await InstallToken.headers(),
          )
          .timeout(AppConfig.requestTimeout);
      if (resp.statusCode != 200) return null;
      _cached =
          LeakageInfo.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      return _cached;
    } catch (_) {
      return null;
    }
  }
}
