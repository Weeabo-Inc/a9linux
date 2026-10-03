#!/usr/bin/env bash
# a9linux/qemu/qemu-env.sh — resolve this harness's paths in ONE place.
#
# WHY THIS FILE EXISTS. The harness was written on Windows/WSL, where the
# repository lived on drvfs at `/mnt/e/Reverseing/Arlo` and the scratch tree at
# `/opt/a9qemu`, and ~20 scripts hardcoded both. The workstream has since moved to
# bare-metal Linux, where neither path exists. Rather than hardcode a second set
# of paths, every script sources this file:
#
#   SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SELF_DIR/qemu-env.sh"
#
# and then uses $Q (this directory), $W (repo root) and $STAGE. The defaults are
# the WSL ones, so the old host keeps working unchanged.
#
# Overrides (all optional):
#   A9_ARLO_ROOT       repository root          (default: this file's ../..)
#   A9QEMU_STAGE       staging/scratch tree     (default: /opt/a9qemu if writable,
#                                                else $XDG_STATE_HOME/a9qemu)
#   A9QEMU_LOG_SCOPE   directory logs are copied back to (default: this directory)
#   A9QEMU_LOG_TAG     suffix for new log names (default: empty; set e.g. "-linux"
#                      to keep a re-run on a second host from overwriting the
#                      first host's logs)
#
# Exported for scripts written before this file: Q, W, STAGE, WIN_SCOPE, QEMU_DIR,
# ARLO_ROOT, LOG_SCOPE, LOG_TAG.
#
# Nothing here runs QEMU, touches the phone, or needs root. It only resolves paths.

A9QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Repository root: derived from this file's location, so a checkout anywhere works.
ARLO_ROOT="${A9_ARLO_ROOT:-$(cd "$A9QEMU_DIR/../.." && pwd)}"
# WSL fallback: on the old host the same tree is also visible through the drvfs
# mount, and a script invoked through a copy (or a stale symlink) still finds it.
if [ ! -d "$ARLO_ROOT/a9linux" ] && [ -d /mnt/e/Reverseing/Arlo/a9linux ]; then
  ARLO_ROOT=/mnt/e/Reverseing/Arlo
fi

# Staging tree. The WSL default is /opt/a9qemu; unprivileged Linux usually cannot
# write /opt, so fall back once, loudly, to a per-user state directory.
if [ -n "${A9QEMU_STAGE:-}" ]; then
  STAGE="$A9QEMU_STAGE"
elif mkdir -p /opt/a9qemu 2>/dev/null && [ -w /opt/a9qemu ]; then
  STAGE=/opt/a9qemu
else
  STAGE="${XDG_STATE_HOME:-$HOME/.local/state}/a9qemu"
  echo "qemu-env: /opt/a9qemu is not writable here; staging in $STAGE" >&2
  echo "qemu-env: (override with A9QEMU_STAGE=/some/where)" >&2
fi
mkdir -p "$STAGE/inputs" "$STAGE/work" "$STAGE/logs" 2>/dev/null || true

# Where run logs are copied back to. On WSL this was the drvfs repository copy.
LOG_SCOPE="${A9QEMU_LOG_SCOPE:-$A9QEMU_DIR/logs}"
LOG_TAG="${A9QEMU_LOG_TAG:-}"
mkdir -p "$LOG_SCOPE" 2>/dev/null || true

export QEMU_DIR="$A9QEMU_DIR"
export ARLO_ROOT STAGE LOG_SCOPE LOG_TAG
# Compatibility aliases used by the scripts written before this file.
export Q="$A9QEMU_DIR"
export SCOPE="$A9QEMU_DIR"
export W="$ARLO_ROOT"
# WIN_SCOPE is the harness DIRECTORY (its `logs/` subdir is the copy target);
# LOG_SCOPE is that logs directory itself. They are not the same value, and run-qemu.sh
# appends `/logs` to WIN_SCOPE.
export WIN_SCOPE="$A9QEMU_DIR"
export A9QEMU_LOG_SCOPE="$LOG_SCOPE"
