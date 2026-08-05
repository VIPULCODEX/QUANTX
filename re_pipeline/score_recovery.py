"""
score_recovery.py — blind-recovery scoring for the QuantX agentic-RE pipeline
================================================================================

Compares a behavioral trace the RE agent derived BLIND (without having seen
ttp.json first) against that sample's ground truth, and computes a recovery
score. This is the number that goes in the paper (see the plan, Part A, step
A2): "can agentic RE rediscover known IOCs with no prior signature?"

Trace schema (what the agent should write to <sample>/trace.json after a
blind RE session, driven by the frida-mcp / ghidra-mcp tools):

    {
      "predicted_category": "<one of findings.py's _BEHAVIOR_CATEGORY values>",
      "confidence": "low" | "medium" | "high",
      "api_sequence": ["...ordered API call categories, not raw strings..."],
      "entry_point_guess": "Class#method",
      "network_activity_observed": "none" | "<free text, lab-only, never sent anywhere>",
      "notes": "free-text agent notes, lab-only, never leaves this machine"
    }

Ground truth schema: see any samples/*/ttp.json.

Usage:
    python3 score_recovery.py samples/a11y_screen_reader
    python3 score_recovery.py samples/*                 # score every sample with a trace.json
    python3 score_recovery.py --selftest samples/*      # sanity-check the scorer itself
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List


@dataclass
class RecoveryScore:
    sample: str
    category_match: bool
    entry_point_match: bool
    network_activity_match: bool
    api_sequence_overlap: float   # fraction of ground-truth calls recovered
    overall: float                # weighted composite, 0.0-1.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "sample": self.sample,
            "category_match": self.category_match,
            "entry_point_match": self.entry_point_match,
            "network_activity_match": self.network_activity_match,
            "api_sequence_overlap": round(self.api_sequence_overlap, 3),
            "overall": round(self.overall, 3),
        }


def _normalize(call: str) -> str:
    """Loose match on API call text so minor phrasing differences between the
    ground truth and the agent's own wording don't sink an otherwise-correct
    recovery. Case-insensitive, whitespace-collapsed."""
    return " ".join(call.lower().split())


def _entry_point_match(ground_truth: str, guess: str) -> bool:
    a, b = _normalize(ground_truth), _normalize(guess)
    # A guess counts if it names the same method, even without the full
    # package-qualified class name — that is still a correct recovery.
    method_a = a.rsplit("#", 1)[-1]
    method_b = b.rsplit("#", 1)[-1]
    return method_a == method_b or method_a in b or method_b in a


def score(ttp: Dict[str, Any], trace: Dict[str, Any]) -> RecoveryScore:
    truth_calls = [_normalize(c) for c in ttp["technique"]["api_sequence"]]
    trace_calls = {_normalize(c) for c in trace.get("api_sequence", [])}

    recovered = sum(
        1 for call in truth_calls
        if call in trace_calls or any(call in t or t in call for t in trace_calls)
    )
    overlap = recovered / len(truth_calls) if truth_calls else 0.0

    category_match = trace.get("predicted_category") == ttp["category"]
    entry_match = _entry_point_match(
        ttp["technique"]["entry_point"], trace.get("entry_point_guess", "")
    )
    network_match = (
        trace.get("network_activity_observed", "").strip().lower()
        == ttp["technique"]["network_activity"].strip().lower()
    )

    # Category is the primary claim (it becomes the finding-code facet); the
    # rest are supporting evidence for how the agent got there.
    overall = 0.5 * category_match + 0.3 * overlap + 0.1 * entry_match + 0.1 * network_match

    return RecoveryScore(
        sample=ttp["sample"],
        category_match=category_match,
        entry_point_match=entry_match,
        network_activity_match=network_match,
        api_sequence_overlap=overlap,
        overall=overall,
    )


def _load(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text())


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample_dirs", nargs="+", help="sample directories to score")
    parser.add_argument(
        "--selftest", action="store_true",
        help="score each sample's ttp.json against itself (must be a perfect match) "
             "to sanity-check the scorer before trusting it on real agent output",
    )
    args = parser.parse_args(argv)

    results: List[RecoveryScore] = []
    for raw in args.sample_dirs:
        d = Path(raw)
        ttp_path = d / "ttp.json"
        if not ttp_path.exists():
            print(f"skip {d}: no ttp.json", file=sys.stderr)
            continue
        ttp = _load(ttp_path)

        if args.selftest:
            trace = {
                "predicted_category": ttp["category"],
                "api_sequence": ttp["technique"]["api_sequence"],
                "entry_point_guess": ttp["technique"]["entry_point"],
                "network_activity_observed": ttp["technique"]["network_activity"],
            }
        else:
            trace_path = d / "trace.json"
            if not trace_path.exists():
                print(f"skip {d}: no trace.json (run the blind RE session first)", file=sys.stderr)
                continue
            trace = _load(trace_path)

        s = score(ttp, trace)
        results.append(s)
        print(json.dumps(s.to_dict()))

        if args.selftest and s.overall < 1.0:
            print(f"FAIL selftest: {d} scored {s.overall} against its own ground truth", file=sys.stderr)
            return 1

    if results:
        mean = sum(r.overall for r in results) / len(results)
        print(f"\nblind-recovery rate: {mean:.3f} across {len(results)} sample(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
