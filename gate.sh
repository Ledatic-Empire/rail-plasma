#!/bin/bash
# gate.sh: the beacon's physics tests, run the way the Rail suite ran them (t186 to t189 there
# until 2026-10-20), then the replay of the pinned pulse record in tests/ through replay.sh
# (Tier 3, step 2). A program that prints is judged on its full stdout; a signal death (exit
# >= 128) fails; a program that prints nothing is judged on its exit status; the replay must
# exit 0 and print MATCH.
#
#   RAIL_BIN=~/projects/rail-https/rail_native bash gate.sh
#
set -u
cd "$(dirname "$0")"
RAIL_BIN="${RAIL_BIN:-$HOME/projects/rail-https/rail_native}"
[ -x "$RAIL_BIN" ] || { echo "gate: no rail_native at $RAIL_BIN" >&2; exit 2; }
OUT="$(mktemp -d "${TMPDIR:-/tmp}/plasma_gate.XXXXXX")" || exit 2
pass=0; fail=0
for src in tests/*.rail; do
  name="$(basename "$src" .rail)"
  expected="$(cat "tests/$name.expected")"
  if ! "$RAIL_BIN" --out-prefix "$OUT/$name" "$src" > "$OUT/$name.compile" 2>&1; then
    echo "FAIL $name: compile"; sed 's/^/    /' "$OUT/$name.compile" | tail -5; fail=$((fail+1)); continue
  fi
  "$OUT/$name" > "$OUT/$name.out" 2>&1; code=$?
  actual="$(cat "$OUT/$name.out")"
  if [ -z "$actual" ]; then actual="$code"; fi
  if [ "$code" -ge 128 ]; then echo "FAIL $name: died with exit $code"; fail=$((fail+1))
  elif [ "$actual" == "$expected" ]; then echo "PASS $name"; pass=$((pass+1))
  else echo "FAIL $name: expected [$expected] got [$actual] (exit $code)"; fail=$((fail+1)); fi
done
# The pinned record: a real pulse, as served, replayed from its seed to its digest.
REC=tests/replay_pulse.json
if RAIL_BIN="$RAIL_BIN" bash replay.sh "$REC" > "$OUT/replay.out" 2>&1 && grep -q '^MATCH$' "$OUT/replay.out"; then
  echo "PASS replay_pulse ($(sed -n 's/^pulse  *\([0-9]*\).*/\1/p' "$OUT/replay.out"), $(sed -n 's/^replaying  *//p' "$OUT/replay.out"))"; pass=$((pass+1))
else
  echo "FAIL replay_pulse:"; sed 's/^/    /' "$OUT/replay.out" | tail -6; fail=$((fail+1))
fi
rm -rf "$OUT"
echo "$pass/$((pass+fail)) beacon tests passed"
[ "$fail" -eq 0 ]
