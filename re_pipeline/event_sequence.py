"""
event_sequence.py — Live Attack Observer scorer (Mode 2, non-rooted, dynamic)
==============================================================================

The dynamic half of the non-rooted module (plan SYNTHESIS 2026-08-04, Mode 2).

A stock non-rooted app cannot read another process's memory — but if the user
grants QuantX its own AccessibilityService, the app receives the **live,
system-wide AccessibilityEvent stream** and can call getWindows(). That is
enough to catch an account-takeover *in progress* without ever touching another
app's memory. This module is the scorer over that stream; the on-device Kotlin
AccessibilityService feeds it the same event shape at runtime.

It detects three things, all live, all cross-app, all non-root:
  1. OVERLAY_ATTACK_LIVE     — an untrusted overlay drawn over a sensitive app
  2. A11Y_AUTOMATION_ANOMALY — machine-cadence automation driving a sensitive app
  3. NOTIF_HIJACK_LIVE       — an OTP notification cleared by a background app,
                               racing the user

Thresholds here are defensible defaults. On the real pipeline they are
**calibrated from the MCP-derived traces**: frida-mcp instruments the
re_pipeline/samples/ trojans on a lab device to record the exact event sequence
and inter-event timing each TTP emits, and those measurements replace the
constants below. That calibration is what makes Mode 2 measured, not guessed —
see the plan. It is not runnable until a device is attached.

Privacy: output is only {code, facets} with a bucketed `target` class and a
`confidence` — never the foreground app's identity nor the attacker package.
The event stream itself is on-device evidence and never leaves the device.

Usage:
    python3 event_sequence.py --selftest
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Set

# ── Calibration constants (defaults; MCP traces replace these) ───────────────
HUMAN_MIN_MEDIAN_MS = 120   # sustained action intervals below this are non-human
HIGH_CONF_MEDIAN_MS = 60    # and below this, with low variance, are unambiguous
LOW_COV = 0.35              # bots are regular; low coefficient of variation
MIN_ACTION_EVENTS = 5       # need a sustained run, not one fast tap
HIJACK_WINDOW_MS = 1500     # OTP removed within this of posting = hijack
HIJACK_FAST_MS = 500        # removed this fast = high confidence

_ACTION_TYPES = {"view_clicked", "view_scrolled", "view_focused", "content_changed"}


@dataclass(frozen=True)
class AxEvent:
    """One AccessibilityEvent as the on-device observer receives it."""
    t_ms: int
    type: str
    pkg: str
    by_user: bool = True     # for notif_removed: did the user dismiss it?


@dataclass
class ObserverContext:
    """What the observer knows locally about the live device, none of which is
    ever transmitted. `sensitivity` maps a foreground package to its bucketed
    target class (financial/messaging/other); `trusted` is the on-device
    allowlist of packages the user vouched for."""
    sensitivity: Dict[str, str] = field(default_factory=dict)
    trusted: Set[str] = field(default_factory=set)

    def target_class(self, pkg: Optional[str]) -> str:
        return self.sensitivity.get(pkg or "", "other")

    def is_sensitive(self, pkg: Optional[str]) -> bool:
        return self.target_class(pkg) in {"financial", "messaging"}


def _cov(values: List[float]) -> float:
    if len(values) < 2:
        return 1.0
    mean = statistics.mean(values)
    if mean <= 0:
        return 1.0
    return statistics.pstdev(values) / mean


def score_stream(events: List[AxEvent], ctx: ObserverContext) -> List[Dict]:
    """Score a live event stream → list of {code, facets} findings (wire shape).

    Empty list means nothing takeover-shaped was observed.
    """
    events = sorted(events, key=lambda e: e.t_ms)
    findings: List[Dict] = []
    foreground: Optional[str] = None

    # Interaction intervals accumulated only while a sensitive app is foreground.
    action_times: List[int] = []
    pending_otp: Optional[AxEvent] = None

    def flush_automation() -> None:
        nonlocal action_times
        if len(action_times) >= MIN_ACTION_EVENTS:
            intervals = [b - a for a, b in zip(action_times, action_times[1:])]
            if intervals:
                median = statistics.median(intervals)
                cov = _cov([float(i) for i in intervals])
                if median <= HUMAN_MIN_MEDIAN_MS:
                    conf = "high" if (median <= HIGH_CONF_MEDIAN_MS and cov <= LOW_COV) else "medium"
                    findings.append({
                        "code": "A11Y_AUTOMATION_ANOMALY",
                        "facets": {
                            "category": "a11y_auto_tap",
                            "confidence": conf,
                            "target": ctx.target_class(foreground),
                        },
                    })
        action_times = []

    for ev in events:
        if ev.type == "window_state_changed":
            # Foreground app changed — close out any automation run on the app
            # we were watching, then switch.
            flush_automation()
            foreground = ev.pkg

        elif ev.type == "window_added_overlay":
            # An overlay appeared. Attack iff it belongs to a different,
            # untrusted package while a sensitive app is foreground.
            if (
                ctx.is_sensitive(foreground)
                and ev.pkg != foreground
                and ev.pkg not in ctx.trusted
            ):
                findings.append({
                    "code": "OVERLAY_ATTACK_LIVE",
                    "facets": {
                        "confidence": "high",
                        "target": ctx.target_class(foreground),
                    },
                })

        elif ev.type in _ACTION_TYPES:
            if ctx.is_sensitive(foreground):
                action_times.append(ev.t_ms)

        elif ev.type == "notif_posted_otp":
            pending_otp = ev

        elif ev.type == "notif_removed":
            if (
                pending_otp is not None
                and not ev.by_user
                and 0 <= ev.t_ms - pending_otp.t_ms <= HIJACK_WINDOW_MS
            ):
                fast = ev.t_ms - pending_otp.t_ms <= HIJACK_FAST_MS
                findings.append({
                    "code": "NOTIF_HIJACK_LIVE",
                    "facets": {"confidence": "high" if fast else "medium"},
                })
            pending_otp = None

    flush_automation()
    return findings


# ── self-test: synthetic human vs. bot traces (no device needed) ─────────────
def _human_trace() -> List[AxEvent]:
    # Irregular, human-paced taps on a banking app: no automation finding.
    t = 0
    evs = [AxEvent(t, "window_state_changed", "com.bank.app")]
    for gap in (220, 640, 310, 900, 150, 500, 720, 400):
        t += gap
        evs.append(AxEvent(t, "view_clicked", "com.bank.app"))
    return evs


def _bot_trace() -> List[AxEvent]:
    # Machine-cadence automation driving the same banking app: high-conf finding.
    t = 0
    evs = [AxEvent(t, "window_state_changed", "com.bank.app")]
    for gap in (30, 32, 28, 31, 29, 30, 33, 27, 31, 30):
        t += gap
        evs.append(AxEvent(t, "view_clicked", "com.bank.app"))
    return evs


def _overlay_trace() -> List[AxEvent]:
    return [
        AxEvent(0, "window_state_changed", "com.bank.app"),
        AxEvent(50, "window_added_overlay", "com.evil.overlay"),
    ]


def _notif_hijack_trace() -> List[AxEvent]:
    return [
        AxEvent(0, "notif_posted_otp", "com.bank.app"),
        AxEvent(200, "notif_removed", "com.evil.reader", by_user=False),
    ]


def _notif_benign_trace() -> List[AxEvent]:
    # User reads and dismisses their own OTP notification a few seconds later.
    return [
        AxEvent(0, "notif_posted_otp", "com.bank.app"),
        AxEvent(4200, "notif_removed", "com.bank.app", by_user=True),
    ]


def selftest() -> int:
    ctx = ObserverContext(
        sensitivity={"com.bank.app": "financial"},
        trusted={"com.android.systemui", "com.bank.app"},
    )
    cases = {
        "human_taps": (_human_trace(), set()),
        "bot_autotap": (_bot_trace(), {"A11Y_AUTOMATION_ANOMALY"}),
        "overlay_attack": (_overlay_trace(), {"OVERLAY_ATTACK_LIVE"}),
        "notif_hijack": (_notif_hijack_trace(), {"NOTIF_HIJACK_LIVE"}),
        "notif_benign": (_notif_benign_trace(), set()),
    }
    failed = 0
    for name, (trace, expected_codes) in cases.items():
        out = score_stream(trace, ctx)
        got = {f["code"] for f in out}
        ok = got == expected_codes
        print(f"  {'ok  ' if ok else 'FAIL'} {name:16} -> {json.dumps(out)}")
        if not ok:
            print(f"        expected codes {expected_codes}, got {got}", file=sys.stderr)
            failed += 1

    # The bot case must specifically be HIGH confidence — the whole point.
    bot_out = score_stream(_bot_trace(), ctx)
    if not any(f["facets"].get("confidence") == "high" for f in bot_out):
        print("        bot auto-tap should be high confidence", file=sys.stderr)
        failed += 1

    print(f"\n{len(cases) - failed}/{len(cases)} live-observer cases correct")
    return 1 if failed else 0


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
