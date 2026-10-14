import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One request body exactly as it was handed to the network layer.
class SentPayload {
  final DateTime time;

  /// The literal JSON string that was sent. Stored as text, not as objects, so
  /// the log cannot drift from the wire: what is shown is what was transmitted.
  final String body;

  const SentPayload(this.time, this.body);

  /// The findings in [body], for display. Empty if the body is not as expected.
  List<Map<String, dynamic>> get findings {
    try {
      final decoded = jsonDecode(body);
      final list = (decoded as Map)['findings'] as List? ?? const [];
      return list
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> toJson() =>
      {'t': time.toIso8601String(), 'b': body};

  static SentPayload? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = DateTime.tryParse('${j['t']}');
    final b = j['b'];
    if (t == null || b is! String) return null;
    return SentPayload(t, b);
  }
}

/// Last [maxEntries] findings requests, newest first.
///
/// The ONLY writer is ScanService._fetchAdvice, which calls [record] with the
/// very string it then sends. There is no second serialisation path.
class PayloadLog extends ChangeNotifier {
  PayloadLog._();
  static final PayloadLog instance = PayloadLog._();

  static const maxEntries = 20;
  static const _prefsKey = 'quantx_payload_log';

  final List<SentPayload> _entries = [];
  bool _loaded = false;

  List<SentPayload> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      for (final j in list) {
        final p = SentPayload.fromJson(j);
        if (p != null) _entries.add(p);
      }
      notifyListeners();
    } catch (_) {
      // A corrupt or unavailable log is not worth failing a scan over.
    }
  }

  void record(String body) {
    _entries.insert(0, SentPayload(DateTime.now(), body));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    _persist();
  }

  /// The stored log as the JSON the pilot tooling reads: the same records that
  /// are persisted ({"t", "b"}), where "b" is the literal request body. Nothing
  /// is re-serialised from objects, so the export cannot differ from the wire.
  String exportJson() =>
      jsonEncode(_entries.map((e) => e.toJson()).toList());

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
