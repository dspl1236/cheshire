# Cheshire

**AliceVision / Meshroom photogrammetry on AMD RDNA3/RDNA4 GPUs.**

Meshroom's dense reconstruction (`DepthMap`) is CUDA-only, so it has never run
on AMD cards. Cheshire ports that backend to **HIP** (AMD's CUDA-shaped API,
native on Windows since ROCm 7.2) and adds a **memory bridge** that lets the
depth-map stages spill from VRAM into system RAM instead of failing.

The cat that grins on any hardware.

## Layout

| Path | What |
|---|---|
| `docs/` | scope, findings, architecture, build notes |
| `hip/` | HIP portability layer + the ported `depthMap_hip` backend overlay |
| `hip/tests/` | small standalone HIP programs that prove each feature the port needs on real hardware |
| `bridge/` | the VRAM -> system-RAM memory bridge (allocator policy + tiling hints) |
| `scripts/` | environment bootstrap (ROCm pip wheels, CMake, Ninja), build drivers |
| `third_party/aliceVision` | upstream AliceVision, pinned as a submodule (untouched) |

## Target hardware / software

* Radeon RX 9070 (RDNA4, `gfx1201`) - primary dev box, Windows 11, Adrenalin 26.8.1
* RDNA3 (`gfx110x`) - secondary target
* ROCm 7.2.1 for Windows, installed as pip wheels (no admin installer needed)
* MSVC 2026 Build Tools + CMake 4.4 + Ninja 1.13
* Production target: the `house-pc` photogrammetry node pattern from
  `haus-infrastructure` (Linux, `meshroom_batch`, `reconstruct`/`newjob` scripts),
  re-homed onto an AMD card.

## Status (2026-09-03)

* Full AliceVision builds on Windows with the HIP backend (`scripts/build-alicevision.cmd`).
* DepthMap output validated against the CUDA node on the same SfM: identical validity masks,
  zero median depth error. Stats, tables and side-by-side panels:
  [docs/validation/monstree-mini6](docs/validation/monstree-mini6/index.md) (6 views, PASS),
  [docs/validation/monstree-full](docs/validation/monstree-full/index.md) (41 views).
* Memory bridge v1 (`hip/compat/include/cheshire/bridge.h`): VRAM first, mapped system RAM
  when short, hardware-tested.
* Linux: bundle built in WSL2 (ROCm 7.2), validated on a Radeon RX 5500 XT (RDNA1) in the
  production node against its own CUDA output: [6 views](docs/validation/monstree-mini6-rx5500xt-linux/index.md),
  [41 views](docs/validation/monstree-full-rx5500xt-linux/index.md); and on a Radeon RX 6750 XT (RDNA2):
  [6 views](docs/validation/monstree-mini6-rx6750xt-linux/index.md), [41 views](docs/validation/monstree-full-rx6750xt-linux/index.md).
  Fat binary covers gfx1010-gfx1201.
* Performance pass (docs/05): 6 views 21.2 s -> 17.4 s, 41 views 154.7 s -> 124.4 s on the RX 9070
  (CUDA node, GTX 1080 Ti: 31.9 s / 105.5 s). Output bit-identical to the validated build.

See `docs/` for findings, toolchain notes, the bridge design and the port log.
