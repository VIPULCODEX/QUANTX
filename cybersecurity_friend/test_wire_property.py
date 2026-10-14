"""
test_wire_property.py — T5: randomized property test of the privacy gate.

For hostile random input (extra keys, wrong types, secrets in every field), what
comes out of sanitize_* must have exactly the keys {code, sev, tier, facets},
only declared facets, and every facet value an enum member, a bucket label or a
bool. Seeded, so a failure reproduces.
"""
import json
import os
import random

import pytest

from export_schema import FIXTURE, render
from findings import (COUNT_BUCKETS, COUNT_BUCKET_OVERFLOW, REGISTRY, assert_no_leak,
                      sanitize_batch, sanitize_finding, GateError)

SEED = 20261009
ITERATIONS = 3000
SECRETS = ["com.mybank.private.9876", "HomeNet-4B-Sharma", "192.168.1.77", "/data/data/x/y"]
BUCKETS = {b for _, b in COUNT_BUCKETS} | {COUNT_BUCKET_OVERFLOW}


def junk(rng):
    return rng.choice([None, True, False, 0, 7, -3, 10**9, 3.5, "", "x" * 50,
                       rng.choice(SECRETS), [rng.choice(SECRETS)], {"a": rng.choice(SECRETS)}])


def random_raw(rng):
    code = rng.choice(list(REGISTRY) + ["NOT_A_CODE", rng.choice(SECRETS), "", None, 5])
    raw = {"code": code}
    if rng.random() < 0.9:
        facets = {}
        spec = REGISTRY.get(code) if isinstance(code, str) else None
        names = list(spec.facets) if spec else []
        for name in names:
            if rng.random() < 0.7:
                fs = spec.facets[name]
                if fs.kind == "enum" and rng.random() < 0.6:
                    facets[name] = rng.choice(sorted(fs.values))
                elif fs.kind == "count" and rng.random() < 0.6:
                    facets[name] = rng.randint(0, 40)
                elif fs.kind == "bool" and rng.random() < 0.6:
                    facets[name] = rng.random() < 0.5
                else:
                    facets[name] = junk(rng)
        for _ in range(rng.randint(0, 3)):
            facets[rng.choice(["evidence", "pkg", "ssid", "path"])] = rng.choice(SECRETS)
        raw["facets"] = facets
    for extra in ("evidence", "sev", "tier", "title", "package"):
        if rng.random() < 0.4:
            raw[extra] = rng.choice(SECRETS) if extra != "sev" else "info"
    return raw


def test_gate_output_shape_holds_for_random_hostile_input():
    rng = random.Random(SEED)
    accepted_total = 0
    for _ in range(ITERATIONS):
        try:
            f = sanitize_finding(random_raw(rng))
        except GateError:
            continue
        accepted_total += 1
        d = f.to_dict()
        assert set(d) == {"code", "sev", "tier", "facets"}
        assert_no_leak(d)
        spec = REGISTRY[f.code]
        assert d["sev"] == spec.severity.value and d["tier"] == int(spec.tier)
        for name, value in d["facets"].items():
            fs = spec.facets[name]                       # declared, or KeyError
            if fs.kind == "enum":
                assert value in fs.values
            elif fs.kind == "count":
                assert value in BUCKETS and isinstance(value, str)
            else:
                assert isinstance(value, bool)
        blob = json.dumps(d)
        for secret in SECRETS:
            assert secret not in blob
    assert accepted_total > ITERATIONS // 4              # the test really exercised the gate


def test_batch_property():
    rng = random.Random(SEED + 1)
    for _ in range(200):
        items = [random_raw(rng) for _ in range(rng.randint(0, 12))]
        accepted, rejected = sanitize_batch(items)
        assert len(accepted) + len(rejected) == len(items)
        for f in accepted:
            assert set(f.to_dict()) == {"code", "sev", "tier", "facets"}


def test_dart_fixture_matches_registry():
    """The Dart property test generates from this file; it must not drift."""
    with open(FIXTURE, encoding="utf-8") as fh:
        assert fh.read() == render(), "run: python export_schema.py"
