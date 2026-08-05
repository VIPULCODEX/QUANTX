"""
findings.py — QuantX Finding schema + privacy gate
===================================================

The contract between on-device detection and the cloud advisor.

Core invariant
--------------
    Raw telemetry never leaves the device.

The device detects locally and emits a *Finding*: a canonical code plus bucketed,
non-identifying facets. No package names, no SSIDs, no file paths, no IPs, no log
lines — ever. This module is the enforcement point, and it is deliberately
allowlist-based: anything not explicitly declared is dropped rather than passed.

Three properties worth understanding before editing:

  1. Unknown codes are REJECTED, not passed through. An unrecognised code is an
     exfiltration channel (`code = "leak:<secret>"`), so it never survives.
  2. Severity comes from the SERVER-SIDE registry, never from the client. A
     compromised client cannot inflate or suppress severity.
  3. Counts are BUCKETED ("2-5"), never exact. Exact counts across several
     findings fingerprint a device; buckets defeat that while preserving the
     signal the advisor actually needs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple


# ─────────────────────────────────────────────────────────────────────────────
# Enums
# ─────────────────────────────────────────────────────────────────────────────
class Severity(str, Enum):
    INFO = "info"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class Tier(int, Enum):
    SANDBOX = 0   # every user, no setup, no tradeoff
    SHIZUKU = 1   # opt-in diagnostic session, needs Developer Options
    ROOT = 2      # already-rooted devices only


# ─────────────────────────────────────────────────────────────────────────────
# Facet specification
# ─────────────────────────────────────────────────────────────────────────────
# A facet is a small, non-identifying qualifier. Only three shapes are allowed —
# all of them closed sets. There is intentionally no free-text facet kind, so
# there is no code path by which arbitrary strings can reach the network.

COUNT_BUCKETS: Tuple[Tuple[int, str], ...] = (
    (0, "0"),
    (1, "1"),
    (5, "2-5"),
    (20, "6-20"),
)
COUNT_BUCKET_OVERFLOW = "20+"


def bucket_count(n: int) -> str:
    """Map an exact count to a coarse bucket. Exact counts fingerprint devices."""
    if not isinstance(n, bool) and isinstance(n, int) and n >= 0:
        for upper, label in COUNT_BUCKETS:
            if n <= upper:
                return label
        return COUNT_BUCKET_OVERFLOW
    raise ValueError("count facet requires a non-negative int")


@dataclass(frozen=True)
class FacetSpec:
    """Declares one permitted facet. `values` is required for ENUM facets."""

    kind: str                              # "enum" | "count" | "bool"
    values: frozenset = frozenset()

    def coerce(self, raw: Any) -> Optional[Any]:
        """Return a safe value, or None if the input is not representable.

        Returning None means "drop this facet" — never "pass it through".
        """
        if self.kind == "bool":
            return bool(raw) if isinstance(raw, bool) else None

        if self.kind == "count":
            try:
                return bucket_count(raw)
            except (ValueError, TypeError):
                return None

        if self.kind == "enum":
            # Membership check against a closed set is what makes this safe:
            # an attacker-supplied string can only ever match a value we chose.
            return raw if isinstance(raw, str) and raw in self.values else None

        return None


# Reusable facet shapes
_COUNT = FacetSpec("count")
_SRC = FacetSpec("enum", frozenset({"play", "sideload", "system", "unknown"}))
_HOOK_FRAMEWORK = FacetSpec("enum", frozenset({"frida", "xposed", "lsposed", "unknown"}))
_INTEGRITY = FacetSpec("enum", frozenset({"strong", "device", "basic", "none"}))
_ROOT_METHOD = FacetSpec("enum", frozenset({"magisk", "other", "unknown"}))
# Categories are the closed taxonomy produced by the offline agentic-RE pipeline
# (re_pipeline/) — one label per reproduced TTP, plus "unknown" for anything the
# on-device scorer flags outside that taxonomy. Never a free-text description.
_BEHAVIOR_CATEGORY = FacetSpec("enum", frozenset({
    "a11y_screen_read", "a11y_auto_tap", "overlay_phish", "notif_intercept", "unknown",
}))
_CONFIDENCE = FacetSpec("enum", frozenset({"low", "medium", "high"}))
# Bucketed *class* of the app an attack targeted — never the app's identity.
# Lets the advisor say "protect your banking app" without a package name.
_TARGET_CLASS = FacetSpec("enum", frozenset({"financial", "messaging", "other"}))


# ─────────────────────────────────────────────────────────────────────────────
# Finding registry
# ─────────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class CodeSpec:
    tier: Tier
    severity: Severity
    title: str
    facets: Dict[str, FacetSpec] = field(default_factory=dict)


REGISTRY: Dict[str, CodeSpec] = {
    # ── Tier 0 — sandbox / RASP ──────────────────────────────────────────────
    "SELF_HOOK_DETECTED": CodeSpec(
        Tier.SANDBOX, Severity.CRITICAL,
        "Instrumentation framework hooking this app",
        {"framework": _HOOK_FRAMEWORK},
    ),
    "SELF_DEBUGGER_ATTACHED": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "A debugger is attached to this app",
    ),
    "SELF_SIGNATURE_MISMATCH": CodeSpec(
        Tier.SANDBOX, Severity.CRITICAL,
        "App signature does not match the official build",
    ),
    "SELF_NATIVE_TAMPER": CodeSpec(
        Tier.SANDBOX, Severity.CRITICAL,
        "Native library modified or inline-hooked",
    ),
    "A11Y_UNTRUSTED_SERVICE": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "Untrusted app holds Accessibility Service access",
        {"count": _COUNT, "src": _SRC},
    ),
    "NOTIF_LISTENER_UNTRUSTED": CodeSpec(
        Tier.SANDBOX, Severity.MEDIUM,
        "Untrusted app can read all notifications",
        {"count": _COUNT, "src": _SRC},
    ),
    "INTEGRITY_VERDICT_FAIL": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "Play Integrity attestation did not pass",
        {"verdict": _INTEGRITY},
    ),
    "DEV_OPTIONS_ENABLED": CodeSpec(
        Tier.SANDBOX, Severity.MEDIUM,
        "Developer Options are enabled",
    ),
    "EMULATOR_DETECTED": CodeSpec(
        Tier.SANDBOX, Severity.LOW,
        "App is running on an emulator",
    ),
    "A11Y_TAKEOVER_PROFILE": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "An accessibility/notification service's declared capabilities match a "
        "known account-takeover technique",
        {"category": _BEHAVIOR_CATEGORY, "confidence": _CONFIDENCE},
    ),

    # ── Tier 0 — Live Attack Observer (opt-in accessibility grant; §Mode 2) ───
    # Dynamic, cross-app, non-root: caught from the live system-wide event
    # stream, not by touching another process. QuantX's own a11y grant is
    # itself reported (A11Y_UNTRUSTED_SERVICE-style self-flagging).
    "OVERLAY_ATTACK_LIVE": CodeSpec(
        Tier.SANDBOX, Severity.CRITICAL,
        "An untrusted overlay was drawn over a sensitive app in real time",
        {"confidence": _CONFIDENCE, "target": _TARGET_CLASS},
    ),
    "A11Y_AUTOMATION_ANOMALY": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "Non-human automation was seen driving a sensitive app",
        {"category": _BEHAVIOR_CATEGORY, "confidence": _CONFIDENCE, "target": _TARGET_CLASS},
    ),
    "NOTIF_HIJACK_LIVE": CodeSpec(
        Tier.SANDBOX, Severity.HIGH,
        "A one-time-code notification was intercepted by a background listener",
        {"confidence": _CONFIDENCE},
    ),
    "NET_APP_EGRESS_ANOMALY": CodeSpec(
        Tier.SANDBOX, Severity.MEDIUM,
        "An app sent an unusual burst of data",
        {"confidence": _CONFIDENCE},
    ),

    # ── Tier 1 — Shizuku ─────────────────────────────────────────────────────
    "OVERLAY_HOLDER_UNTRUSTED": CodeSpec(
        Tier.SHIZUKU, Severity.HIGH,
        "Untrusted app can draw over other apps",
        {"count": _COUNT, "src": _SRC},
    ),
    "PKG_UNKNOWN_INSTALLER": CodeSpec(
        Tier.SHIZUKU, Severity.MEDIUM,
        "Apps installed from an unrecognised source",
        {"count": _COUNT},
    ),
    "DEVICE_ADMIN_UNTRUSTED": CodeSpec(
        Tier.SHIZUKU, Severity.HIGH,
        "Untrusted app holds Device Admin rights",
        {"count": _COUNT},
    ),
    "NET_SUSPICIOUS_EGRESS": CodeSpec(
        Tier.SHIZUKU, Severity.MEDIUM,
        "Unexpected outbound network activity",
        {"count": _COUNT},
    ),
    "WIRELESS_DEBUG_ENABLED": CodeSpec(
        Tier.SHIZUKU, Severity.MEDIUM,
        "Wireless debugging is enabled",
    ),

    # ── Tier 2 — root ────────────────────────────────────────────────────────
    "DEVICE_ROOTED": CodeSpec(
        Tier.ROOT, Severity.MEDIUM,
        "Device is rooted",
        {"method": _ROOT_METHOD},
    ),
    "XPROC_INJECTED_LIB": CodeSpec(
        Tier.ROOT, Severity.CRITICAL,
        "Injected library found in another app's process",
        {"count": _COUNT},
    ),
    "XPROC_ANON_EXEC": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "Anonymous executable memory in another process",
        {"count": _COUNT},
    ),
    "SYS_PARTITION_MODIFIED": CodeSpec(
        Tier.ROOT, Severity.CRITICAL,
        "System partition integrity check failed",
    ),
    "SYS_PRIV_APP_UNKNOWN": CodeSpec(
        Tier.ROOT, Severity.CRITICAL,
        "Unrecognised privileged system app",
        {"count": _COUNT},
    ),
    "BOOT_PERSISTENCE_UNKNOWN": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "Unrecognised boot-persistence entry",
        {"count": _COUNT},
    ),
    "NET_UNATTRIBUTED_CONN": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "Network connection with no attributable process",
        {"count": _COUNT},
    ),
    "SELINUX_PERMISSIVE": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "SELinux is not enforcing",
    ),
    "DM_VERITY_DISABLED": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "Verified boot (dm-verity) is disabled",
    ),
    "XPROC_BEHAVIORAL_ANOMALY": CodeSpec(
        Tier.ROOT, Severity.HIGH,
        "Another app is behaving like known account-takeover malware",
        {"category": _BEHAVIOR_CATEGORY, "confidence": _CONFIDENCE},
    ),
}


# ─────────────────────────────────────────────────────────────────────────────
# Finding
# ─────────────────────────────────────────────────────────────────────────────
@dataclass(frozen=True)
class Finding:
    code: str
    severity: Severity
    tier: Tier
    facets: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "code": self.code,
            "sev": self.severity.value,
            "tier": int(self.tier),
            "facets": dict(self.facets),
        }

    def cache_key(self) -> str:
        """Stable key for advice caching. Because facets are closed-set, the
        keyspace is small and the cache hit rate is high — which is what keeps
        most scans from ever reaching the LLM."""
        parts = ",".join(f"{k}={self.facets[k]}" for k in sorted(self.facets))
        return f"{self.code}|{self.severity.value}|{parts}"


class GateError(ValueError):
    """Raised when input cannot be represented as a valid Finding."""


# ─────────────────────────────────────────────────────────────────────────────
# The privacy gate
# ─────────────────────────────────────────────────────────────────────────────
def sanitize_finding(raw: Any) -> Finding:
    """Convert untrusted client input into a Finding, or raise GateError.

    This is the ONLY supported way to construct a Finding from client input.
    Everything not explicitly declared in REGISTRY is discarded.
    """
    if not isinstance(raw, dict):
        raise GateError("finding must be an object")

    code = raw.get("code")
    if not isinstance(code, str):
        raise GateError("finding.code must be a string")

    spec = REGISTRY.get(code)
    if spec is None:
        # Deliberately strict: an unknown code is an exfiltration channel.
        raise GateError(f"unknown finding code: {code[:32]!r}")

    # Severity and tier are authoritative from the registry — never client input.
    clean: Dict[str, Any] = {}
    submitted = raw.get("facets")
    if isinstance(submitted, dict):
        for name, facet_spec in spec.facets.items():
            if name in submitted:
                value = facet_spec.coerce(submitted[name])
                if value is not None:
                    clean[name] = value

    return Finding(code=code, severity=spec.severity, tier=spec.tier, facets=clean)


def sanitize_batch(raw_items: Any) -> Tuple[List[Finding], List[str]]:
    """Sanitize a list of findings. Returns (accepted, rejection_reasons).

    A bad finding never poisons the batch — it is dropped and reported, so a
    partially-broken client still gets useful advice for what it got right.
    """
    if not isinstance(raw_items, list):
        raise GateError("findings must be a list")
    if len(raw_items) > 100:
        raise GateError("too many findings in one batch (max 100)")

    accepted: List[Finding] = []
    rejected: List[str] = []
    for item in raw_items:
        try:
            accepted.append(sanitize_finding(item))
        except GateError as exc:
            rejected.append(str(exc))
    return accepted, rejected


def assert_no_leak(payload: Dict[str, Any]) -> None:
    """Belt-and-braces check run before anything is sent to the LLM.

    sanitize_finding() should make this unreachable. It exists because the
    privacy claim is the product, and a single regression in the gate would
    silently break it — so we verify the shape independently of the code that
    produced it.
    """
    allowed_top = {"code", "sev", "tier", "facets"}
    extra = set(payload) - allowed_top
    if extra:
        raise GateError(f"unexpected keys in outbound payload: {sorted(extra)}")

    spec = REGISTRY.get(payload.get("code", ""))
    if spec is None:
        raise GateError("outbound payload has unknown code")

    valid_buckets = {label for _, label in COUNT_BUCKETS} | {COUNT_BUCKET_OVERFLOW}

    for name, value in payload.get("facets", {}).items():
        facet_spec = spec.facets.get(name)
        if facet_spec is None:
            raise GateError(f"undeclared facet in outbound payload: {name}")

        # By this point a count facet is already a bucket label, not an integer,
        # so it is checked against the bucket set rather than re-coerced.
        if facet_spec.kind == "count":
            if value not in valid_buckets:
                raise GateError(f"unbucketed count facet: {name}")
        elif facet_spec.kind == "bool":
            if not isinstance(value, bool):
                raise GateError(f"non-bool value for bool facet: {name}")
        elif facet_spec.kind == "enum":
            if value not in facet_spec.values:
                raise GateError(f"invalid enum value for facet: {name}")
        else:
            raise GateError(f"unknown facet kind for {name}")


# ─────────────────────────────────────────────────────────────────────────────
# Remediation playbooks
# ─────────────────────────────────────────────────────────────────────────────
# These are the offline fallback AND the seed corpus for PEFT training
# (finding code -> remediation). The model must learn these natively, because at
# inference time it receives no device context — only the code.

PLAYBOOKS: Dict[str, Dict[str, Any]] = {
    "SELF_HOOK_DETECTED": {
        "why": "A hooking framework can read and rewrite anything this app does, "
               "including what you type into it.",
        "steps": [
            "Close this app now and do not enter passwords or OTPs into it.",
            "Uninstall any instrumentation or 'app modding' tools on the device.",
            "If you did not install such a tool yourself, treat the device as compromised.",
            "Reinstall this app from the official store after cleaning up.",
        ],
    },
    "SELF_SIGNATURE_MISMATCH": {
        "why": "This build was not signed by the official developer, so it is a "
               "repackaged copy and may contain added malicious code.",
        "steps": [
            "Uninstall this app immediately.",
            "Reinstall only from the official app store.",
            "Change any password you entered into this copy.",
        ],
    },
    "SELF_NATIVE_TAMPER": {
        "why": "A native library inside this app has been modified or hooked in "
               "memory, so the app's own security checks can no longer be trusted "
               "to report honestly.",
        "steps": [
            "Stop using this app for anything sensitive.",
            "Uninstall it and reinstall from the official store.",
            "If the warning returns on a clean install, the device itself is compromised.",
        ],
    },
    "SYS_PARTITION_MODIFIED": {
        "why": "The read-only system partition does not match its expected state. "
               "Something has altered the OS itself, below the level any app can clean.",
        "steps": [
            "Do not use this device for banking, payments, or work accounts.",
            "A factory reset will not fix a modified system partition.",
            "Reflash official firmware from the device vendor, or have the device serviced.",
        ],
    },
    "A11Y_UNTRUSTED_SERVICE": {
        "why": "Accessibility access lets an app read everything on screen and tap "
               "on your behalf. It is the single most abused permission on Android "
               "and the primary mechanism used by banking trojans.",
        "steps": [
            "Open Settings > Accessibility > Downloaded apps.",
            "Turn off access for anything you do not specifically rely on.",
            "Uninstall any app you do not recognise that requested it.",
            "If a banking app is installed, check its transaction history.",
        ],
    },
    "NOTIF_LISTENER_UNTRUSTED": {
        "why": "Notification access exposes OTP codes and message previews to that app.",
        "steps": [
            "Open Settings > Notifications > Device & app notifications.",
            "Revoke access for anything unrecognised.",
        ],
    },
    "DEV_OPTIONS_ENABLED": {
        "why": "Developer Options widen the device's attack surface, including "
               "debug interfaces that malware on the device can try to abuse.",
        "steps": [
            "If you are not actively developing or debugging, turn Developer Options off.",
            "Settings > System > Developer options > toggle off.",
        ],
    },
    "OVERLAY_HOLDER_UNTRUSTED": {
        "why": "Draw-over-other-apps allows a fake screen to be layered over a real "
               "one to capture what you type (tapjacking).",
        "steps": [
            "Open Settings > Apps > Special app access > Display over other apps.",
            "Revoke it for anything you do not recognise.",
        ],
    },
    "DEVICE_ROOTED": {
        "why": "Root disables parts of Android's security model, including verified "
               "boot. This is expected if you rooted the device intentionally.",
        "steps": [
            "If you did not root this device yourself, treat it as compromised.",
            "Avoid banking and payment apps on a rooted device.",
        ],
    },
    "XPROC_INJECTED_LIB": {
        "why": "Another app on this device has code injected into it by something "
               "else — a strong indicator of active malware, not just risky settings.",
        "steps": [
            "Do not open banking or payment apps until this is resolved.",
            "Review recently installed apps and remove anything unfamiliar.",
            "Back up your data and consider a factory reset.",
        ],
    },
    "SYS_PRIV_APP_UNKNOWN": {
        "why": "An unrecognised app holds privileged system rights. Pre-installed "
               "privileged malware cannot be removed by normal uninstall.",
        "steps": [
            "Do not enter sensitive credentials on this device.",
            "A factory reset may not remove system-partition components.",
            "Consider reflashing official firmware from the vendor.",
        ],
    },
    "SELINUX_PERMISSIVE": {
        "why": "SELinux is the kernel-level policy that contains a compromised app. "
               "Permissive mode means those containment rules are logged, not enforced.",
        "steps": [
            "Set SELinux back to enforcing if you changed it deliberately.",
            "If you did not change it, treat the device as compromised.",
        ],
    },
    "A11Y_TAKEOVER_PROFILE": {
        "why": "An app that holds accessibility or notification access declares "
               "the exact capabilities banking trojans use to take over an "
               "account — reading the whole screen, tapping on your behalf, "
               "drawing over other apps, or intercepting one-time codes. This "
               "is stronger than 'an untrusted app has accessibility': the app's "
               "own manifest matches a known attack profile. A legitimate tool "
               "(a screen reader, a password manager) can look similar, so "
               "confirm you installed it on purpose before trusting it.",
        "steps": [
            "Do not enter banking or payment credentials until you have checked this.",
            "Open Settings > Accessibility > Downloaded apps and Settings > "
            "Notifications > Device & app notifications.",
            "If you do not recognise the flagged app or did not enable it "
            "deliberately, turn its access off and uninstall it.",
            "If it is a tool you rely on (screen reader, automation, password "
            "manager), this is expected — leave it on.",
        ],
    },
    "OVERLAY_ATTACK_LIVE": {
        "why": "Right now, an untrusted app is drawing a screen on top of a "
               "sensitive app you were using. This is the tapjacking technique: "
               "what you see and tap may belong to the attacker's fake screen, "
               "not the real app underneath. This was caught as it happened, "
               "not merely as a risky setting.",
        "steps": [
            "Stop entering anything — do not type passwords, PINs, or codes now.",
            "Leave the current app: press Home, then reopen the real app fresh.",
            "Open Settings > Apps > Special app access > Display over other apps "
            "and turn it off for anything you do not recognise.",
            "Uninstall the unrecognised app, then check your account activity.",
        ],
    },
    "A11Y_AUTOMATION_ANOMALY": {
        "why": "Something was operating a sensitive app at a speed and rhythm a "
               "human does not — automated taps and navigation, the way a "
               "banking trojan drives a transfer on the victim's behalf. This is "
               "a live-behavior signal, observed while the app was in use.",
        "steps": [
            "Take control: interact with the phone to interrupt the automation.",
            "Open Settings > Accessibility and turn off any service you did not "
            "deliberately enable.",
            "Uninstall the app behind it and review recent account transactions.",
            "If you cannot regain control, power the device off.",
        ],
    },
    "NOTIF_HIJACK_LIVE": {
        "why": "A one-time security code arrived and was cleared away by a "
               "background app before you could act on it — the interception "
               "step that lets an attacker complete a login or transfer.",
        "steps": [
            "Assume an account is under active attack: change that account's "
            "password from a different, trusted device now.",
            "Open Settings > Notifications > Device & app notifications and "
            "revoke notification access for anything unrecognised.",
            "Uninstall the app that intercepted it and review recent activity.",
        ],
    },
    "NET_APP_EGRESS_ANOMALY": {
        "why": "An app sent out an unusually large burst of data. On its own "
               "this can be normal (a backup, an upload), but paired with other "
               "warnings it can mean information is being exfiltrated.",
        "steps": [
            "If you were not uploading or backing up, note which app it was.",
            "Restrict its background data, or uninstall it if unrecognised.",
            "Re-scan; if other warnings accompany this, treat it as urgent.",
        ],
    },
    "XPROC_BEHAVIORAL_ANOMALY": {
        "why": "An on-device behavioral monitor saw another app's live syscall "
               "pattern match known account-takeover techniques — automating taps "
               "through accessibility access, drawing phishing overlays, or "
               "intercepting one-time codes. This is a live-behavior signal, not "
               "just a static permission or file check.",
        "steps": [
            "Do not enter banking or payment credentials on this device right now.",
            "Open Settings > Accessibility and Settings > Notifications and revoke "
            "access for anything unfamiliar.",
            "Review recently installed apps and remove anything you do not recognise.",
            "If the warning persists after removing suspicious apps, treat the "
            "device as compromised and avoid sensitive transactions until it is reset.",
        ],
    },
}


def offline_advice(finding: Finding) -> Optional[Dict[str, Any]]:
    """Local remediation, no network. Used when offline, when the LLM is
    unavailable, and as the ground truth the PEFT model is trained against."""
    book = PLAYBOOKS.get(finding.code)
    if book is None:
        return None
    spec = REGISTRY[finding.code]
    return {
        "code": finding.code,
        "title": spec.title,
        "severity": finding.severity.value,
        "why": book["why"],
        "steps": list(book["steps"]),
    }


def registry_summary() -> Dict[str, Any]:
    """Introspection for docs, tests, and training-set generation."""
    by_tier: Dict[int, List[str]] = {0: [], 1: [], 2: []}
    for code, spec in REGISTRY.items():
        by_tier[int(spec.tier)].append(code)
    return {
        "total_codes": len(REGISTRY),
        "by_tier": {k: sorted(v) for k, v in by_tier.items()},
        "with_playbooks": sorted(PLAYBOOKS),
        "missing_playbooks": sorted(set(REGISTRY) - set(PLAYBOOKS)),
    }
