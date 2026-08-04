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
#   ./scripts/context.sh status               who holds the baton
#   ./scripts/context.sh pack                 bundle + encrypt -> context.enc
#   ./scripts/context.sh unpack               decrypt + restore
#   ./scripts/context.sh pack --with-secrets  also include .env  (SEE WARNING)
#   ./scripts/context.sh list                 show what a bundle contains
#
# BATON DISCIPLINE
#   context.enc is a single AES blob, so git cannot merge two versions of it —
#   a conflict forces you to discard one side whole, with no way to see what
#   you are throwing away. The workflow is therefore strictly one machine at a
#   time: pack and push before you leave, pull and unpack when you arrive.
#
#   Guards below make forgetting loud rather than silent. `pack` refuses when
#   the remote's bundle differs from yours, and `unpack` refuses when your
#   local files are newer than the bundle about to overwrite them. Both take
#   --force if you have decided which side wins.
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
# Locate the Claude memory directory for THIS project.
#
# Claude Code names each project folder after the working directory path with
# non-alphanumeric characters replaced by "-", so the name embeds the username
# and the full path. Hardcoding it works on exactly one machine: on any other,
# the restore would write into a directory Claude never reads, and would do so
# without any error — the worst kind of failure for a migration script.
#
# So derive it. Match on the project folder's own name, which travels with the
# repository, and fall back to creating the conventional path if no existing
# project directory matches.
resolve_mem() {
  local slug
  slug="$(basename "$ROOT" | tr -c '[:alnum:]' '-')"
  slug="${slug%-}"

  local d
  for d in "$CFG"/projects/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      *"$slug") echo "${d%/}/memory"; return 0 ;;
    esac
  done

  # Nothing matched — first run on this machine. Use the path Claude would
  # itself derive, so the directory is already correct once a session starts.
  local win
  win="$(cd "$ROOT" && pwd -W 2>/dev/null || pwd)"
  echo "$CFG/projects/$(printf '%s' "$win" | tr -c '[:alnum:]' '-')/memory"
}

MEM="$(resolve_mem)"

die() { echo "error: $*" >&2; exit 1; }

command -v gpg >/dev/null || die "gpg not found (Git Bash ships one; check PATH)"

# ── Baton guards ────────────────────────────────────────────────────────────
#
# The question these answer is not "is git behind" but the narrower "does the
# remote hold a DIFFERENT bundle than mine". Ordinary commits to code move HEAD
# without touching context.enc, and blocking on those would train you to reach
# for --force, which defeats the guard entirely.

BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"

# Populates REMOTE_STATE with one of: offline, no-upstream, same, differs
probe_remote() {
  REMOTE_STATE="offline"
  [ -n "$BRANCH" ] || return 0
  git -C "$ROOT" fetch --quiet origin "$BRANCH" 2>/dev/null || return 0
  git -C "$ROOT" rev-parse --verify --quiet "origin/$BRANCH" >/dev/null 2>&1 || {
    REMOTE_STATE="no-upstream"; return 0; }
  if git -C "$ROOT" diff --quiet HEAD "origin/$BRANCH" -- context.enc 2>/dev/null; then
    REMOTE_STATE="same"
  else
    REMOTE_STATE="differs"
  fi
}

# True when a tracked plaintext file has been edited since the bundle was made,
# i.e. there is local work the bundle does not contain.
local_is_newer() {
  [ -f "$BUNDLE" ] || return 0
  for f in CLAUDE.md ARCHITECTURE.md; do
    [ -f "$ROOT/$f" ] && [ "$ROOT/$f" -nt "$BUNDLE" ] && return 0
  done
  return 1
}

read_pass() {
  # A passphrase file exists for non-interactive callers: automation, and any
  # agent driving this script whose shell has no terminal to prompt on. The
  # file is its own confirmation — you can read back what you wrote — so the
  # double-entry check below is skipped in this mode.
  #
  # It is a deliberate trade: a passphrase briefly on disk in exchange for not
  # having to type it into a prompt. Delete the file afterwards; `pack` prints
  # a reminder, and .passphrase is gitignored so it cannot be committed.
  if [ -n "${PASSFILE:-}" ]; then
    [ -f "$PASSFILE" ] || die "passphrase file not found: $PASSFILE"
    PASS="$(head -n 1 "$PASSFILE" | tr -d '\r\n')"
    [ -n "$PASS" ] || die "passphrase file is empty: $PASSFILE"
    return 0
  fi

  # --pinentry-mode loopback keeps gpg from trying to open a GUI prompt, which
  # is unreliable under Git Bash on Windows.
  printf 'Passphrase: ' >&2
  read -r -s PASS
  printf '\n' >&2
  [ -n "$PASS" ] || die "empty passphrase"

  # Confirm when sealing, never when opening. A typo while packing produces a
  # bundle locked with a passphrase nobody knows, and it stays undiscovered
  # until someone tries to open it on another machine — by which point the
  # only copy of the context is inside it. Opening needs no confirmation: a
  # wrong passphrase there simply fails and costs nothing.
  if [ "${CONFIRM_PASS:-0}" = 1 ]; then
    printf 'Confirm    : ' >&2
    local again
    read -r -s again
    printf '\n' >&2
    [ "$PASS" = "$again" ] || die "passphrases do not match — nothing was written"
  fi
}

cmd_status() {
  probe_remote
  echo "branch        : ${BRANCH:-<none>}"

  if [ -f "$BUNDLE" ]; then
    echo "context.enc   : $(du -h "$BUNDLE" | cut -f1), packed $(date -r "$BUNDLE" '+%Y-%m-%d %H:%M')"
  else
    echo "context.enc   : absent"
  fi

  case "$REMOTE_STATE" in
    offline)     echo "remote        : unreachable — cannot tell who holds the baton" ;;
    no-upstream) echo "remote        : no upstream branch" ;;
    same)        echo "remote        : bundle matches yours" ;;
    differs)     echo "remote        : DIFFERENT bundle upstream" ;;
  esac

  echo ""
  if [ "$REMOTE_STATE" = "differs" ]; then
    echo "  The other machine holds the baton."
    echo "  ->  git pull  &&  ./scripts/context.sh unpack"
  elif local_is_newer; then
    echo "  You hold the baton, with unpacked local edits."
    echo "  ->  ./scripts/context.sh pack  &&  git add context.enc && git commit && git push"
  else
    echo "  You hold the baton. Nothing to pack."
  fi
}

cmd_pack() {
  local with_secrets=0 force=0
  local prev=""
  for a in "$@"; do
    case "$prev" in --passphrase-file) PASSFILE="$a" ;; esac
    case "$a" in
      --with-secrets) with_secrets=1 ;;
      --force)        force=1 ;;
    esac
    prev="$a"
  done

  probe_remote
  if [ "$REMOTE_STATE" = "differs" ] && [ "$force" = 0 ]; then
    echo "refusing to pack: the remote holds a different context.enc." >&2
    echo "" >&2
    echo "  The other machine packed since you last pulled. Packing now and" >&2
    echo "  pushing would collide, and the blob cannot be merged — resolving" >&2
    echo "  it means discarding one side entirely, unseen." >&2
    echo "" >&2
    echo "  Take the baton first:   git pull && ./scripts/context.sh unpack" >&2
    echo "  Or overrule this with:  ./scripts/context.sh pack --force" >&2
    exit 1
  fi
  [ "$REMOTE_STATE" = "offline" ] && \
    echo "  note: remote unreachable, packing without a baton check" >&2

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

  CONFIRM_PASS=1 read_pass
  tar -czf - -C "$staging" . \
    | gpg --batch --yes --symmetric --cipher-algo AES256 \
          --pinentry-mode loopback --passphrase-fd 3 \
          --output "$BUNDLE" 3<<<"$PASS"

  echo ""
  echo "packed -> context.enc ($(du -h "$BUNDLE" | cut -f1))"
  echo "commit it with: git add context.enc && git commit -m 'chore: sync context'"
  if [ -n "${PASSFILE:-}" ]; then
    echo ""
    echo "  Now delete the passphrase file:  rm '$PASSFILE'"
    echo "  It is gitignored, but it is still your passphrase sitting on disk."
  fi
}

cmd_unpack() {
  local force=0
  [ "${1:-}" = "--force" ] && force=1

  [ -f "$BUNDLE" ] || die "context.enc not found — git pull first"

  if local_is_newer && [ "$force" = 0 ]; then
    echo "refusing to unpack: your local files are newer than context.enc." >&2
    echo "" >&2
    echo "  You edited CLAUDE.md or ARCHITECTURE.md and never packed. Unpacking" >&2
    echo "  overwrites them in place, so those edits would be gone with no copy" >&2
    echo "  anywhere — they are gitignored, so git cannot recover them either." >&2
    echo "" >&2
    echo "  Keep your edits:      ./scripts/context.sh pack" >&2
    echo "  Or discard them with: ./scripts/context.sh unpack --force" >&2
    exit 1
  fi

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
      # Stamp the restored file with the bundle's own mtime. cp would otherwise
      # set it to now, making every freshly unpacked file look newer than the
      # bundle it came from — so the "you have unedited local work" guard would
      # fire immediately after every unpack. A guard that always cries wolf
      # teaches you to pass --force, which is worse than having no guard.
      touch -r "$BUNDLE" "$ROOT/$f"
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
  status) cmd_status ;;
  pack)   shift; cmd_pack "$@" ;;
  unpack) shift; cmd_unpack "${1:-}" ;;
  list)   cmd_list ;;
  *)
    sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
