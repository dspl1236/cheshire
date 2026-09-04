# Cheshire

**Meshroom / AliceVision photogrammetry on AMD Radeon GPUs, via HIP.**

AliceVision's dense reconstruction (`DepthMap`, the stage Meshroom needs a GPU for) is
written in CUDA and has only ever run on NVIDIA. Cheshire compiles those same CUDA kernels as
HIP through a small compatibility layer, adds a **memory bridge** that lets the stage spill from
VRAM into system RAM instead of failing, and packages the result for Windows and Linux.
Validated against a CUDA node's output on RDNA1, RDNA2 and RDNA4 cards.

The cat that grins on any hardware.

## Results

Same photos, same SfM, same DepthMap parameters as the CUDA reference (Meshroom 2023.3 on a
GTX 1080 Ti); only the GPU stage differs. Metrics are per view over pixels valid in both maps.

| GPU | OS | 6 views | 41 views | valid masks | median rel. depth error | within 1 % (median view, 6 / 41) |
|---|---|---|---|---|---|---|
| GTX 1080 Ti (CUDA reference) | Linux | 31.9 s | 105.5 s | | | |
| Radeon RX 9070, RDNA4 | Windows | **17.4 s** | 124.4 s | identical | 0.0000 | 98.9 % / 98.7 % |
| Radeon RX 6750 XT, RDNA2 | Linux | **31.0 s** | 226.1 s | identical | 0.0000 | 97.5 % / 98.1 % |
| Radeon RX 5500 XT, RDNA1 | Linux | 60.7 s | 447.7 s | identical | 0.0000 | 97.5 % / 98.1 % |

RDNA1 and RDNA2 produce bit-identical depth maps. The remaining 1-3 % of pixels that differ by
more than 1 % between GPU generations (and against CUDA) is the algorithm's cross-hardware
noise floor: texture-filter and FMA rounding, not a port defect. Full per-view tables and
side-by-side panels: [docs/validation](docs/validation/).

## Memory bridge

Measured on the RX 9070 (`hip/tests/membridge_probe.hip`), the tiers the bridge chooses between:

| memory | kernel streaming read |
|---|---|
| VRAM (`hipMalloc`) | 585-619 GB/s |
| mapped system RAM (`hipHostMalloc`, PCIe 4.0 x16) | 24.6-26.6 GB/s |
| `hipMallocManaged` | 26.6 GB/s (no page migration on Windows) |
| pinned host copies | 28 GB/s each way |

On Windows the driver already lets `hipMalloc` run past VRAM into system RAM; on Linux it fails
hard. The bridge (`hip/compat/include/cheshire/bridge.h`) makes both behave the same: VRAM
first, mapped host memory when VRAM is short or a soft cap is hit, one registry so `cudaFree`
releases the right thing, and textures and kernels keep working over spilled buffers.
Forcing it on a real job (1.5 GB VRAM cap, 5.4 GB spilled): output **bit-identical**,
2.7x slower on the RX 9070, 5.2x on a PCIe 3.0 box. Design and measurements:
[docs/02-memory-bridge.md](docs/02-memory-bridge.md).

## What was found on the way (reproducers in `hip/tests/`)

* **HIP drops `surf2Dwrite` stores into 16-bit float arrays**, on Windows and Linux alike;
  reads are fine. AliceVision's mip chain is built through a buffer copy instead.
* **Linux ROCm 7.2 has no `hipMallocMipmappedArray`** on RDNA1 (and WSL2 has no textures at
  all). Mipmaps are emulated in the compat layer as one texture per level: bit-identical to
  native mipmaps on the RX 9070, ~35 % slower there, so the Windows build keeps native.
* **ROCm for Windows installs as pip wheels**, no admin installer. CMake refuses to mix
  `cl.exe` with clang for HIP: use `clang-cl` for both. `-fgpu-rdc` is broken on Windows, so
  the device code is compiled as one unity translation unit.
* **A relocatable Linux bundle needs two things `fixup_bundle` never sees**: the KFD flavour of
  `libhsa-runtime64` (a WSL build box ships the `/dev/dxg` one) and `libamd_comgr` (HIP
  `dlopen`s it). With those in place RDNA1 works natively on ROCm 7.2.

## Layout

| Path | What |
|---|---|
| `hip/compat/include/cheshire/` | the CUDA -> HIP compatibility header, the memory bridge, the mipmap emulation |
| `hip/port/` | fused SGM aggregation and the other upstreamable source changes, applied by `scripts/apply_hip_patch.py` |
| `hip/tests/` | standalone HIP probes: textures, surfaces, mipmaps, bandwidth, allocation, launch overhead, the bridge |
| `scripts/` | Windows build (`build-alicevision.cmd`), Linux superbuild and bundle (`scripts/linux/`), validation runner, comparison tool |
| `docs/` | findings, toolchain notes, bridge design, port log, validation, performance, Linux build |
| `third_party/aliceVision` | upstream AliceVision, pinned as a submodule and left untouched; the HIP backend is a patch set |

## Building

* Windows (RDNA3/RDNA4): [docs/01-toolchain-windows.md](docs/01-toolchain-windows.md), then
  `scripts\build-alicevision.cmd gfx1201 install`.
* Linux (RDNA1-RDNA4): [docs/06-linux-build.md](docs/06-linux-build.md), then
  `scripts/linux/build-deps.sh` and `scripts/linux/build-alicevision.sh bundle`.
* Validate: `scripts\run-depthmap.cmd <dataset>` or `scripts/linux/run-depthmap.sh` against a
  Meshroom cache; `scripts/compare_depthmaps.py` produces the numbers and panels.

## Status and next

Works end to end on RDNA1, RDNA2 and RDNA4; RDNA3 has its code object in every bundle but no
hardware run yet. Next: bridge v2 (keep similarity volumes in VRAM, spill camera images first,
make the planner aware), a same-version CUDA reference, RDNA3 hardware, and a Meshroom
release paired with the bundle on a production node.
