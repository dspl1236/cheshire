# Linux build (for the AMD photogrammetry node)

The production node pattern (haus-infrastructure `photogrammetry-node.md`) is Linux Mint 22
(= Ubuntu 24.04) with Meshroom's `meshroom_batch` and the `reconstruct`/`newjob` scripts.
`house-pc` itself has a GTX 1080 Ti and no AMD card, so the Linux HIP build is produced and
packaged here and deployed to whatever AMD box replaces or joins it.

## Build environment: WSL2 Ubuntu 24.04 + ROCm 7.2 (this PC)

```bash
# Windows side (once): wsl --install -d Ubuntu-24.04 --no-launch
# inside the distro (root):
apt-get update && apt-get install -y build-essential cmake ninja-build git wget curl python3 python3-venv
wget https://repo.radeon.com/amdgpu-install/7.2/ubuntu/noble/amdgpu-install_7.2.70200-1_all.deb
apt-get install -y ./amdgpu-install_7.2.70200-1_all.deb
amdgpu-install -y --usecase=wsl,rocm --no-dkms      # ~10 min, installs /opt/rocm-7.2.0
/opt/rocm/bin/rocminfo | grep -E "gfx|Marketing"     # RX 9070 shows up as gfx1201
# Kitware CMake (AliceVision wants >= 3.30; noble ships 3.28) + superbuild prerequisites:
#   see scripts/linux/build-deps.sh header and docker/Dockerfile_ubuntu_deps upstream
```

Same-version base as the node (Ubuntu 24.04 / glibc 2.39), so the bundle transfers.

### What WSL can and cannot do (measured with `hip/tests`)

| | WSL2 + ROCm 7.2 | native Windows ROCm 7.2.1 |
|---|---|---|
| plain kernels, `hipMalloc`, copies | OK (launch 1.9 us) | OK |
| `hipMallocPitch`, `hipMalloc3D` | **invalid argument** | OK |
| arrays, textures, surfaces, mipmaps | **operation not supported** (`maxTexture2D = 0`) | OK (except surf stores to half arrays) |
| `rocprofv3` | present, but the depth-map kernels cannot run | n/a |

So WSL is a **build box**: it compiles the HIP backend for every RDNA target, but
`aliceVision_depthMapEstimation` cannot execute there and neither can it be profiled there.
Correctness of the kernels is established on Windows from the same sources (docs/04); the
Linux binaries need a native-Linux AMD machine for a run-through.

## Steps

1. `scripts/linux/build-deps.sh` - AliceVision's own dependency superbuild
   (`ALICEVISION_BUILD_DEPENDENCIES=ON`), CUDA-free: no PopSift, CCTag, AprilTag, OpenCV,
   ONNX Runtime, USD, PCL, E57, FFmpeg, Python bindings. Everything the node's default
   `meshroom_batch` graph needs (features, matching, SfM, PrepareDenseScene, DepthMap,
   DepthMapFilter, Meshing, MeshFiltering, Texturing) is in. Install: `/opt/AliceVision_deps`.
2. `scripts/linux/build-alicevision.sh [configure|build|install|bundle] [gfx list]` -
   applies `scripts/apply_hip_patch.py`, configures with `ALICEVISION_USE_HIP=ON`,
   `CMAKE_HIP_COMPILER=/opt/rocm/lib/llvm/bin/clang++`, default targets
   `gfx1201;gfx1200;gfx1100;gfx1101;gfx1102`, installs to `/opt/AliceVision_hip` and makes
   AliceVision's relocatable `bundle` (binaries + libraries + share/) like the Meshroom
   tarball the node uses today.
3. `scripts/linux/run-depthmap.sh` - the node-side equivalent of the Windows validation
   runner (same DepthMap command line as Meshroom 2023.3's `standard` preset).
4. `scripts/linux/gpu-precheck.sh` - drop-in for the `nvidia-smi` precondition in the
   node's `reconstruct`: reports the GPU via `amd-smi` / `rocm-smi` / `nvidia-smi`, whichever
   exists.

## Notes

* Background processes started from a `wsl -e bash -c` session die with the session;
  start long builds with `setsid -f ... < /dev/null` or from a Windows-side background task.
* `-fgpu-rdc` (relocatable device code) is expected to work on Linux; the unity device TU is
  still the default (`ALICEVISION_HIP_RDC=ON` switches).
* The Boost.WinAPI define block in the patch is `if (WIN32)`-guarded and does nothing here.

## Result (2026-09-03)

* Dependency superbuild: OK after three generic fixes (CMake 4 policy floor for lz4/OpenMesh,
  `-include cstdint` for assimp's Draco on GCC 13, pybind11 needed by OpenImageIO). About
  40 minutes on 12 threads. 157 libraries in `/opt/AliceVision_deps`.
* AliceVision + HIP backend: **671/671 targets, 0 failures** on the first full pass
  (after `ALICEVISION_BUILD_LIDAR=OFF`; E57 was excluded from the deps). HIP 7.2.26015,
  targets `gfx1201;gfx1200;gfx1100;gfx1101;gfx1102` in one fat binary. The Linux build
  was noticeably less trouble than Windows: no STL shim, no OpenMP shim, no arch flag issue.
* Bundle: `cmake --build . --target bundle` -> `/opt/AliceVision_hip/bundle` (167 MB;
  bin/ with 208 tool entries, lib/ including `libamdhip64.so.7`, `libhsa-runtime64.so.1`,
  `libamd_comgr`, share/). Run it like the Meshroom tarball: `LD_LIBRARY_PATH=<bundle>/lib`
  and `ALICEVISION_ROOT=<bundle>`.
* Tarball: `build/cheshire-alicevision-hip-linux-x64-rocm7.2-<commit>.tar.gz` (60 MB),
  also staged on `house-pc:~/apps/cheshire/`. It loads and runs its CPU tools on Mint 22.
* Under WSL the bundle finds the GPU (`hardwareResources` reports the RX 9070 through the
  HIP runtime) and `depthMapEstimation` fails exactly where expected, at the first array /
  texture creation: `CUDA Error: operation not supported`. A native-Linux AMD box is
  needed for the first real Linux depth-map run; the kernels are the Windows-validated ones.

## Deploying to an AMD node

1. Unpack the tarball to `~/apps/cheshire/bundle`; the ROCm user-space runtime is inside the
   bundle, but the **amdgpu kernel driver** must be present (Ubuntu 24.04 stock kernel 6.8+
   is fine for RDNA3; RDNA4 wants the ROCm 7.2 `amdgpu-dkms` or a 6.12+ kernel) and the
   service user must be in the `render` and `video` groups.
2. Meshroom must match the AliceVision generation: this tree is AliceVision 3.4-dev, and the
   node's Meshroom 2023.3.0 graph passes options these binaries no longer accept
   (`--sgmFilteringAxes`). Use a Meshroom release built for AliceVision >= 3.3 (2025.x) and
   point it at the bundle's `bin`.
3. Replace the `nvidia-smi` precondition in `reconstruct` with `scripts/linux/gpu-precheck.sh`
   (amd-smi / rocm-smi / nvidia-smi, whichever exists) and the UI's GPU tiles accordingly.
4. Validate with `scripts/linux/run-depthmap.sh <bundle> <cache> <out> <reference DepthMap dir>`
   on a copied Meshroom cache (`data/ref/monstree-*` here), same procedure as docs/04.

## RDNA2 / house-pc with an RX 6700 XT (prepared 2026-09-03)

* Bundle rebuilt with `gfx1030` added (targets now gfx1030;gfx1100;gfx1101;gfx1102;gfx1200;gfx1201),
  `build/cheshire-alicevision-hip-linux-x64-rocm7.2-39f0251-rdna2.tar.gz`, staged as the only
  tarball in `house-pc:~/apps/cheshire/` together with `scripts/` (node-amd-setup.sh,
  run-depthmap.sh, gpu-precheck.sh, compare_depthmaps.py) and a Python venv for the compare tool.
* ROCm 7.2 user-space still ships gfx1030 code objects and the HSA runtime knows gfx1031; the
  6700 XT runs the gfx1030 code with `HSA_OVERRIDE_GFX_VERSION=10.3.0` (set in `env.sh` by the
  setup script). Mint 22.3's kernel has `amdgpu` for RDNA2; nothing from AMD's apt repo needed.
* Known caveat: community reports of a SIGSEGV regression on gfx1031/1032 with ROCm >= 6.4.3,
  unconfirmed on 7.2. Fallback if it shows up: rebuild the bundle against ROCm 6.4.
* Procedure on the node after the card swap (1080 Ti out): `sudo bash scripts/node-amd-setup.sh setup`,
  re-login, `scripts/node-amd-setup.sh check`, then `scripts/node-amd-setup.sh run monstree-mini6`
  (compares against the CUDA DepthMap produced on the same machine). Meshroom 2023.3 cannot drive
  these binaries; the test runs `aliceVision_depthMapEstimation` directly.
