# Port status

## 2026-09-03: the whole `depthMap/cuda` tree compiles as HIP (gfx1201, clang-cl)

`scripts\build-port.cmd` builds `hip/port` -> object library `cheshire_depthmap_port`
from the **unmodified** upstream sources in `third_party/aliceVision`. Everything the
port needed, in order of discovery:

| Problem | Fix | Where |
|---|---|---|
| sources `#include <cuda_runtime.h>`, `<cuda_fp16.h>`, `<math_constants.h>` | shim headers that pull in `cheshire/cuda_to_hip.h` | `hip/compat/include/` |
| `cuda*` API names | flat macro map (llama.cpp `vendors/hip.h` style), grep-derived from the tree | `cuda_to_hip.h` |
| `cudaMallocPitch<Type>(&buf, ...)` (templated overload only exists in CUDA) | inline template overloads | `cuda_to_hip.h` |
| nvcc pre-includes `cuda_runtime.h`; `.cu` files use `float3` before any include | force-include the compat header (`/FI` or `-include`) | `hip/port/CMakeLists.txt` |
| `CUDART_PI`, `CUDART_PI_F`, `CUDART_INF_F` | literal / `__builtin_inff()` definitions (hip_math_constants.h has no equivalents) | `cuda_to_hip.h` |
| `CUDA_HOST_DEVICE` gated on `#if defined(__NVCC__)` in two headers -> `__host__`-only methods called from kernels | overlay copies with `\|\| defined(__HIPCC__)`; unified diff kept for upstream | `hip/port/overlay/`, `patches/0001-hipcc-host-device-macros.patch` |
| Eigen guard in `numeric.hpp` | `EIGEN_MAX_ALIGN_BYTES=0 EIGEN_MAX_STATIC_ALIGN_BYTES=0` (same as upstream CMake) | `hip/port/CMakeLists.txt` |
| kernels reference `__constant__` symbols defined in other `.cu` files (upstream uses `CUDA_SEPARABLE_COMPILATION`) | `-fgpu-rdc` is **broken on Windows ROCm 7.2.1** (`clang-offload-bundler` -> `llvm-objcopy`: "user-mapped section open" / "not a valid object file" on COFF). Instead a **unity device TU** includes the 7 `.cu` files; host `.cpp` files stay separate because `cudaMemcpyToSymbol` does not need RDC. `CHESHIRE_HIP_RDC=ON` restores per-file RDC for Linux. | `hip/port/unity/depthmap_device_unity.hip` |
| Boost headers in the device pass warn about `__declspec` | `-Wno-ignored-attributes -Wno-unknown-attributes` for HIP | `hip/port/CMakeLists.txt` |

Result: 6 objects (5 host + 1 unity device), 0 errors. Upstreamable shape: a
`ALICEVISION_DEPTHMAP_BACKEND=HIP` value that compiles the existing CUDA sources with the
compat header, plus the two-line header patch.

## Next
1. Full AliceVision build with the HIP backend against the prebuilt vcpkg tree
   (`tools/vcpkg-deps`, MSVC 2026 build), clang-cl as the compiler.
2. Run `aliceVision_depthMapEstimation` on a real dataset; compare against the CUDA
   node's output on the same SfM.
3. Memory bridge inside `DeviceCache` / `DeviceMipmapImage` (docs/02).

## 2026-09-03 (later): full AliceVision build green, DepthMap validated against CUDA

`scripts/build-alicevision.cmd gfx1201 install` builds all of AliceVision (108 executables)
with the HIP backend and installs to `build/av-gfx1201-install`. Extra fixes on the way
(all in `scripts/apply_hip_patch.py` / `build-alicevision.cmd`): MSVC STL helper shim
(`hip/compat/stlcompat`), `/arch:AVX2` instead of the OFA `/arch:SSE2`, Boost.WinAPI vs
windows.h in the device pass (`BOOST_USE_WINDOWS_H`), an OpenMP structured-binding rewrite,
`LEMON::lemon`, the constant-writing host files joining the unity TU (non-RDC shadows are
TU-local on the host too), and **float4 instead of half4 camera textures** (HIP-Windows
half texture bug). Validation: docs/04 (PASS on monstree-mini6, 21.2 s vs 31.9 s CUDA/1080 Ti).

## v0.2.0 (2026-09-04)

* Memory bridge v2: allocations tagged by class, soft VRAM cap, non-coherent host tier, planner
  patch in `DepthMapEstimator::getNbSimultaneousTiles` (hip/port/bridge_v2). docs/02 has every
  measurement; every configuration is bit-identical to v0.1.0.
* Mipmap emulation: linear (pitch2D) level storage, default on the emulated build; per-level
  array textures redirected; `[cheshire] mip:` log line.
* Compat layer: `cudaMemcpy*` / `cudaMemset*` wrappers that stream-order operations on spilled
  blocks; `cudaMemcpy2DToArray` / `cudaMemcpy3D` routed through the emulation.
* Meshroom pairing (`scripts/linux/meshroom-pair.sh`): the 2023.3 DepthMap node runs on the HIP
  build, dropping the removed `--sgmFilteringAxes` option; CUDA binary kept and chosen when
  `nvidia-smi` answers.
* Windows package with RDNA3 + RDNA4 code objects (gfx1100/1101/1102/1200/1201) for testers;
  no RDNA3 hardware run yet.
