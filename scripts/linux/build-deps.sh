#!/usr/bin/env bash
# Cheshire Linux: build AliceVision's third-party dependencies with its own superbuild
# (ALICEVISION_BUILD_DEPENDENCIES=ON), CUDA-free. Tested in WSL2 Ubuntu 24.04 with ROCm 7.2.
# Usage: scripts/linux/build-deps.sh [install-prefix] [build-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AV_DEV="$ROOT/third_party/aliceVision"
AV_INSTALL="${1:-/opt/AliceVision_deps}"
AV_BUILD="${2:-$HOME/av-deps-build}"
JOBS="${JOBS:-$(nproc)}"
mkdir -p "$AV_BUILD" "$AV_INSTALL/lib"
ln -sfn lib "$AV_INSTALL/lib64"
cd "$AV_BUILD"
cmake "$AV_DEV" \
  -DCMAKE_BUILD_TYPE=Release \
  -DALICEVISION_BUILD_DEPENDENCIES:BOOL=ON \
  -DAV_BUILD_ALICEVISION:BOOL=OFF \
  -DCMAKE_INSTALL_PREFIX="$AV_INSTALL" \
  -DAV_BUILD_ZLIB:BOOL=ON \
  -DAV_BUILD_CUDA:BOOL=OFF \
  -DAV_BUILD_POPSIFT:BOOL=OFF \
  -DAV_BUILD_CCTAG:BOOL=OFF \
  -DAV_BUILD_APRILTAG:BOOL=OFF \
  -DAV_BUILD_USD:BOOL=OFF \
  -DAV_BUILD_PCL:BOOL=OFF \
  -DAV_BUILD_E57FORMAT:BOOL=OFF \
  -DAV_BUILD_OPENCV:BOOL=OFF \
  -DAV_BUILD_ONNXRUNTIME:BOOL=OFF \
  -DAV_BUILD_FFMPEG:BOOL=OFF \
  -DAV_BUILD_VPX:BOOL=OFF \
  -DAV_BUILD_PYBIND11:BOOL=OFF \
  -DAV_BUILD_SWIG:BOOL=OFF \
  -DPython_EXECUTABLE="$(command -v python3)"
cmake --build . --parallel "$JOBS"
# the superbuild drops dependency tools into bin/; keep them out of the AliceVision bin
if [ -d "$AV_INSTALL/bin" ] && [ ! -d "$AV_INSTALL/bin-deps" ]; then mv "$AV_INSTALL/bin" "$AV_INSTALL/bin-deps"; fi
echo "DEPS OK -> $AV_INSTALL"
