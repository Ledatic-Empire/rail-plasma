# rail-plasma

The entropy beacon behind https://ledatic.org/entropy, and the MHD work around it. Pure Rail,
compiled by the `rail_native` of a Rail checkout. Moved out of `Ledatic-Empire/rail` on
2026-10-20 (it lived at `tools/plasma/` and `stdlib/mhd_{kernel,axisym,mpd}.rail`; that tree is
tag `archive/tier2-precut-2026-10-20` there, and the history of every file stays there).

## What is live

- `mhd_beacon.rail` runs the 2D MHD solver and writes a frame per step; `mhd_beacon_daemon.py`
  packs and publishes it; `mhd_beacon.sh` keeps both up. On the Mini this is launchd
  `com.ledatic.mhd`, working directory this checkout, `RAIL_DIR` pointing at the Rail checkout
  whose `rail_native` compiles it.
- `mhd_verify_epoch.rail` replays any epoch from its logged seed; the chain audit calls it.
- `mhd_kernel.rail`, `mhd_axisym.rail`, `mhd_mpd.rail`: the solvers. Programs import them bare
  (`import mhd_kernel`), which resolves in this directory; `import time` resolves in the Rail
  checkout's `stdlib/` next to the `rail_native` that is running.

## Gate

```
RAIL_BIN=~/projects/rail-https/rail_native bash gate.sh
```

Four known-answer tests, moved here from the Rail suite (t186 to t189 there until 2026-10-20):
LxF invariants, the MUSCL divergence regression, the beacon replay from seed 246384, and GLM
divergence cleaning. CI runs them on every push against a pinned Rail commit.

## Everything else

Experiments and viewers that grew around the beacon: the neural MHD surrogate
(`neural_mhd_*.rail`, `neural_mhd_gpu_host.m`), the Orszag-Tang Metal host, the WASM render
substrate (`render.rail`, `build_render_wasm.sh`), the viewers (`live4k.html`, `holo.html`,
`plasma_lab.html`, ...). `VIEWERS.md` is the old `tools/plasma/README.md`; `PLASMA.md`,
`GLM_METRIC.md` and `ROLLOUT_BASELINE.md` are the notes. Paths inside those notes still say
`tools/plasma/`; read them as this directory.
