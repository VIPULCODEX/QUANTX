import math

import pytest

import leakage
from findings import FacetSpec, REGISTRY


def test_cardinalities():
    assert leakage.facet_cardinality(FacetSpec("bool")) == 2
    assert leakage.facet_cardinality(FacetSpec("count")) == 5
    assert leakage.facet_cardinality(FacetSpec("enum", frozenset({"a", "b", "c"}))) == 3


def test_code_without_facets_has_one_variant_zero_bits():
    code = next(c for c, s in REGISTRY.items() if not s.facets)
    assert leakage.code_variants(code) == 1
    assert leakage.leakage_table()["per_code"][code]["facet_bits"] == 0


def test_hand_checked_example():
    # OVERLAY_ATTACK_LIVE: confidence (3 values) and target (3 values), both optional
    # -> (3+1)*(3+1) = 16 variants = 4 bits.
    assert leakage.code_variants("OVERLAY_ATTACK_LIVE") == 16
    assert leakage.leakage_table()["per_code"]["OVERLAY_ATTACK_LIVE"]["facet_bits"] == 4.0


def test_totals_are_consistent():
    t = leakage.leakage_table()
    assert t["total_payloads"] == sum(r["variants"] for r in t["per_code"].values())
    assert t["payload_bits_max"] == pytest.approx(math.log2(t["total_payloads"]), abs=1e-3)
    assert t["total_codes"] == len(REGISTRY)
    assert all(r["payload_bits_max"] == t["payload_bits_max"] for r in t["per_code"].values())
    assert t["scan_bits_max"] > t["payload_bits_max"]


def test_leakage_route(monkeypatch):
    pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient
    import api
    r = TestClient(api.app).get("/api/security/findings/leakage")
    assert r.status_code == 200
    assert r.json()["per_code"]["OVERLAY_ATTACK_LIVE"]["variants"] == 16
    assert "max-age" in r.headers["cache-control"]
