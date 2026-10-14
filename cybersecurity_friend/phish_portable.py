"""
phish_portable.py — executable specification of the on-device PhishSense model.

Reproduces the scikit-learn TfidfVectorizer + one-vs-rest LogisticRegression
pipeline from the exported JSON using only the standard library. The Dart port
(cyber_intel_app/lib/services/phish_local.dart) follows this file. The rule and
URL layers are not re-implemented here: they are pure Python already
(utils/rules.py, utils/url_checker.py) and the Dart port is checked against the
real `inference.analyze_text` through golden vectors.
"""
import json
import math
import os
import re
from collections import Counter
from typing import Dict, List

from utils.preprocessing import preprocess_text

_TOKEN = re.compile(r"(?u)\b\w\w+\b")


def load(path: str = None) -> dict:
    path = path or os.path.join(os.path.dirname(__file__), "..", "cyber_intel_app", "assets", "phish_model.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _terms(text: str) -> List[str]:
    toks = _TOKEN.findall(preprocess_text(text))
    out = list(toks)
    out += [" ".join(toks[i:i + 2]) for i in range(len(toks) - 1)]
    return out


def ml_probs(model: dict, text: str) -> Dict[str, float]:
    vec, clf = model["vectorizer"], model["classifier"]
    vocab, idf = vec["vocabulary"], vec["idf"]
    counts = Counter(t for t in _terms(text) if t in vocab)

    x = {vocab[t]: (1.0 + math.log(c)) * idf[vocab[t]] for t, c in counts.items()}
    norm = math.sqrt(sum(v * v for v in x.values()))
    if norm > 0:
        x = {j: v / norm for j, v in x.items()}

    scores = []
    for row, b in zip(clf["coef"], clf["intercept"]):
        d = b + sum(row[j] * v for j, v in x.items())
        scores.append(1.0 / (1.0 + math.exp(-d)))
    total = sum(scores)                                   # one-vs-rest normalisation
    return {c: s / total for c, s in zip(clf["classes"], scores)}
