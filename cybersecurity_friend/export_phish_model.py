"""
export_phish_model.py — export the PhishSense TF-IDF + logistic-regression
parameters as JSON for the on-device checker.

Read-only with respect to the model: model/model.pkl is opened, never written,
and inference.py is not touched. The pickle is read with a stub unpickler that
maps scikit-learn classes to plain state holders, so no scikit-learn install is
needed and no pickled code from the file is executed (only the one
`preprocess_text` reference, which is resolved to our own utils.preprocessing).

    python export_phish_model.py        # writes ../cyber_intel_app/assets/phish_model.json
"""
import hashlib
import json
import os
import pickle

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "model", "model.pkl")
OUT = os.path.join(HERE, "..", "cyber_intel_app", "assets", "phish_model.json")


class _State:
    def __setstate__(self, state):
        self.state = state


class _Unpickler(pickle.Unpickler):
    def find_class(self, module, name):
        if module.startswith(("sklearn", "scipy")):
            return type(name, (_State,), {})
        if module.endswith("preprocessing") and name == "preprocess_text":
            from utils.preprocessing import preprocess_text
            return preprocess_text
        return super().find_class(module, name)


def build() -> dict:
    raw = open(MODEL, "rb").read()
    art = _Unpickler(__import__("io").BytesIO(raw)).load()
    steps = dict(art["pipeline"].state["steps"])
    vec, clf = steps["vectorizer"].state, steps["classifier"].state
    tf = vec["_tfidf"].state

    # The on-device implementation reproduces exactly this configuration; refuse
    # to export anything else rather than ship a silently different model.
    expected = {
        "analyzer": "word", "lowercase": True, "ngram_range": (1, 2), "binary": False,
        "token_pattern": r"(?u)\b\w\w+\b", "stop_words": None, "strip_accents": None,
        "norm": "l2", "use_idf": True, "smooth_idf": True, "sublinear_tf": True,
    }
    for k, v in expected.items():
        got = vec.get(k, tf.get(k))
        assert got == v, f"unsupported vectorizer setting {k}={got!r}"
    assert clf["solver"] == "liblinear" and clf["multi_class"] in ("deprecated", "auto", "ovr"), \
        "unsupported classifier: probabilities are computed one-vs-rest"
    assert clf["fit_intercept"] is True

    vocab = {str(t): int(i) for t, i in vec["vocabulary_"].items()}
    idf = np.asarray(tf["idf_"], dtype=float)
    assert len(vocab) == len(idf) == clf["coef_"].shape[1]
    assert sorted(vocab.values()) == list(range(len(vocab)))
    import utils.rules as R
    import utils.url_checker as U
    # The Dart port hard-codes these four patterns (with Unicode-aware boundaries)
    # and the score constants; fail loudly if the Python side moves.
    assert R.OBFUSCATION_PATTERNS == {
        r"\bcl[1i]ck\b": "click", r"\bfr[3e]{2}\b": "free",
        r"\b0tp\b": "otp", r"\bv[3e]rify\b": "verify"}, "obfuscation patterns changed"
    sources = {}
    for rel in ("inference.py", "utils/rules.py", "utils/url_checker.py", "utils/preprocessing.py"):
        sources[rel] = hashlib.sha256(open(os.path.join(HERE, rel), "rb").read()).hexdigest()
    return {
        "format": 1,
        "sources_sha256": sources,
        "rules": {
            "classes": list(R.CLASSES),
            "urgency": sorted(R.URGENCY_WORDS), "phishing": sorted(R.PHISHING_WORDS),
            "otp": sorted(R.OTP_WORDS), "job": sorted(R.JOB_WORDS), "lottery": sorted(R.LOTTERY_WORDS),
            "shorteners": sorted(U.SHORTENERS), "suspicious_tlds": sorted(U.SUSPICIOUS_TLDS),
        },
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "sklearn_version": str(vec["_sklearn_version"]),
        "vectorizer": {
            "ngram_range": [1, 2],
            "sublinear_tf": True,
            "norm": "l2",
            "vocabulary": dict(sorted(vocab.items(), key=lambda kv: kv[1])),
            "idf": [float(x) for x in idf],
        },
        "classifier": {
            "kind": "ovr_logistic",
            "classes": [str(c) for c in clf["classes_"]],
            "coef": [[float(x) for x in row] for row in clf["coef_"]],
            "intercept": [float(x) for x in clf["intercept_"]],
        },
    }


def render() -> str:
    return json.dumps(build(), separators=(",", ":"), sort_keys=True) + "\n"


if __name__ == "__main__":
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(render())
    print("wrote", os.path.normpath(OUT), os.path.getsize(OUT), "bytes")
