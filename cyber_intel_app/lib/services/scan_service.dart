import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'security_channel.dart';

/// One detection result.
///
/// [evidence] is the on-device detail — app names, file paths, ports. It is
/// shown in the UI and NEVER leaves the device. [toWire] is the only method
/// that produces something transmittable.
class Finding {
  final String code;
  final Map<String, dynamic> facets;
  final List<String> evidence;

  String? title;
  String severity;
  Map<String, dynamic>? offline;
  String? ai;

  Finding({
    required this.code,
    required this.facets,
    required this.evidence,
    this.severity = 'unknown',
  });

  factory Finding.fromNative(Map<String, dynamic> m) => Finding(
        code: '${m['code']}',
        facets: ((m['facets'] as Map?) ?? {})
            .map((k, v) => MapEntry('$k', v)),
        evidence:
            ((m['evidence'] as List?) ?? []).map((e) => '$e').toList(),
      );

  /// The ONLY representation that crosses the network.
  ///
  /// Deliberately does not include [evidence]. The server also validates
  /// against its own registry and drops anything undeclared, so a bug here is
  /// caught on the other side too.
  Map<String, dynamic> toWire() => {'code': code, 'facets': facets};
}

/// Runs the on-device scan and fetches remediation advice for the results.
class ScanService extends ChangeNotifier {
  List<Finding> _findings = [];
  bool _scanning = false;
  DateTime? _lastScan;
  String? _error;
  bool _adviceOffline = false;

  List<Finding> get findings => _findings;
  bool get scanning => _scanning;
  DateTime? get lastScan => _lastScan;
  String? get error => _error;

  /// True when advice came from the bundled playbooks because the server was
  /// unreachable. Surfaced in the UI so a silent degradation is visible.
  bool get adviceOffline => _adviceOffline;

  String get worstSeverity {
    const order = ['critical', 'high', 'medium', 'low', 'info'];
    for (final s in order) {
      if (_findings.any((f) => f.severity == s)) return s;
    }
    return _findings.isEmpty ? 'clear' : 'info';
  }

  Future<void> run() async {
    _scanning = true;
    _error = null;
    _adviceOffline = false;
    notifyListeners();

    try {
      final raw = await SecurityChannel.runTier0Scan();
      _findings = raw.map(Finding.fromNative).toList();
      _lastScan = DateTime.now();
      notifyListeners();

      if (_findings.isNotEmpty) await _fetchAdvice();
    } catch (e) {
      _error = '$e';
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  /// Send codes only, and merge the returned advice back in by code.
  Future<void> _fetchAdvice() async {
    try {
      final body = jsonEncode({
        'want_ai': true,
        'findings': _findings.map((f) => f.toWire()).toList(),
      });

      final resp = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/security/findings'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(AppConfig.requestTimeout);

      if (resp.statusCode != 200) {
        _adviceOffline = true;
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final byCode = <String, Map<String, dynamic>>{
        for (final r in (data['findings'] as List? ?? []))
          '${(r as Map)['code']}': r.cast<String, dynamic>()
      };

      for (final f in _findings) {
        final r = byCode[f.code];
        if (r == null) continue;
        f.severity = '${r['sev'] ?? 'unknown'}';
        f.title = r['title'] as String?;
        f.offline = (r['offline'] as Map?)?.cast<String, dynamic>();
        f.ai = r['ai'] as String?;
      }
      // Severity drives ordering, so sort only after the server has assigned it.
      const rank = {
        'critical': 0, 'high': 1, 'medium': 2, 'low': 3, 'info': 4, 'unknown': 5
      };
      _findings.sort(
          (a, b) => (rank[a.severity] ?? 9).compareTo(rank[b.severity] ?? 9));
    } catch (_) {
      // The scan itself already succeeded; only the advice is missing.
      _adviceOffline = true;
    }
  }
}
