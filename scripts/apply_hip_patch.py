#!/usr/bin/env python3
"""Apply Cheshire's HIP-backend changes to the AliceVision submodule working tree.

Idempotent: run it again after a submodule update and it re-applies (or reports
anchors that moved). Also regenerates patches/0002-hip-backend-cmake.patch from the
resulting `git diff` so the change set stays reviewable / upstreamable.

What it does
  * src/cmake/config.hpp.in           + ALICEVISION_HAVE_HIP()
  * src/CMakeLists.txt                + ALICEVISION_USE_HIP option, HIP detection after the
                                        CUDA block. A HIP build sets ALICEVISION_HAVE_CUDA=1
                                        (the CUDA sources are what gets compiled) and routes
                                        ALICEVISION_CUDA_LIBRARIES to hip::host.
  * src/aliceVision/depthMap/CMakeLists.txt
                                      + on HIP: device sources = one unity TU, host sources
                                        compiled as HIP, CUDA::cudart -> ${ALICEVISION_CUDA_LIBRARIES}
  * src/aliceVision/depthMap/cuda/hip/  new: compat shims + unity TU (copied from hip/compat, hip/port)
"""
from __future__ import annotations
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
AV = ROOT / "third_party" / "aliceVision"
MARK = "# --- cheshire HIP backend ---"


def patch(path: Path, anchor: str, new: str, *, after: bool = True, once_marker: str = MARK) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return  # already applied (exact block present)
    if anchor not in text:
        sys.exit(f"anchor not found in {path}:\n{anchor}")
    text = text.replace(anchor, (anchor + new) if after else (new + anchor), 1)
    path.write_text(text, encoding="utf-8", newline="\n")


TRACKED = [
    "src/cmake/config.hpp.in",
    "src/CMakeLists.txt",
    "src/aliceVision/depthMap/CMakeLists.txt",
    "src/aliceVision/mvsData/ROI.hpp",
    "src/aliceVision/depthMap/BufPtr.hpp",
]


def main() -> None:
    # 0. always start from pristine upstream files so re-runs never stack edits
    subprocess.run(["git", "checkout", "--", *TRACKED], cwd=AV, check=True)

    # 1. new files: compat shims + unity TU inside the tree
    dst = AV / "src" / "aliceVision" / "depthMap" / "cuda" / "hip"
    dst.mkdir(parents=True, exist_ok=True)
    for f in ["cuda_runtime.h", "cuda_fp16.h", "math_constants.h"]:
        shutil.copy2(ROOT / "hip" / "compat" / "include" / f, dst / f)
    (dst / "cheshire").mkdir(exist_ok=True)
    shutil.copy2(ROOT / "hip" / "compat" / "include" / "cheshire" / "cuda_to_hip.h", dst / "cheshire" / "cuda_to_hip.h")
    shutil.copy2(ROOT / "hip" / "port" / "unity" / "depthmap_device_unity.hip", dst / "depthmap_device_unity.hip")
    # header overlay (2-line change) applied in place
    for rel in ["src/aliceVision/mvsData/ROI.hpp", "src/aliceVision/depthMap/BufPtr.hpp"]:
        p = AV / rel
        t = p.read_text(encoding="utf-8")
        t2 = t.replace("#if defined(__NVCC__)\n", "#if defined(__NVCC__) || defined(__HIPCC__)\n") \
              .replace("#if !defined(__NVCC__)\n", "#if !defined(__NVCC__) && !defined(__HIPCC__)\n")
        if t2 != t:
            p.write_text(t2, encoding="utf-8", newline="\n")

    # 2. config.hpp.in
    patch(AV / "src/cmake/config.hpp.in",
          "#define ALICEVISION_HAVE_SYCL() @ALICEVISION_HAVE_SYCL@\n",
          "\n// --- cheshire HIP backend ---\n// HIP build: the CUDA depth-map sources are compiled through a CUDA->HIP compat header,\n"
          "// so ALICEVISION_HAVE_CUDA stays 1 and this flag marks the AMD runtime underneath.\n"
          "#define ALICEVISION_HAVE_HIP() @ALICEVISION_HAVE_HIP@\n")

    # 3. src/CMakeLists.txt: option + detection block after the CUDA block
    patch(AV / "src/CMakeLists.txt",
          'trilean_option(ALICEVISION_USE_SYCL "Enable SYCL" AUTO)\n',
          f'{MARK}\ntrilean_option(ALICEVISION_USE_HIP "Enable HIP (AMD GPUs): compiles the CUDA depth-map backend through a CUDA->HIP compat layer" AUTO)\n')
    hip_block = f'''
# ==============================================================================
{MARK}
# HIP (AMD ROCm). Only considered when no CUDA toolkit was found. The existing CUDA
# depth-map sources are compiled as HIP through src/aliceVision/depthMap/cuda/hip/,
# so from the code's point of view ALICEVISION_HAVE_CUDA is 1.
# ==============================================================================
set(ALICEVISION_HAVE_HIP 0)
if (NOT ALICEVISION_HAVE_CUDA AND NOT ALICEVISION_USE_HIP STREQUAL "OFF")
    include(CheckLanguage)
    check_language(HIP)
    if (NOT CMAKE_HIP_COMPILER)
        if (ALICEVISION_USE_HIP STREQUAL "ON")
            message(SEND_ERROR "Failed to find a HIP compiler (set CMAKE_HIP_COMPILER to ROCm's clang++/clang-cl).")
        endif()
    else()
        enable_language(HIP)
        find_package(hip QUIET)
        if (hip_FOUND)
            set(ALICEVISION_HAVE_HIP 1)
            set(ALICEVISION_HAVE_CUDA 1)
            list(APPEND ALICEVISION_CUDA_LIBRARIES hip::host)
            set(ALICEVISION_HIP_DIR "${{CMAKE_CURRENT_SOURCE_DIR}}/aliceVision/depthMap/cuda/hip")
            # cuda_runtime.h / cuda_fp16.h / math_constants.h shims must win over any real CUDA headers
            include_directories(BEFORE "${{ALICEVISION_HIP_DIR}}")
            add_compile_definitions(__HIP_PLATFORM_AMD__=1)
            # nvcc pre-includes cuda_runtime.h into every .cu; clang does not
            if (CMAKE_HIP_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")
                add_compile_options("$<$<COMPILE_LANGUAGE:HIP>:/FI${{ALICEVISION_HIP_DIR}}/cheshire/cuda_to_hip.h>")
                add_compile_options("$<$<COMPILE_LANGUAGE:HIP>:/bigobj>")
            else()
                add_compile_options("$<$<COMPILE_LANGUAGE:HIP>:-include${{ALICEVISION_HIP_DIR}}/cheshire/cuda_to_hip.h>")
            endif()
            add_compile_options("$<$<COMPILE_LANGUAGE:HIP>:-Wno-ignored-attributes>" "$<$<COMPILE_LANGUAGE:HIP>:-Wno-unknown-attributes>")
            option(ALICEVISION_HIP_RDC "HIP relocatable device code (-fgpu-rdc) instead of the unity device TU; broken on Windows ROCm 7.2.1" OFF)
            message(STATUS "HIP found: ${{hip_VERSION}} (architectures: ${{CMAKE_HIP_ARCHITECTURES}})")
        elseif (ALICEVISION_USE_HIP STREQUAL "ON")
            message(SEND_ERROR "Failed to find the hip CMake package (add the ROCm root to CMAKE_PREFIX_PATH).")
        endif()
    endif()
endif()
'''
    patch(AV / "src/CMakeLists.txt",
          "# ==============================================================================\n# SYCL/AdaptiveCpp\n",
          hip_block, after=False)

    # 4. depthMap/CMakeLists.txt: HIP source handling + link line
    dm = AV / "src/aliceVision/depthMap/CMakeLists.txt"
    patch(dm,
          "alicevision_add_library(aliceVision_depthMap_cuda\n",
          f'''{MARK}
if (ALICEVISION_HAVE_HIP)
    set(depthMap_hip_device_sources cuda/hip/depthmap_device_unity.hip)
    if (ALICEVISION_HIP_RDC)
        set(depthMap_hip_device_sources
            cuda/device/DeviceCameraParams.cu cuda/device/DevicePatchPattern.cu
            cuda/imageProcessing/deviceGaussianFilter.cu cuda/imageProcessing/deviceColorConversion.cu
            cuda/imageProcessing/deviceMipmappedArray.cu
            cuda/planeSweeping/deviceDepthSimilarityMap.cu cuda/planeSweeping/deviceSimilarityVolume.cu)
        add_compile_options("$<$<COMPILE_LANGUAGE:HIP>:-fgpu-rdc>")
        add_link_options(-fgpu-rdc --hip-link)
    else()
        # the .cu files are pulled into the unity TU; keep them out of the build
        set_source_files_properties(
            cuda/device/DeviceCameraParams.cu cuda/device/DevicePatchPattern.cu
            cuda/imageProcessing/deviceGaussianFilter.cu cuda/imageProcessing/deviceColorConversion.cu
            cuda/imageProcessing/deviceMipmappedArray.cu
            cuda/planeSweeping/deviceDepthSimilarityMap.cu cuda/planeSweeping/deviceSimilarityVolume.cu
            PROPERTIES HEADER_FILE_ONLY true)
    endif()
    # everything that touches the runtime is compiled by the HIP compiler (host + device passes)
    set_source_files_properties(${{depthMap_hip_device_sources}} ${{depthMap_cuda_host_sources}} ${{depthMap_cuda_imageProcessing_sources}} ${{depthMap_cuda_planeSweeping_sources}} ${{depthMap_cuda_device_sources}}
        PROPERTIES LANGUAGE HIP)
    list(APPEND depthMap_cuda_files_sources ${{depthMap_hip_device_sources}})
endif()

''', after=False)
    t = dm.read_text(encoding="utf-8")
    if "        CUDA::cudart\n" in t:
        t = t.replace("        CUDA::cudart\n", "        ${ALICEVISION_CUDA_LIBRARIES}   # CUDA::cudart, or hip::host on a HIP build\n", 1)
        dm.write_text(t, encoding="utf-8", newline="\n")

    # 5. regenerate the reviewable patch
    subprocess.run(["git", "add", "-N", "src/aliceVision/depthMap/cuda/hip"], cwd=AV, check=True)
    diff = subprocess.run(["git", "diff", "--no-color"], cwd=AV, check=True, capture_output=True, text=True).stdout
    out = ROOT / "patches" / "0002-hip-backend-cmake.patch"
    out.write_text(diff, encoding="utf-8", newline="\n")
    print(f"applied; {len(diff.splitlines())} diff lines -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
