"""
leakage.py — information capacity of the findings wire format, computed from
the registry in findings.py (never hand-entered).

Model. A wire finding is `{code, facets}`. Facets are optional, each drawn from
a closed set, so for one code the number of distinct payloads is

    V(code) = prod over its facets of (|values| + 1)        (the +1 is "absent")

where |values| is 2 for a bool, the enum size for an enum, and the number of
count buckets for a count. The number of distinct payloads in the whole format
is  P = sum over codes of V(code).

Upper bounds, in bits (these are CAPACITY, not what real devices emit - real
distributions are skewed and carry less; the eval harness measures that):

    facet_bits(code)   = log2 V(code)    what the facets add beyond the code
    payload_bits(code) = log2 P          largest a single payload could carry
    code_bits          = log2 (number of codes)

A scan sends a set of findings. Treating each code as absent-or-one-variant,
the set space is  prod over codes of (1 + V(code)),  so
    scan_bits = sum over codes of log2(1 + V(code))
bounds what a whole scan could reveal if every code were present or absent
independently and a code appeared at most once.
"""

import math
from functools import lru_cache
from typing import Any, Dict

from findings import COUNT_BUCKETS, COUNT_BUCKET_OVERFLOW, REGISTRY, FacetSpec

N_COUNT_BUCKETS = len(COUNT_BUCKETS) + 1       # includes the overflow bucket


def facet_cardinality(spec: FacetSpec) -> int:
    if spec.kind == "bool":
        return 2
    if spec.kind == "count":
        return N_COUNT_BUCKETS
    if spec.kind == "enum":
        return len(spec.values)
    raise ValueError(f"unknown facet kind: {spec.kind}")


def code_variants(code: str) -> int:
    v = 1
    for spec in REGISTRY[code].facets.values():
        v *= facet_cardinality(spec) + 1
    return v


@lru_cache(maxsize=1)
def leakage_table() -> Dict[str, Any]:
    per_code = {}
    total = 0
    for code in sorted(REGISTRY):
        v = code_variants(code)
        total += v
        per_code[code] = {
            "facets": {n: facet_cardinality(s) for n, s in sorted(REGISTRY[code].facets.items())},
            "variants": v,
            "facet_bits": round(math.log2(v), 4),
        }
    payload_bits = round(math.log2(total), 4)
    for row in per_code.values():
        row["payload_bits_max"] = payload_bits
    scan_bits = round(sum(math.log2(1 + r["variants"]) for r in per_code.values()), 4)
    return {
        "model": "capacity upper bounds, not measured entropy",
        "total_codes": len(REGISTRY),
        "total_payloads": total,
        "code_bits": round(math.log2(len(REGISTRY)), 4),
        "payload_bits_max": payload_bits,
        "scan_bits_max": scan_bits,
        "count_buckets": [b for _, b in COUNT_BUCKETS] + [COUNT_BUCKET_OVERFLOW],
        "per_code": per_code,
    }
