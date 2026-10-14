// The on-device PhishSense port must agree with the real server pipeline
// (scikit-learn 1.6.1 + rules + URL checks) on every golden vector.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cyber_intel_app/services/phish_local.dart';

void main() {
  final model = PhishModel.fromJsonString(
      File('assets/phish_model.json').readAsStringSync());
  final golden = jsonDecode(File('test/fixtures/phish_golden.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (golden['cases'] as List).cast<Map<String, dynamic>>();

  test('golden file was recorded with scikit-learn 1.6.1', () {
    expect(golden['sklearn_version'], '1.6.1');
    expect(cases.length, greaterThan(200));
  });

  test('class probabilities match scikit-learn', () {
    var worst = 0.0;
    for (final c in cases) {
      final want = (c['ml_probs'] as Map<String, dynamic>);
      final got = model.mlProbs(c['text'] as String);
      for (var i = 0; i < model.classes.length; i++) {
        final d = (got[i] - (want[model.classes[i]] as num).toDouble()).abs();
        if (d > worst) worst = d;
      }
    }
    expect(worst, lessThan(1e-9));
  });

  test('full analysis matches the server on every golden case', () {
    final failures = <String>[];
    for (final c in cases) {
      final text = c['text'] as String;
      final want = c['expected'] as Map<String, dynamic>;
      final got = model.analyze(text);
      final a = jsonEncode(_canon(want)), b = jsonEncode(_canon(got));
      if (a != b) {
        final shown = text.length > 60 ? '${text.substring(0, 60)}…' : text;
        failures.add('"$shown"\n  want $a\n  got  $b');
      }
    }
    expect(failures, isEmpty, reason: failures.take(5).join('\n'));
  });

  test('preprocess keeps URLs and strips punctuation like the server', () {
    expect(PhishModel.preprocess('  Hello, WORLD!! Visit http://Bit.ly/X now  '),
        'hello world visit now http://bit.ly/x');
    expect(PhishModel.preprocess(''), '');
  });

  test('empty and whitespace input are safe and do not throw', () {
    for (final t in ['', '   ', 'a']) {
      final r = model.analyze(t);
      expect(r['prediction'], isNotNull);
      expect(r['risk_score'], inInclusiveRange(0, 100));
    }
  });
}

Map<String, dynamic> _canon(Map<String, dynamic> m) => {
      'prediction': m['prediction'],
      'risk_score': m['risk_score'],
      'reasons': m['reasons'],
      'highlighted_words': m['highlighted_words'],
      'url_flag': m['url_flag'],
    };
