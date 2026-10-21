#!/bin/bash
# replay.sh: replay one pulse of the ledatic.org entropy beacon and print MATCH or MISMATCH.
#
#   bash replay.sh 9166174          # by id: the record is fetched from ledatic.org
#   bash replay.sh pulse.json       # a record you already hold
#
# Needs a Rail compiler: RAIL_BIN, else ../rail/rail_native (a clone of Ledatic-Empire/rail
# beside this directory; its committed rail_native is the compiler), else the house path.
# Needs curl for the by-id form. Nothing else: the hash is computed in Rail (replay.rail).
#
# Exit 0 MATCH, 1 MISMATCH, 2 when nothing could be replayed (no compiler, no record, a pulse
# without an epoch seed). docs/REPLAY.md says what a MATCH does and does not prove.
set -u
cd "$(dirname "$0")" || exit 2
BEACON="${BEACON_URL:-https://ledatic.org}"
RAIL_BIN="${RAIL_BIN:-}"
if [ -z "$RAIL_BIN" ]; then
  for c in ../rail/rail_native "$HOME/projects/rail-https/rail_native"; do
    [ -x "$c" ] && RAIL_BIN="$c" && break
  done
fi
[ -n "$RAIL_BIN" ] && [ -x "$RAIL_BIN" ] || {
  echo "replay: no rail_native; set RAIL_BIN or clone https://github.com/Ledatic-Empire/rail beside this directory" >&2
  exit 2
}
arg="${1:-}"
[ -n "$arg" ] || { echo "usage: bash replay.sh <pulse_id | pulse.json>" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rail_replay.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

if [ -f "$arg" ]; then
  REC="$arg"
elif [[ "$arg" =~ ^[0-9]+$ ]]; then
  REC="$WORK/$arg.json"
  curl -fsS --max-time 20 "$BEACON/entropy/pulse/$arg" -o "$REC" || {
    echo "replay: could not fetch pulse $arg from $BEACON" >&2; exit 2; }
else
  echo "replay: $arg is neither a file nor a pulse id" >&2; exit 2
fi

if ! "$RAIL_BIN" --out-prefix "$WORK/replay" replay.rail > "$WORK/compile.log" 2>&1; then
  echo "replay: replay.rail did not compile with $RAIL_BIN" >&2
  tail -5 "$WORK/compile.log" >&2
  exit 2
fi

rail_here="$(git -C "$(dirname "$RAIL_BIN")" rev-parse HEAD 2>/dev/null || echo unknown)"
plasma_here="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
os_here="$(sw_vers -buildVersion 2>/dev/null || uname -r)"
echo "this machine   rail $rail_here  rail-plasma $plasma_here  os $os_here"
"$WORK/replay" "$REC" "$WORK/planes.f32"
