"""
capability_profile.py — non-rooted (Tier 0) capability-profile extraction + scoring
====================================================================================

The non-rooted half of the novelty module (plan REVISION 2026-08-04). On a
non-rooted device the OS sandbox forbids watching another app *run*, so this
does NOT do dynamic behavioral detection. Instead it reads a service's declared
**capability profile** — the same fields Tier 0 can pull on-device from
`PackageManager` / `AccessibilityServiceInfo` with zero permissions — and scores
that profile against the account-takeover TTP fingerprints the agentic-RE
pipeline derives from re_pipeline/samples/.

This module operates on manifest/config XML so it can be developed and tested
offline against the sample source tree, with no built APK and no device. The
on-device Kotlin port (task B'3) reads the identical fields from:
  - Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES / ENABLED_NOTIFICATION_LISTENERS
  - AccessibilityServiceInfo.getCapabilities() / eventTypes / flags
  - PackageManager.getPackageInfo(..., GET_PERMISSIONS) for SYSTEM_ALERT_WINDOW
  - the package's installer source (the `src` facet), added on-device

Output categories and confidence map 1:1 onto findings.py's _BEHAVIOR_CATEGORY
and _CONFIDENCE facets for the A11Y_TAKEOVER_PROFILE (Tier 0) finding code.

The honest limit (baked into scoring): a *legitimate* accessibility tool
(TalkBack, a password manager) declares the same scary capabilities as a
trojan. Capability profile alone cannot separate them. What separates them is
(a) the CONFLUENCE of several takeover techniques in one package, and (b) the
installer source — a play/system-installed match is downgraded on-device via
the `src` facet. This module scores (a); it documents (b) as the on-device
downgrade rule rather than pretending manifest data settles it.

Usage:
    python3 capability_profile.py samples/*/     # profile + classify each sample
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import FrozenSet, List, Optional, Tuple
from xml.etree import ElementTree as ET

ANDROID_NS = "http://schemas.android.com/apk/res/android"


def _attr(el: ET.Element, name: str) -> Optional[str]:
    return el.get(f"{{{ANDROID_NS}}}{name}")


def _flag_set(raw: Optional[str]) -> FrozenSet[str]:
    """Android '|'-joined flag masks, e.g. 'typeWindowContentChanged|typeViewFocused'."""
    if not raw:
        return frozenset()
    return frozenset(part.strip() for part in raw.split("|") if part.strip())


@dataclass(frozen=True)
class CapabilityProfile:
    """The Tier-0-readable capability surface of one installed package."""
    package: str
    has_accessibility_service: bool = False
    can_retrieve_window_content: bool = False
    can_perform_gestures: bool = False
    a11y_event_types: FrozenSet[str] = field(default_factory=frozenset)
    a11y_flags: FrozenSet[str] = field(default_factory=frozenset)
    has_notification_listener: bool = False
    requests_overlay: bool = False  # declares SYSTEM_ALERT_WINDOW

    def takeover_techniques(self) -> List[str]:
        """The distinct account-takeover techniques this profile enables, as
        _BEHAVIOR_CATEGORY labels. Confluence of several is the strong signal."""
        techniques: List[str] = []
        # Auto-tap subsumes screen-read (it needs content retrieval too), so it
        # is reported as the single, more severe technique rather than both.
        if self.can_perform_gestures and self.can_retrieve_window_content:
            techniques.append("a11y_auto_tap")
        elif self.can_retrieve_window_content:
            techniques.append("a11y_screen_read")
        if self.requests_overlay:
            techniques.append("overlay_phish")
        if self.has_notification_listener:
            techniques.append("notif_intercept")
        return techniques


# Severity order for choosing the dominant reported category when several
# techniques are present. Auto-tap (acts on the victim's behalf) is the worst.
_TECHNIQUE_RANK = {
    "a11y_auto_tap": 3,
    "overlay_phish": 2,
    "notif_intercept": 1,
    "a11y_screen_read": 0,
}


def classify(profile: CapabilityProfile) -> Optional[Tuple[str, str]]:
    """Score a capability profile → (category, confidence), or None if nothing
    takeover-shaped is declared (no finding emitted).

    confidence scales with the number of confluent takeover techniques:
      1 technique  → "medium"   (a single scary capability; often benign)
      2+ techniques → "high"    (the confluence real trojans exhibit)
    On-device, a play/system `src` downgrades "high"→"medium" and "medium"→"low";
    that downgrade is applied where the src facet is known, not here.
    """
    techniques = profile.takeover_techniques()
    if not techniques:
        return None
    category = max(techniques, key=lambda t: _TECHNIQUE_RANK[t])
    confidence = "high" if len(techniques) >= 2 else "medium"
    return category, confidence


def extract(sample_main_dir: Path) -> CapabilityProfile:
    """Build a CapabilityProfile from a sample's src/main tree (its
    AndroidManifest.xml plus any res/xml accessibility-service config)."""
    manifest = sample_main_dir / "AndroidManifest.xml"
    root = ET.parse(manifest).getroot()

    package = _guess_package(root, sample_main_dir)
    permissions = {
        _attr(el, "name")
        for el in root.iter("uses-permission")
    }
    requests_overlay = "android.permission.SYSTEM_ALERT_WINDOW" in permissions

    has_a11y = False
    can_content = False
    can_gestures = False
    event_types: FrozenSet[str] = frozenset()
    a11y_flags: FrozenSet[str] = frozenset()
    has_notif = False

    for service in root.iter("service"):
        perm = _attr(service, "permission") or ""
        actions = {
            _attr(action, "name")
            for intent in service.iter("intent-filter")
            for action in intent.iter("action")
        }

        if "android.accessibilityservice.AccessibilityService" in actions:
            has_a11y = True
            cfg = _load_a11y_config(service, sample_main_dir)
            if cfg is not None:
                can_content = can_content or (_attr(cfg, "canRetrieveWindowContent") == "true")
                can_gestures = can_gestures or (_attr(cfg, "canPerformGestures") == "true")
                event_types = event_types | _flag_set(_attr(cfg, "accessibilityEventTypes"))
                a11y_flags = a11y_flags | _flag_set(_attr(cfg, "accessibilityFlags"))

        if (
            perm == "android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            or "android.service.notification.NotificationListenerService" in actions
        ):
            has_notif = True

    return CapabilityProfile(
        package=package,
        has_accessibility_service=has_a11y,
        can_retrieve_window_content=can_content,
        can_perform_gestures=can_gestures,
        a11y_event_types=event_types,
        a11y_flags=a11y_flags,
        has_notification_listener=has_notif,
        requests_overlay=requests_overlay,
    )


def _guess_package(root: ET.Element, sample_main_dir: Path) -> str:
    # Modern Gradle manifests carry no package attr (namespace is in
    # build.gradle). Fall back to the kotlin source path for a readable label.
    pkg = root.get("package")
    if pkg:
        return pkg
    kotlin = sample_main_dir / "kotlin"
    if kotlin.exists():
        for p in kotlin.rglob("*.kt"):
            rel = p.relative_to(kotlin).parent
            if rel.parts:
                return ".".join(rel.parts)
    return sample_main_dir.parent.name


def _load_a11y_config(service: ET.Element, sample_main_dir: Path) -> Optional[ET.Element]:
    for meta in service.iter("meta-data"):
        if _attr(meta, "name") == "android.accessibilityservice":
            resource = _attr(meta, "resource") or ""
            xml_name = resource.split("/")[-1]  # "@xml/foo" → "foo"
            cfg_path = sample_main_dir / "res" / "xml" / f"{xml_name}.xml"
            if cfg_path.exists():
                return ET.parse(cfg_path).getroot()
    return None


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sample_dirs", nargs="+")
    args = parser.parse_args(argv)

    correct = total = 0
    for raw in args.sample_dirs:
        d = Path(raw)
        main_dir = d / "src" / "main"
        if not (main_dir / "AndroidManifest.xml").exists():
            print(f"skip {d}: no src/main/AndroidManifest.xml", file=sys.stderr)
            continue

        profile = extract(main_dir)
        result = classify(profile)
        category, confidence = result if result else (None, None)

        row = {
            "sample": d.name,
            "techniques": profile.takeover_techniques(),
            "category": category,
            "confidence": confidence,
        }
        print(json.dumps(row))

        ttp_path = d / "ttp.json"
        if ttp_path.exists():
            expected = json.loads(ttp_path.read_text())["category"]
            total += 1
            if category == expected:
                correct += 1
            else:
                print(f"  MISMATCH {d.name}: got {category!r}, expected {expected!r}",
                      file=sys.stderr)

    if total:
        print(f"\ncapability-profile recovery: {correct}/{total} categories correct")
        return 0 if correct == total else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
