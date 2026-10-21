# Replaying a pulse

The ledatic.org entropy beacon publishes one signed record every two seconds
(https://ledatic.org/entropy/spec). Since 2026-10-19 each record's `frame` block names the
inputs its number came from; since 2026-10-21 it also names the program. This page is how a
stranger checks one.

## The record

```json
"frame": {
  "digest":        "c0f66004ffe42845fa4c760ea8bf4570d69a472423002b3c8a8fc28476c9a185",
  "run_frame":     828,
  "epoch_seed":    569261,
  "epoch_frame":   76,
  "rail_commit":   "cc7924e1ee56b92fb1dc1a6d775f9965c8577269",
  "plasma_commit": "…",
  "os_build":      "25G83"
}
```

| field | meaning |
|---|---|
| `digest` | SHA-256 of the 393,216 float32 bytes the solver wrote for this frame: six 128 by 128 planes (rho, vx, vy, p, Bx, By), plane-major, row-major, little-endian |
| `epoch_seed` | the integer the beacon drew from `/dev/urandom` at the start of this epoch; the perturbation of the Orszag-Tang initial condition is a pure function of it |
| `epoch_frame` | frames advanced since that perturbation; one frame is four Lax-Friedrichs steps with CFL-adaptive dt |
| `rail_commit` | the commit of https://github.com/Ledatic-Empire/rail whose committed `rail_native` compiled the beacon |
| `plasma_commit` | the commit of this repository the beacon ran |
| `os_build` | the macOS build the beacon ran on (`sw_vers -buildVersion`) |

`digest`, `epoch_seed` and `epoch_frame` are inside the signed canonical message. The three
program fields are not: they are the producer's pointer to the source that reproduces the
digest, and the replay below is their check. A pointer at the wrong commit fails the replay;
it cannot make a wrong digest pass. A suffix `-dirty` means the checkout had modified tracked
files when it ran, so the commit alone is not the program; treat such a pulse as unreplayable.
A pulse whose `status` carries bit 2 (NO_PROVENANCE, value 4) or whose `epoch_seed` is -1
names no inputs and cannot be replayed.

## One command

```
git clone https://github.com/Ledatic-Empire/rail.git
git clone https://github.com/Ledatic-Empire/rail-plasma.git
cd rail-plasma
bash replay.sh 9166174            # a pulse id, fetched from ledatic.org
bash replay.sh pulse.json         # or a record you already hold
```

The Rail clone's committed `rail_native` is the compiler (ARM64 macOS; it needs the command
line tools for `as`, `ld` and `codesign`). `replay.sh` compiles `replay.rail`, which parses
the record, rebuilds the frame with the same `mhd_kernel.rail` the beacon runs, hashes the
planes with Rail's own SHA-256, and prints:

```
this machine   rail cc7924e1…  rail-plasma 3f0e…  os 25G83
pulse          9166174  2026-10-21T13:29:34Z
epoch_seed     569261
epoch_frame    76
rail_commit    cc7924e1ee56b92fb1dc1a6d775f9965c8577269
plasma_commit  …
os_build       25G83
replaying      77 frames (308 LF steps)
sim_time       1.19434709205996
digest         c0f66004ffe42845fa4c760ea8bf4570d69a472423002b3c8a8fc28476c9a185
frame.digest   c0f66004ffe42845fa4c760ea8bf4570d69a472423002b3c8a8fc28476c9a185
MATCH
```

Exit 0 is MATCH, 1 is MISMATCH, 2 is "nothing could be replayed" (no compiler, no record, no
seed). An epoch is about 190 frames; replaying its last frame takes about 25 s on an M4 Pro.
To replay at exactly the commits the record names, check both clones out at them first
(`git -C ../rail checkout <rail_commit>`, `git checkout <plasma_commit>`). The scheduled job
in `.github/workflows/gate.yml` does that for the newest pulse every day on a GitHub Mac.

## What MATCH means, and does not

MATCH means: this machine, running the named source, derives the published digest from the
published seed. The record is the output of the program it names. That is provenance.

It does not mean the physics is right, and the record never says so. A reproducible digest of a
wrong simulation is still reproducible. Conservation and divergence checks are the gate's job
(`gate.sh`), not the replay's.

A MISMATCH on the Mini or in CI is a finding against the beacon. A MISMATCH on another
platform is a finding against the layer under the kernel. Since Tier 3 step 4 (2026-10-21) no
libm function whose result the standard leaves to the implementation is on that path: the
initial condition and the seeded perturbation take `sin` from Rail's `stdlib/math_exact.rail`
(a fixed integer algorithm at 24 fractional bits, within 1.43e-7 of libm, the same bits on any
machine with 64-bit integers), and what remains of libm is `sqrt` (IEEE-754 requires it
correctly rounded, so every libm agrees) and `fmod` inside the runtime's generic `%` (exact by
definition). Float literals are the 64 bits the compiler decided (Rail `tools/decimal64.rail`,
step 8, 2026-10-21): no `atof` runs. Nothing on the
judging path prints a float: the digest is a SHA-256 over the frame's bytes, and the
known-answer test in `tests/` judges its double by the 64 bits (`show_float_hex`, Rail
`stdlib/float_hex.rail`, derived by exact arithmetic, so the same bits give the same hex on
every IEEE-754 platform; Tier 3 step 3, 2026-10-21). Rail's text printers (`show_float`,
`snprintf` on macOS, a six-decimal shim on Linux) are for reading, never for judging.

Linux ARM64 replays (measured 2026-10-21 on a Pi Zero 2 W, Debian 6.6.51, running binaries
cross-compiled on the Mini). The first reason it was declared non-replay, no `sin` in the libc
Rail ships for it, ended with step 4. The second, that a replay on the Pi gave a different
digest, had been read as the twelve of the kernel's 29 float literals that the Linux `atof`
parsed one or two ulps off; step 8 removed `atof` from every literal (all 38 probed literals,
the kernel's 31 included, now hold the Mini's bits on the Pi) and the digest did not move,
because it was never numerical: the runtime's float32 file writer issued raw Darwin syscalls,
wrote nothing on Linux, and the replay digested 393,216 bytes of a file that did not exist,
whose SHA-256 is `a6619f48...`. With Linux versions of the writer and reader (Rail
`tools/linux_libc.s`) the Pi replays step 4's 38-frame record (152 steps) to `acf59368...`, the
digest the Mini's kernel gives it, and the two planes files `cmp` equal byte for byte.
`replay.rail` now refuses a planes file it did not write (`WRITE_FAILED`, exit 2) instead of
digesting zeros. What the Pi cannot do yet is the record pinned here (64 frames, 256 steps): the
Linux build's static 1 GB heap exceeds the box's 416 MB and it reset twice under the attempt, so
a Pi verdict needs a record its memory holds, or a Linux heap that collects sooner.

## What else runs this

- `gate.sh` replays the pinned record in `tests/` after the four physics tests, on every push
  and pull request (GitHub `macos-latest`, Rail pinned).
- The house's chain audit replays the newest seeded pulse from its archive through the same
  `replay.sh` and reports `REPLAY=match|mismatch|error` beside the signature and link checks.
- The off-box witness (Tier 3 step 7, since 2026-10-21): every day the Mini replays the newest
  seeded pulse ledatic.org serves, and a second Mac on the house tailnet fetches the same record
  on its own, checks out the Rail and rail-plasma commits the record names from the public repos,
  and replays it with that compiler. Each machine logs `match`, `mismatch` or `error` for the
  pulse; anything but match on both rings the owner.
- `mhd_verify_epoch.rail` is the hand-driven form: seed and frame count in, diagnostics out,
  planes optionally written. It and `replay.rail` advance a frame through one definition,
  `mk_advance_frames` in `mhd_kernel.rail`.
