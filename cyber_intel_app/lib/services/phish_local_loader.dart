import 'package:flutter/services.dart' show rootBundle;

import 'phish_local.dart';

/// Loads the bundled PhishSense parameters once.
class PhishLocal {
  static PhishModel? _model;

  static Future<PhishModel> load() async {
    final cached = _model;
    if (cached != null) return cached;
    final model = PhishModel.fromJsonString(
        await rootBundle.loadString('assets/phish_model.json'));
    _model = model;
    return model;
  }
}
