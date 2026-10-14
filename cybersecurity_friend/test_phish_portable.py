"""
test_phish_portable.py — the pure-Python spec of the on-device model must
reproduce the real scikit-learn 1.6.1 probabilities recorded in the golden file,
and the exported JSON must still describe the current model.pkl.
"""
import hashlib
import json
import os

import pytest

import phish_portable

HERE = os.path.dirname(os.path.abspath(__file__))
GOLDEN = os.path.join(HERE, "..", "cyber_intel_app", "test", "fixtures", "phish_golden.json")
MODEL = os.path.join(HERE, "model", "model.pkl")


@pytest.fixture(scope="module")
def golden():
    with open(GOLDEN, encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="module")
def model():
    return phish_portable.load()


def test_golden_was_made_with_the_pinned_sklearn(golden):
    assert golden["sklearn_version"] == "1.6.1"
    assert len(golden["cases"]) > 200


def test_portable_matches_sklearn_probabilities(golden, model):
    worst = 0.0
    for case in golden["cases"]:
        got = phish_portable.ml_probs(model, case["text"])
        assert set(got) == set(case["ml_probs"])
        for c, p in case["ml_probs"].items():
            worst = max(worst, abs(got[c] - p))
    assert worst < 1e-9, worst


def test_probabilities_are_a_distribution(model):
    p = phish_portable.ml_probs(model, "urgent verify your account")
    assert sum(p.values()) == pytest.approx(1.0)
    assert all(0 <= v <= 1 for v in p.values())


def test_empty_text_uses_only_the_intercepts(model):
    p = phish_portable.ml_probs(model, "")
    assert sum(p.values()) == pytest.approx(1.0)


def test_exported_json_matches_current_model_pickle(model):
    assert model["source_sha256"] == hashlib.sha256(open(MODEL, "rb").read()).hexdigest(), \
        "model.pkl changed: run export_phish_model.py and make_phish_golden.py"
    pytest.importorskip("numpy")
    import export_phish_model
    assert json.loads(export_phish_model.render()) == model


def test_python_logic_the_dart_port_mirrors_has_not_changed(model):
    for rel, digest in model["sources_sha256"].items():
        assert hashlib.sha256(open(os.path.join(HERE, rel), "rb").read()).hexdigest() == digest, \
            f"{rel} changed: review lib/services/phish_local.dart, then re-run export_phish_model.py and make_phish_golden.py"


def test_golden_matches_the_real_pipeline(golden):
    sk = pytest.importorskip("sklearn")
    if sk.__version__ != "1.6.1":
        pytest.skip("needs scikit-learn 1.6.1")
    import warnings
    warnings.filterwarnings("ignore")
    import inference
    m = inference.load_model()
    for case in golden["cases"][::7]:
        assert inference.analyze_text(case["text"], model=m) == case["expected"]
