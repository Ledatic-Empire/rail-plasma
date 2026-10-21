#!/bin/bash
# tools/plasma/mhd_beacon.sh — Rail-native entropy-beacon daemon wrapper
#
# Replaces invocation of mhd_ot_beacon.py.  This wrapper is what the
# launchd plist (com.ledatic.mhd) runs; it execs the Rail beacon and
# restarts on crash with a brief backoff so a stuck/crashed process
# can't loop the kernel into oblivion.

set -u

RAIL_DIR="${RAIL_DIR:-$HOME/projects/rail-https}"
RAIL_BIN="${RAIL_DIR}/rail_native"
PLASMA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEACON_RAIL="${PLASMA_DIR}/mhd_beacon.rail"
DAEMON_PY="${PLASMA_DIR}/mhd_beacon_daemon.py"
# Canonical /tmp/plasma_live.bin in production; side path
# /tmp/plasma_live_rail.bin by default so dev runs don't clobber a live
# numpy beacon.  Exported so the daemon (spawned below) inherits it.
export MHD_BEACON_OUT="${MHD_BEACON_OUT:-/tmp/plasma_live_rail.bin}"

mkdir -p /tmp/mhd_beacon

# FIFO that Rail writes to after each frame to wake the warm packer.
[ -p /tmp/mhd_beacon/ready ] || mkfifo /tmp/mhd_beacon/ready

# Stop any prior daemon, then start a fresh one.  Without the warm
# daemon, the run_packer shim was forking python3 once per frame (~50 ms
# startup tax) — eliminating that fork tax is the whole point of #3.
pkill -f mhd_beacon_daemon.py 2>/dev/null
sleep 0.3
python3 "${DAEMON_PY}" >> $HOME/.ledatic/logs/mhd_packer.log 2>&1 &
DAEMON_PID=$!
trap "kill ${DAEMON_PID} 2>/dev/null" EXIT

# The Rail beacon used to shell out to /tmp/mhd_beacon/run_packer once
# per frame; that shim is no longer used since v3.9.0 — the beacon now
# write_files the FIFO directly to avoid the per-frame fork+exec
# (which leaked ~135 KB/s through macOS's slow VM-decommit on child
# exit). The daemon still drains /tmp/mhd_beacon/ready the same way.

cd "${PLASMA_DIR}"

# The program behind every frame, for the pulse's frame block (Tier 3, step 2): the Rail
# commit whose committed rail_native compiles the beacon, this checkout's commit, and the OS
# build. Written before each run so a pull between restarts is recorded, not guessed; a
# checkout with modified tracked files says so ("-dirty"), because then the commit is not the
# program. The packer daemon copies these three lines into the frame trailer (LDB3) and
# beacon_v2.py publishes them as frame.rail_commit, frame.plasma_commit, frame.os_build.
write_provenance() {
    local rail plasma os
    rail="$(git -C "${RAIL_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
    [ -n "$(git -C "${RAIL_DIR}" status --porcelain --untracked-files=no 2>/dev/null)" ] && rail="${rail}-dirty"
    plasma="$(git -C "${PLASMA_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
    [ -n "$(git -C "${PLASMA_DIR}" status --porcelain --untracked-files=no 2>/dev/null)" ] && plasma="${plasma}-dirty"
    os="$(sw_vers -buildVersion 2>/dev/null || uname -r)"
    printf '%s\n%s\n%s\n' "$rail" "$plasma" "$os" > /tmp/mhd_beacon/provenance.txt.tmp \
        && mv /tmp/mhd_beacon/provenance.txt.tmp /tmp/mhd_beacon/provenance.txt
}

# --out-prefix lands the compiled beacon at a DEDICATED path, not the shared
# /tmp/rail_out. Without it, `run` squats /tmp/rail_out as its running binary,
# so every concurrent `rail_native <file>` compile on this host either
# clobbers the beacon or gets ETXTBSY against it (the live binary is busy).
while true; do
    write_provenance
    "${RAIL_BIN}" --out-prefix /tmp/ledatic_mhd_out run "${BEACON_RAIL}"
    rc=$?
    echo "mhd_beacon: rail exited (rc=${rc}); restarting in 2s" >&2
    sleep 2
done
