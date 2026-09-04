# Scope and findings (2026-09-03)

## Goal
Run the full Meshroom/AliceVision pipeline on AMD RDNA3/RDNA4 GPUs, natively on
Windows first, Linux second (the production node is Linux). Two deliverables:

1. **HIP backend for AliceVision `depthMap`** - the only CUDA-mandatory stage.
2. **Memory bridge** - allocator policy so depth-map work spills VRAM -> system RAM.

Plus the glue the existing node needs: `reconstruct`/web UI currently hard-require
`nvidia-smi`; an AMD node needs the same tiles and preconditions from `amd-smi`.

## What already exists (verified 2026-09-03)
* ROCm 7.2.1 for Windows ships as pip wheels
  (`rocm_sdk_core`, `rocm_sdk_devel`, `rocm_sdk_libraries_custom`, `rocm` meta
  sdist) at `https://repo.radeon.com/rocm/windows/rocm-rel-7.2.1/`.
  RDNA4 (`gfx1200`/`gfx1201`) is the best-supported Windows target. Python 3.12,
  driver 26.2.2 or newer required. No admin installer needed.
* AliceVision upstream (`2cb1a39`, 2026-08-28) has **three** depth-map backends
  in its CMake: `CUDA`, `SYCL` (new, `src/aliceVision/depthMap_sycl/`), or BOTH.
  The SYCL port proves the stage is already abstracted behind
  `ALICEVISION_DEPTHMAP_BACKEND`; a `HIP` value slots in the same way.
  SYCL itself is not a Windows/AMD path (no Codeplay AMD plugin on Windows).
* The CUDA surface of `depthMap/cuda` is small and HIP-friendly: ~8.3k lines,
  streams, pitched 2D/3D memory, texture objects with `tex2DLod`, surfaces
  (`surf2Dwrite`), **mipmapped arrays**, `__constant__` camera params, `half`.
  No cub/thrust/warp-shuffle/cooperative groups. Mipmapped arrays are the one
  feature to prove early on HIP-Windows (see `hip/tests/mipmap_tex.hip`).
* Feature extraction: PopSift (CUDA) is optional; vlfeat CPU SIFT is the
  default in Meshroom. Segmentation uses ONNX Runtime CUDA EP; on Windows the
  DirectML EP runs on AMD without any port, on Linux the ROCm EP.
* COLMAP upstream already ships a HIP `patch_match_stereo` (Linux only) - a
  useful reference for HIP idioms, not a dependency.
* ZLUDA (CUDA-on-AMD) supports ROCm 7 / RDNA4 but is a one-person hobby again;
  not a foundation.

## The production node today (from haus-infrastructure/docs/photogrammetry-node.md)
* `house-pc`: i3-4330 / 14 GiB / GTX 1080 Ti 11 GB, Linux Mint 22.3,
  Meshroom **2023.3.0** bundled tarball (CUDA 11.3 runtime, libpopsift), no Docker.
* Only `DepthMap` (and optional PopSift extraction) touch the GPU. GPU share of a
  job is 18-22% (36% on `detailed`); the i3 is the real bottleneck.
* Presets differ only by `DepthMap:downscale` (4/2/1) and texture side.
* Hard NVIDIA couplings to replace: `nvidia-smi` precondition in `reconstruct`,
  GPU/VRAM tiles in the FastAPI UI, torch `+cu121` in the segmentation venv.

## Approach
HIP port with a single-source portability header so the same kernels build for
CUDA and HIP (upstreamable). Vulkan-compute rewrite is the fallback only if
HIP-on-Windows proves unusable for textures/mipmaps.

## Dev box
Ryzen 5 5600X, 64 GB RAM, RX 9070 16 GB, Windows 11 Pro 26200, Adrenalin 26.8.1.
