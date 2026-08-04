#!/usr/bin/env bash
#
# Encrypted context sync for QuantX.
#
# The problem this solves: the working context that makes a new machine useful
# — CLAUDE.md, ARCHITECTURE.md, the Claude memory directory — is exactly the
# material that should not sit in plaintext on a public GitHub repository. So
# it travels as a single AES-256 blob that only holders of the passphrase can
# read. GitHub stores it; GitHub cannot read it.
#
#   ./scripts/context.sh pack                 bundle + encrypt -> context.enc
#   ./scripts/context.sh unpack               decrypt + restore
#   ./scripts/context.sh pack --with-secrets  also include .env  (SEE WARNING)
#   ./scripts/context.sh list                 show what a bundle contains
#
# HONEST LIMITS
#   * "Only my devices" is achievable. "Only this device" is not — whatever
#     decrypts the bundle must exist wherever you want to read it.
#   * Publishing ciphertext is irreversible. Once a commit is pushed, that blob
#     is public forever and offline brute force has unlimited time. The only
#     thing standing between it and a reader is passphrase strength, so use a
#     long one — four or five unrelated words beat a short complex string.
#   * --with-secrets puts your API keys in that permanent blob. Use it only if
#     the remote is a PRIVATE repository, so the passphrase is your second line
#     of defence rather than your only one.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/context.enc"

# The Claude config directory holds the memory files. Honour CLAUDE_CONFIG_DIR
# if it has been redirected, otherwise fall back to the default location.
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECT_KEY="c--Users-Asus--gemini-antigravity-scratch-New-folder"
MEM="$CFG/projects/$PROJECT_KEY/memory"

die() { echo "error: $*" >&2; exit 1; }

command -v gpg >/dev/null || die "gpg not found (Git Bash ships one; check PATH)"

read_pass() {
  # --pinentry-mode loopback keeps gpg from trying to open a GUI prompt, which
  # is unreliable under Git Bash on Windows.
  printf 'Passphrase: ' >&2
  read -r -s PASS
  printf '\n' >&2
  [ -n "$PASS" ] || die "empty passphrase"
}

cmd_pack() {
  local with_secrets=0
  [ "${1:-}" = "--with-secrets" ] && with_secrets=1

  local staging
  staging="$(mktemp -d)"
  # Expanded now, not at trap time: $staging is function-local, so a deferred
  # expansion resolves to nothing at EXIT and trips `set -u`.
  trap "rm -rf '$staging'" EXIT

  local added=0

  for f in CLAUDE.md ARCHITECTURE.md; do
    if [ -f "$ROOT/$f" ]; then
      cp "$ROOT/$f" "$staging/$f"
      echo "  + $f"
      added=$((added + 1))
    fi
  done

  if [ -d "$MEM" ]; then
    mkdir -p "$staging/memory"
    cp "$MEM"/*.md "$staging/memory/" 2>/dev/null || true
    local n
    n="$(find "$staging/memory" -name '*.md' | wc -l)"
    echo "  + memory/ ($n files)"
    added=$((added + n))
  else
    echo "  ! memory dir not found at $MEM — skipping" >&2
  fi

  if [ "$with_secrets" = 1 ]; then
    if [ -f "$ROOT/cybersecurity_friend/.env" ]; then
      mkdir -p "$staging/secrets"
      cp "$ROOT/cybersecurity_friend/.env" "$staging/secrets/.env"
      echo "  + cybersecurity_friend/.env  <-- SECRETS INCLUDED"
      echo ""
      echo "  WARNING: this bundle now contains API keys. Push it to a PRIVATE"
      echo "  remote only. On a public remote the ciphertext is permanent and"
      echo "  the passphrase becomes the sole protection, forever."
      echo ""
      added=$((added + 1))
    else
      echo "  ! --with-secrets given but no .env found" >&2
    fi
  fi

  [ "$added" -gt 0 ] || die "nothing to pack"

  read_pass
  tar -czf - -C "$staging" . \
    | gpg --batch --yes --symmetric --cipher-algo AES256 \
          --pinentry-mode loopback --passphrase-fd 3 \
          --output "$BUNDLE" 3<<<"$PASS"

  echo ""
  echo "packed -> context.enc ($(du -h "$BUNDLE" | cut -f1))"
  echo "commit it with: git add context.enc && git commit -m 'chore: sync context'"
}

cmd_unpack() {
  [ -f "$BUNDLE" ] || die "context.enc not found — git pull first"
  read_pass

  local staging
  staging="$(mktemp -d)"
  # Expanded now, not at trap time: $staging is function-local, so a deferred
  # expansion resolves to nothing at EXIT and trips `set -u`.
  trap "rm -rf '$staging'" EXIT

  gpg --batch --yes --decrypt --pinentry-mode loopback \
      --passphrase-fd 3 "$BUNDLE" 3<<<"$PASS" \
    | tar -xzf - -C "$staging" \
    || die "decryption failed — wrong passphrase, or the bundle is corrupt"

  for f in CLAUDE.md ARCHITECTURE.md; do
    if [ -f "$staging/$f" ]; then
      cp "$staging/$f" "$ROOT/$f"
      echo "  -> $f"
    fi
  done

  if [ -d "$staging/memory" ]; then
    mkdir -p "$MEM"
    cp "$staging/memory"/*.md "$MEM/" 2>/dev/null || true
    echo "  -> $MEM"
  fi

  if [ -f "$staging/secrets/.env" ]; then
    cp "$staging/secrets/.env" "$ROOT/cybersecurity_friend/.env"
    echo "  -> cybersecurity_friend/.env"
  fi

  echo ""
  echo "unpacked. Plaintext files are gitignored and stay local."
}

cmd_list() {
  [ -f "$BUNDLE" ] || die "context.enc not found"
  read_pass
  gpg --batch --yes --decrypt --pinentry-mode loopback \
      --passphrase-fd 3 "$BUNDLE" 3<<<"$PASS" | tar -tzf -
}

case "${1:-}" in
  pack)   shift; cmd_pack "${1:-}" ;;
  unpack) cmd_unpack ;;
  list)   cmd_list ;;
  *)
    sed -n '3,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
