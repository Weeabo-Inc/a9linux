#!/usr/bin/env bash
# a9linux/qemu/test-pin-teeth-run.sh — drive the staleness negative control end to end:
# our pin verdict against an altered map, then the canonical check, then cleanup.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SELF_DIR/qemu-env.sh"
echo "=== (B) our pin check against the altered copy ==="
# build first: without it `mine` has nothing to read and exits 2 with a note on
# stderr -- which the old version of this script swallowed, so the end-to-end
# control reported success while testing nothing. Found on the bare-metal Linux
# host, 2026-10-03; a control that silently does nothing is the failure mode it
# exists to catch.
bash "$Q/test-pin-teeth.sh" build || exit 1
if ! bash "$Q/test-pin-teeth.sh" mine; then
  echo "RESULT: FAIL - our pin verdict did NOT reject the altered map"
  exit 1
fi
echo
echo "=== canonical check on the REAL artefacts (verdict A structural + verdict B pins) ==="
bash "$Q/verify-map-pairing.sh" | tail -16
rc=${PIPESTATUS[0]}
echo
echo "=== cleanup ==="
bash "$Q/test-pin-teeth.sh" clean
exit $rc
