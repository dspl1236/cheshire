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

See `docs/` for the plan and current status.
