// On-device PhishSense: the same text model, rules and URL checks the server
// runs, executed locally so the message or link being checked never leaves the
// phone.
//
// This is a port, not a re-implementation by guesswork. The model parameters
// come from assets/phish_model.json (exported from the server's model.pkl by
// cybersecurity_friend/export_phish_model.py) and the output is checked against
// golden vectors recorded from the real scikit-learn 1.6.1 pipeline
// (test/phish_local_test.dart). Known, accepted differences are listed at the
// bottom of this file.
//
// Pure Dart on purpose: no Flutter imports, so it can run under `dart test`.

import 'dart:convert';
import 'dart:math' as math;

class PhishModel {
  final Map<String, int> _vocab;
  final List<double> _idf;
  final List<String> classes;
  final List<List<double>> _coef;
  final List<double> _intercept;
  final Set<String> _urgency, _phishing, _otp, _job, _lottery, _shorteners, _badTlds;

  PhishModel._(this._vocab, this._idf, this.classes, this._coef, this._intercept,
      this._urgency, this._phishing, this._otp, this._job, this._lottery,
      this._shorteners, this._badTlds);

  factory PhishModel.fromJsonString(String source) =>
      PhishModel.fromJson(jsonDecode(source) as Map<String, dynamic>);

  factory PhishModel.fromJson(Map<String, dynamic> j) {
    final vec = j['vectorizer'] as Map<String, dynamic>;
    final clf = j['classifier'] as Map<String, dynamic>;
    final rules = j['rules'] as Map<String, dynamic>;
    Set<String> set(String k) =>
        (rules[k] as List).map((e) => '$e').toSet();
    return PhishModel._(
      (vec['vocabulary'] as Map).map((k, v) => MapEntry('$k', (v as num).toInt())),
      (vec['idf'] as List).map((e) => (e as num).toDouble()).toList(),
      (clf['classes'] as List).map((e) => '$e').toList(),
      (clf['coef'] as List)
          .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
          .toList(),
      (clf['intercept'] as List).map((e) => (e as num).toDouble()).toList(),
      set('urgency'), set('phishing'), set('otp'), set('job'), set('lottery'),
      set('shorteners'), set('suspicious_tlds'),
    );
  }

  // ── text normalisation (utils/preprocessing.py) ───────────────────────────
  static final _urlPattern =
      RegExp(r'(https?://[^\s]+|www\.[^\s]+)', caseSensitive: false);
  static final _nonAlnum = RegExp(r'[^a-z0-9\s]');
  static final _spaces = RegExp(r'\s+');

  static List<String> extractUrls(String text) =>
      _urlPattern.allMatches(text).map((m) => m.group(0)!).toList();

  static String preprocess(String text) {
    final lowered = text.toLowerCase().trim();
    final urls = extractUrls(lowered);
    var noUrls = lowered.replaceAll(_urlPattern, ' ');
    noUrls = noUrls.replaceAll(_nonAlnum, ' ');
    noUrls = noUrls.replaceAll(_spaces, ' ').trim();
    return urls.isNotEmpty ? '$noUrls ${urls.join(' ')}'.trim() : noUrls;
  }

  // ── text model (TfidfVectorizer + one-vs-rest LogisticRegression) ─────────
  // Python's (?u)\b\w\w+\b: maximal runs of 2+ word characters, where a word
  // character is a Unicode letter or number or underscore. Dart's own \w is
  // ASCII-only, so the class is spelled out.
  static final _wordRun = RegExp(
      r'(?<![\p{L}\p{N}_])[\p{L}\p{N}_]{2,}(?![\p{L}\p{N}_])',
      unicode: true);

  /// Class probabilities in [classes] order. Matches `pipeline.predict_proba`.
  List<double> mlProbs(String text) {
    final tokens = _wordRun.allMatches(preprocess(text)).map((m) => m.group(0)!).toList();
    final terms = <String>[...tokens];
    for (var i = 0; i + 1 < tokens.length; i++) {
      terms.add('${tokens[i]} ${tokens[i + 1]}');
    }
    final counts = <int, int>{};
    for (final t in terms) {
      final idx = _vocab[t];
      if (idx != null) counts[idx] = (counts[idx] ?? 0) + 1;
    }

    final x = <int, double>{};
    counts.forEach((j, c) => x[j] = (1.0 + math.log(c)) * _idf[j]);
    var sq = 0.0;
    for (final v in x.values) {
      sq += v * v;
    }
    final norm = math.sqrt(sq);
    if (norm > 0) {
      x.updateAll((j, v) => v / norm);
    }

    final scores = <double>[];
    for (var k = 0; k < classes.length; k++) {
      var d = _intercept[k];
      final row = _coef[k];
      x.forEach((j, v) => d += row[j] * v);
      scores.add(1.0 / (1.0 + math.exp(-d)));
    }
    final total = scores.fold<double>(0.0, (a, b) => a + b);
    return scores.map((s) => s / total).toList();
  }

  // ── rules (utils/rules.py) ────────────────────────────────────────────────
  static final _alnumRun = RegExp(r'[a-z0-9]+');
  // Python's \b is Unicode-aware; Dart's is not, so boundaries are explicit.
  static const _b0 = r'(?<![\p{L}\p{N}_])';
  static const _b1 = r'(?![\p{L}\p{N}_])';
  static final _obfuscation = <MapEntry<RegExp, String>>[
    MapEntry(RegExp('${_b0}cl[1i]ck$_b1', unicode: true), 'click'),
    MapEntry(RegExp('${_b0}fr[3e]{2}$_b1', unicode: true), 'free'),
    MapEntry(RegExp('${_b0}0tp$_b1', unicode: true), 'otp'),
    MapEntry(RegExp('${_b0}v[3e]rify$_b1', unicode: true), 'verify'),
  ];

  List<String> _hits(Set<String> tokens, Set<String> words) =>
      (tokens.intersection(words).toList()..sort(_byCodePoint));

  Map<String, dynamic> _rules(String text) {
    final lowered = text.toLowerCase();
    final tokens = _alnumRun.allMatches(lowered).map((m) => m.group(0)!).toSet();

    var score = 0;
    var reasons = <String>[];
    final highlighted = <String>{};
    final cls = <String, double>{
      for (final c in const ['phishing', 'otp_scam', 'job_scam', 'lottery', 'safe']) c: 0.0
    };

    final urgency = _hits(tokens, _urgency);
    if (urgency.isNotEmpty) {
      score += 20;
      reasons.add('Urgency detected');
      highlighted.addAll(urgency);
      cls['phishing'] = cls['phishing']! + 10;
    }
    final phishing = _hits(tokens, _phishing);
    if (phishing.isNotEmpty) {
      score += 25;
      reasons.add('Account verification pressure detected');
      highlighted.addAll(phishing);
      cls['phishing'] = cls['phishing']! + 35;
    }
    final otp = _hits(tokens, _otp);
    if (otp.isNotEmpty) {
      score += 40;
      reasons.add('OTP solicitation detected');
      highlighted.addAll(otp);
      cls['otp_scam'] = cls['otp_scam']! + 70;
    }
    final job = _hits(tokens, _job);
    if (job.isNotEmpty) {
      score += 30;
      reasons.add('Job/earning lure detected');
      highlighted.addAll(job);
      cls['job_scam'] = cls['job_scam']! + 60;
    }
    final lottery = _hits(tokens, _lottery);
    if (lottery.isNotEmpty) {
      score += 30;
      reasons.add('Financial lure detected');
      highlighted.addAll(lottery);
      cls['lottery'] = cls['lottery']! + 60;
    }

    for (final e in _obfuscation) {
      if (e.key.hasMatch(lowered)) {
        score += 15;
        if (!reasons.contains('Obfuscated wording detected')) {
          reasons.add('Obfuscated wording detected');
        }
        highlighted.add(e.value);
        if (e.value == 'otp') {
          cls['otp_scam'] = cls['otp_scam']! + 20;
        } else if (e.value == 'verify' || e.value == 'click') {
          cls['phishing'] = cls['phishing']! + 10;
        } else {
          cls['lottery'] = cls['lottery']! + 5;
        }
      }
    }

    if (extractUrls(lowered).isNotEmpty) {
      score += 5;
      cls['phishing'] = cls['phishing']! + 5;
    }

    score = math.min(score, 100);
    if (score < 15) {
      cls['safe'] = 100;
      reasons = ['No major scam indicators found'];
    }
    return {'score': score, 'reasons': reasons, 'highlighted': highlighted, 'classScores': cls};
  }

  // ── URL checks (utils/url_checker.py) ─────────────────────────────────────
  /// Python's urlparse(...).netloc for the "http://"-prefixed candidate: the
  /// text after "//" up to the first '/', '?' or '#'.
  static String _netloc(String url) {
    final candidate =
        (url.startsWith('http://') || url.startsWith('https://')) ? url : 'http://$url';
    final start = candidate.indexOf('//') + 2;
    var end = candidate.length;
    for (final ch in const ['/', '?', '#']) {
      final i = candidate.indexOf(ch, start);
      if (i != -1 && i < end) end = i;
    }
    return candidate.substring(start, end);
  }

  static String _domain(String url) {
    var d = _netloc(url).toLowerCase();
    if (d.startsWith('www.')) d = d.substring(4);
    return d;
  }

  static bool _randomLooking(String domain) {
    final core = domain.split('.').first;
    final hasDigits = RegExp(r'[0-9]').hasMatch(core);
    final longCore = core.length >= 12;
    final manyHyphens = '-'.allMatches(core).length >= 2;
    return (hasDigits && longCore) || manyHyphens;
  }

  Map<String, dynamic> _urls(String text) {
    final urls = extractUrls(text);
    final suspicious = <String>[];
    final reasons = <String>[];
    for (final url in urls) {
      final domain = _domain(url);
      if (domain.isEmpty) continue;
      final tld = domain.contains('.') ? domain.split('.').last : '';
      final shortener = _shorteners.contains(domain);
      final badTld = _badTlds.contains(tld);
      final random = _randomLooking(domain);
      if (shortener || badTld || random) suspicious.add(url);
      if (shortener && !reasons.contains('Shortened link detected')) {
        reasons.add('Shortened link detected');
      }
      if (badTld && !reasons.contains('Suspicious domain extension found')) {
        reasons.add('Suspicious domain extension found');
      }
      if (random && !reasons.contains('Random-looking domain detected')) {
        reasons.add('Random-looking domain detected');
      }
    }
    return {
      'flag': suspicious.isNotEmpty ? 'Suspicious' : 'Safe',
      'urls': urls,
      'suspicious': suspicious,
      'reasons': reasons,
    };
  }

  // ── combination (inference.analyze_text) ──────────────────────────────────
  /// Same keys as the server's /api/security/phishing minus `ai_explanation`.
  Map<String, dynamic> analyze(String text) {
    final probs = mlProbs(text);
    final mlProbsByClass = {for (var i = 0; i < classes.length; i++) classes[i]: probs[i]};

    final safeProb = mlProbsByClass['safe'] ?? 0.0;
    final mlRisk = (1.0 - safeProb) * 100.0;

    final rule = _rules(text);
    final url = _urls(text);

    var ruleScore = rule['score'] as int;
    final reasons = List<String>.from(rule['reasons'] as List<String>);
    final highlighted = Set<String>.from(rule['highlighted'] as Set<String>);

    if (url['flag'] == 'Suspicious') {
      ruleScore = math.min(100, ruleScore + 15);
      reasons.add('Suspicious URL found');
      highlighted.addAll(url['suspicious'] as List<String>);
    } else if ((url['urls'] as List).isNotEmpty) {
      reasons.add('URL present but no high-risk domain pattern found');
    }
    for (final r in url['reasons'] as List<String>) {
      if (!reasons.contains(r)) reasons.add(r);
    }

    final ruleClass = Map<String, double>.from(rule['classScores'] as Map<String, double>);
    if (url['flag'] == 'Suspicious') {
      ruleClass['phishing'] = (ruleClass['phishing'] ?? 0.0) + 20.0;
    }

    // _normalize_rule_scores
    var total = 0.0;
    for (final v in ruleClass.values) {
      total += v > 0 ? v : 0.0;
    }
    final ruleProbs = total == 0
        ? <String, double>{'safe': 1.0}
        : {for (final e in ruleClass.entries) e.key: (e.value > 0 ? e.value : 0.0) / total};

    String prediction = classes.first;
    var best = double.negativeInfinity;
    for (final c in classes) {
      final combined = 0.6 * (mlProbsByClass[c] ?? 0.0) + 0.4 * (ruleProbs[c] ?? 0.0);
      if (combined > best) {
        best = combined;
        prediction = c;
      }
    }

    var finalRisk = _pyRound(0.6 * mlRisk + 0.4 * ruleScore);
    finalRisk = math.max(0, math.min(100, finalRisk));

    if (finalRisk < 35 && safeProb >= 0.40 && ruleScore < 30) {
      prediction = 'safe';
    }

    if (prediction != 'safe' && reasons.contains('No major scam indicators found')) {
      reasons.remove('No major scam indicators found');
    }
    if (reasons.isEmpty) reasons.add('No major scam indicators found');

    return {
      'prediction': prediction,
      'risk_score': finalRisk,
      'reasons': reasons,
      'highlighted_words': highlighted.toList()..sort(_byCodePoint),
      'url_flag': url['flag'],
    };
  }

  /// Python's round(): halves go to the nearest even integer.
  static int _pyRound(double x) {
    final f = x.floorToDouble();
    final diff = x - f;
    final fi = f.toInt();
    if (diff < 0.5) return fi;
    if (diff > 0.5) return fi + 1;
    return fi.isEven ? fi : fi + 1;
  }

  /// Python sorts strings by code point; Dart's compareTo uses UTF-16 units.
  static int _byCodePoint(String a, String b) {
    final ra = a.runes.iterator, rb = b.runes.iterator;
    while (true) {
      final ma = ra.moveNext(), mb = rb.moveNext();
      if (!ma && !mb) return 0;
      if (!ma) return -1;
      if (!mb) return 1;
      if (ra.current != rb.current) return ra.current.compareTo(rb.current);
    }
  }
}

// Known, accepted differences from the Python implementation (none appear in the
// golden vectors; all concern unusual input):
//  * Whitespace: Python's \s and str.strip() also treat U+001C-U+001F and U+0085
//    as space; Dart's do not.
//  * Digits in the "random-looking domain" test: Python's str.isdigit() accepts
//    non-ASCII digits (e.g. Arabic-Indic, superscripts); this port counts 0-9 only.
//  * A malformed bracketed host such as "http://[bad" makes Python's urlparse
//    raise (the server then returns an error); this port just treats it as text.
