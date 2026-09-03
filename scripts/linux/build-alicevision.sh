#!/usr/bin/env bash
# Cheshire Linux: build AliceVision with the HIP depth-map backend against the superbuild
# dependencies (scripts/linux/build-deps.sh) and ROCm in /opt/rocm.
# Usage: scripts/linux/build-alicevision.sh [configure|build|install|bundle] [gfx list]
#   gfx list default: gfx1201;gfx1200;gfx1100;gfx1101;gfx1102  (RDNA4 + RDNA3)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AV_DEV="$ROOT/third_party/aliceVision"
STEP="${1:-install}"
ARCHS="${2:-gfx1201;gfx1200;gfx1100;gfx1101;gfx1102}"
ROCM="${ROCM_PATH:-/opt/rocm}"
AV_DEPS="${AV_DEPS:-/opt/AliceVision_deps}"
AV_BUILD="${AV_BUILD:-$HOME/av-hip-build}"
AV_INSTALL="${AV_INSTALL:-/opt/AliceVision_hip}"
AV_BUNDLE="${AV_BUNDLE:-$AV_INSTALL/bundle}"
JOBS="${JOBS:-$(nproc)}"

python3 "$ROOT/scripts/apply_hip_patch.py"

mkdir -p "$AV_BUILD"
cd "$AV_BUILD"
cmake "$AV_DEV" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$AV_DEPS;$ROCM" \
  -DCMAKE_INSTALL_PREFIX="$AV_INSTALL" \
  -DALICEVISION_BUNDLE_PREFIX="$AV_BUNDLE" \
  -DCMAKE_HIP_COMPILER="$ROCM/lib/llvm/bin/clang++" \
  -DCMAKE_HIP_ARCHITECTURES="$ARCHS" \
  -DALICEVISION_USE_CUDA=OFF -DALICEVISION_USE_HIP=ON -DALICEVISION_USE_SYCL=OFF \
  -DALICEVISION_USE_POPSIFT=OFF -DALICEVISION_USE_CCTAG=OFF -DALICEVISION_USE_APRILTAG=OFF \
  -DALICEVISION_USE_OPENCV=OFF -DALICEVISION_USE_ONNX=OFF -DALICEVISION_USE_ONNX_GPU=OFF \
  -DALICEVISION_USE_USD=OFF -DALICEVISION_USE_ALEMBIC=ON -DALICEVISION_BUILD_LIDAR=OFF \
  -DALICEVISION_BUILD_TESTS=OFF -DALICEVISION_BUILD_DOC=OFF -DALICEVISION_BUILD_SWIG_BINDING=OFF \
  -DMINIGLOG=ON -DTARGET_ARCHITECTURE=core \
  ${CHESHIRE_CMAKE_EXTRA:-}
[ "$STEP" = configure ] && exit 0
cmake --build . --parallel "$JOBS"
[ "$STEP" = build ] && exit 0
cmake --install .
[ "$STEP" = install ] && exit 0
cmake --build . --target bundle
echo "BUNDLE -> $AV_BUNDLE"
