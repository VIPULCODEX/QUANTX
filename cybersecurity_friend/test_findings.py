"""
test_findings.py — adversarial tests for the privacy gate.

These are written from the attacker's side: assume the client is fully
compromised and is deliberately trying to smuggle user data out through the
findings channel. Every test below is an exfiltration attempt that must fail.

Run standalone:  python test_findings.py
Or with pytest:  pytest test_findings.py
"""

from findings import (
    COUNT_BUCKET_OVERFLOW,
    Finding,
    GateError,
    REGISTRY,
    Severity,
    Tier,
    assert_no_leak,
    bucket_count,
    offline_advice,
    registry_summary,
    sanitize_batch,
    sanitize_finding,
)

SECRET = "com.mybank.private.account.9876543210"


# ─────────────────────────────────────────────────────────────────────────────
# Exfiltration attempts
# ─────────────────────────────────────────────────────────────────────────────
def test_unknown_code_is_rejected():
    """An unknown code is a free-text channel. It must not survive."""
    for attempt in (
        {"code": f"LEAK:{SECRET}"},
        {"code": SECRET},
        {"code": "A11Y_UNTRUSTED_SERVICE_" + SECRET},
        {"code": ""},
        {"code": 123},
        {"code": None},
    ):
        try:
            sanitize_finding(attempt)
        except GateError:
            continue
        raise AssertionError(f"gate accepted a bad code: {attempt!r}")


def test_undeclared_facets_are_dropped():
    """Extra facets are the obvious smuggling route."""
    out = sanitize_finding({
        "code": "SELF_DEBUGGER_ATTACHED",
        "facets": {
            "package": SECRET,
            "ssid": "HomeWiFi-5G",
            "path": "/data/data/com.mybank/files/session",
            "ip": "192.168.1.44",
        },
    })
    assert out.facets == {}, f"facets leaked: {out.facets}"
    assert SECRET not in str(out.to_dict())


def test_free_text_in_declared_enum_facet_is_dropped():
    """A declared facet still only accepts values from its closed set."""
    out = sanitize_finding({
        "code": "A11Y_UNTRUSTED_SERVICE",
        "facets": {"src": SECRET, "count": 2},
    })
    assert "src" not in out.facets, "enum facet accepted arbitrary text"
    assert out.facets["count"] == "2-5"


def test_valid_enum_value_survives():
    out = sanitize_finding({
        "code": "A11Y_UNTRUSTED_SERVICE",
        "facets": {"src": "sideload", "count": 1},
    })
    assert out.facets == {"src": "sideload", "count": "1"}


def test_nested_structures_are_dropped():
    """Objects/arrays inside a facet must not pass through."""
    out = sanitize_finding({
        "code": "A11Y_UNTRUSTED_SERVICE",
        "facets": {"src": {"nested": SECRET}, "count": [1, 2, 3]},
    })
    assert out.facets == {}, f"structured data leaked: {out.facets}"


def test_counts_are_bucketed_not_exact():
    """Exact counts fingerprint a device across findings."""
    assert bucket_count(0) == "0"
    assert bucket_count(1) == "1"
    assert bucket_count(3) == "2-5"
    assert bucket_count(11) == "6-20"
    assert bucket_count(9999) == COUNT_BUCKET_OVERFLOW

    out = sanitize_finding({"code": "PKG_UNKNOWN_INSTALLER", "facets": {"count": 137}})
    assert out.facets["count"] == COUNT_BUCKET_OVERFLOW
    assert "137" not in str(out.to_dict())


def test_negative_and_bool_counts_rejected():
    out = sanitize_finding({"code": "PKG_UNKNOWN_INSTALLER", "facets": {"count": -5}})
    assert "count" not in out.facets
    out = sanitize_finding({"code": "PKG_UNKNOWN_INSTALLER", "facets": {"count": True}})
    assert "count" not in out.facets


# ─────────────────────────────────────────────────────────────────────────────
# Client cannot influence authority fields
# ─────────────────────────────────────────────────────────────────────────────
def test_client_cannot_set_severity_or_tier():
    """A compromised client must not be able to suppress a critical finding."""
    out = sanitize_finding({
        "code": "SELF_SIGNATURE_MISMATCH",
        "sev": "info",
        "tier": 0,
        "severity": "info",
    })
    assert out.severity is Severity.CRITICAL, "client downgraded severity"
    assert out.tier is Tier.SANDBOX


def test_top_level_extras_never_serialize():
    out = sanitize_finding({
        "code": "DEV_OPTIONS_ENABLED",
        "note": SECRET,
        "user_id": "vipul",
        "logs": ["line one", "line two"],
    })
    payload = out.to_dict()
    assert set(payload) == {"code", "sev", "tier", "facets"}
    assert SECRET not in str(payload)


# ─────────────────────────────────────────────────────────────────────────────
# Batch handling
# ─────────────────────────────────────────────────────────────────────────────
def test_bad_finding_does_not_poison_batch():
    accepted, rejected = sanitize_batch([
        {"code": "DEV_OPTIONS_ENABLED"},
        {"code": f"EVIL:{SECRET}"},
        {"code": "EMULATOR_DETECTED"},
    ])
    assert [f.code for f in accepted] == ["DEV_OPTIONS_ENABLED", "EMULATOR_DETECTED"]
    assert len(rejected) == 1
    # The rejection reason is truncated so it cannot echo a long payload back.
    assert len(rejected[0]) < 120


def test_batch_size_is_capped():
    try:
        sanitize_batch([{"code": "DEV_OPTIONS_ENABLED"}] * 101)
    except GateError:
        return
    raise AssertionError("oversized batch accepted")


def test_non_list_batch_rejected():
    try:
        sanitize_batch({"code": "DEV_OPTIONS_ENABLED"})
    except GateError:
        return
    raise AssertionError("non-list batch accepted")


# ─────────────────────────────────────────────────────────────────────────────
# Independent outbound check
# ─────────────────────────────────────────────────────────────────────────────
def test_assert_no_leak_catches_handcrafted_payloads():
    """assert_no_leak must fail even on payloads the gate never produced,
    because it is the independent second line of defence."""
    bad_payloads = [
        {"code": "DEV_OPTIONS_ENABLED", "sev": "medium", "tier": 0,
         "facets": {}, "extra": SECRET},
        {"code": "NOPE", "sev": "high", "tier": 0, "facets": {}},
        {"code": "A11Y_UNTRUSTED_SERVICE", "sev": "high", "tier": 0,
         "facets": {"package": SECRET}},
        {"code": "PKG_UNKNOWN_INSTALLER", "sev": "medium", "tier": 1,
         "facets": {"count": 137}},          # unbucketed
    ]
    for payload in bad_payloads:
        try:
            assert_no_leak(payload)
        except GateError:
            continue
        raise AssertionError(f"assert_no_leak passed a bad payload: {payload!r}")


def test_assert_no_leak_passes_every_real_finding():
    """Anything the gate produces must survive the independent check."""
    for code, spec in REGISTRY.items():
        facets = {}
        for name, fs in spec.facets.items():
            facets[name] = 3 if fs.kind == "count" else (
                True if fs.kind == "bool" else sorted(fs.values)[0]
            )
        finding = sanitize_finding({"code": code, "facets": facets})
        assert_no_leak(finding.to_dict())


# ─────────────────────────────────────────────────────────────────────────────
# Cache + playbooks
# ─────────────────────────────────────────────────────────────────────────────
def test_cache_key_is_stable_and_order_independent():
    a = sanitize_finding({"code": "A11Y_UNTRUSTED_SERVICE",
                          "facets": {"src": "play", "count": 2}})
    b = sanitize_finding({"code": "A11Y_UNTRUSTED_SERVICE",
                          "facets": {"count": 3, "src": "play"}})
    assert a.cache_key() == b.cache_key(), "same bucket should share a cache entry"


def test_offline_advice_available_for_high_severity_codes():
    """Anything CRITICAL must work with no network — that is the whole point of
    keeping playbooks on-device."""
    missing = [
        code for code, spec in REGISTRY.items()
        if spec.severity is Severity.CRITICAL
        and offline_advice(Finding(code, spec.severity, spec.tier)) is None
    ]
    assert not missing, f"CRITICAL codes without offline playbooks: {missing}"


def test_every_code_has_a_tier_and_title():
    for code, spec in REGISTRY.items():
        assert spec.title and isinstance(spec.title, str), code
        assert isinstance(spec.tier, Tier), code


if __name__ == "__main__":
    passed = failed = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
            except Exception as exc:                      # noqa: BLE001
                print(f"  FAIL  {name}\n          {type(exc).__name__}: {exc}")
                failed += 1
            else:
                print(f"  ok    {name}")
                passed += 1

    print(f"\n{passed} passed, {failed} failed")
    summary = registry_summary()
    print(f"\nregistry: {summary['total_codes']} codes  "
          f"(T0={len(summary['by_tier'][0])} "
          f"T1={len(summary['by_tier'][1])} "
          f"T2={len(summary['by_tier'][2])})")
    if summary["missing_playbooks"]:
        print(f"codes still needing playbooks: {len(summary['missing_playbooks'])}")
    raise SystemExit(1 if failed else 0)
