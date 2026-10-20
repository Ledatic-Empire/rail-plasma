#!/bin/bash
# gate.sh: the beacon's physics tests, run the way the Rail suite ran them (t186 to t189 there
# until 2026-10-20). A program that prints is judged on its full stdout; a signal death (exit
# >= 128) fails; a program that prints nothing is judged on its exit status.
#
#   RAIL_BIN=~/projects/rail-https/rail_native bash gate.sh
#
set -u
cd "$(dirname "$0")"
RAIL_BIN="${RAIL_BIN:-$HOME/projects/rail-https/rail_native}"
[ -x "$RAIL_BIN" ] || { echo "gate: no rail_native at $RAIL_BIN" >&2; exit 2; }
OUT="${TMPDIR:-/tmp}/plasma_gate.$$"
mkdir -p "$OUT"
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
rm -rf "$OUT"
echo "$pass/$((pass+fail)) beacon tests passed"
[ "$fail" -eq 0 ]
