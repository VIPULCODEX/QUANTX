"""
export_schema.py — write the facet schema as JSON for the Dart tests.

    python export_schema.py            # rewrite the fixture
    pytest test_wire_property.py       # fails if the fixture has drifted

The Dart property test generates findings from this file, so it can only ever
use values the server registry actually allows.
"""
import json
import os

from findings import COUNT_BUCKETS, COUNT_BUCKET_OVERFLOW, REGISTRY

FIXTURE = os.path.join(os.path.dirname(__file__), "..", "cyber_intel_app",
                       "test", "fixtures", "facet_schema.json")


def schema_dict() -> dict:
    buckets = [b for _, b in COUNT_BUCKETS] + [COUNT_BUCKET_OVERFLOW]
    codes = {}
    for code in sorted(REGISTRY):
        facets = {}
        for name, spec in sorted(REGISTRY[code].facets.items()):
            if spec.kind == "enum":
                facets[name] = {"kind": "enum", "values": sorted(spec.values)}
            elif spec.kind == "count":
                facets[name] = {"kind": "count", "values": buckets}
            else:
                facets[name] = {"kind": "bool", "values": [True, False]}
        codes[code] = facets
    return {"codes": codes}


def render() -> str:
    return json.dumps(schema_dict(), indent=2, sort_keys=True) + "\n"


if __name__ == "__main__":
    with open(FIXTURE, "w", encoding="utf-8") as f:
        f.write(render())
    print("wrote", os.path.normpath(FIXTURE))
