# QuantX

An Android security app that inspects the phone it runs on and asks a cloud
assistant what to do about what it finds, without telling the assistant anything
about the device.

It targets the case root detectors miss: a phone that is unmodified (locked
bootloader, no root, verified boot intact) but controlled by an attacker because
its owner granted an accessibility service permission. That is how banking
trojans such as Anatsa, Octo, Cerberus and Xenomorph operate.

## How the privacy boundary works

- The app runs its checks on the device (Tier 0 detector in Kotlin) and the
  phishing check on the device as well.
- Only canonical finding codes with a few closed-set facets leave the phone.
  No app names, package ids, network names, file paths or logs.
- `toWire()` in `cyber_intel_app/lib/services/scan_service.dart` is the single
  place a request body is built, and it cannot emit raw evidence.
- The server validates every code and facet against a registry
  (`cybersecurity_friend/findings.py`); unknown codes are rejected. Severity and
  tier are decided by the server, never accepted from the client.
- **What was sent** (Settings) shows the last requests exactly as transmitted,
  with an upper bound on the bits each finding can carry, and a **Copy log**
  button.
- Counts are sent as exact integers and are bucketed by the server before they
  reach the model.

## Layout

| Path | What it is |
| --- | --- |
| `cyber_intel_app/` | Flutter app (Dart) and the Tier 0 detector (Kotlin) |
| `cybersecurity_friend/` | FastAPI backend: gate, playbooks, assistant, hardening |
| `.github/workflows/` | CI: APK build, release on tag, backend sync |

## Tests

```bash
cd cybersecurity_friend && pip install -r requirements.txt pytest && pytest -q
cd cyber_intel_app && flutter test
```

## Releases

Pushing a tag `vX.Y.Z` builds and publishes the APK (`flutter_release.yml`).

## Status

Research prototype. The backend model is a hosted LLM; keys are read from the
environment only. See the threat model before relying on it.
