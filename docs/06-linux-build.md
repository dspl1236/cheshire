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
