cmake_minimum_required(VERSION 3.28)
# Cheshire standalone port build: compile AliceVision's depthMap/cuda tree as HIP,
# unmodified, through the cuda_to_hip compat layer. Compile-only object library first;
# linking into the real AliceVision comes with the full vcpkg build.
project(cheshire_depthmap_port LANGUAGES CXX HIP)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_HIP_STANDARD 17)
if(NOT CMAKE_HIP_ARCHITECTURES)
  set(CMAKE_HIP_ARCHITECTURES gfx1201)
endif()
find_package(hip REQUIRED)

set(CHESHIRE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(AV_SRC "${CHESHIRE_ROOT}/third_party/aliceVision/src")
set(AV_DM "${AV_SRC}/aliceVision/depthMap")
# vcpkg prebuilt dependency tree (Boost, Eigen, OpenImageIO headers are enough to compile)
set(CHESHIRE_VCPKG_INSTALLED "${CHESHIRE_ROOT}/tools/vcpkg-deps/x64-windows-release/installed/x64-windows-release"
    CACHE PATH "vcpkg installed tree for AliceVision deps")

# ---- sources: exactly the lists from third_party/aliceVision/src/aliceVision/depthMap/CMakeLists.txt
set(port_cu
  ${AV_DM}/cuda/device/DeviceCameraParams.cu
  ${AV_DM}/cuda/device/DevicePatchPattern.cu
  ${AV_DM}/cuda/imageProcessing/deviceGaussianFilter.cu
  ${AV_DM}/cuda/imageProcessing/deviceColorConversion.cu
  ${AV_DM}/cuda/imageProcessing/deviceMipmappedArray.cu
  ${AV_DM}/cuda/planeSweeping/deviceDepthSimilarityMap.cu
  ${AV_DM}/cuda/planeSweeping/deviceSimilarityVolume.cu
)
set(port_host_cpp
  ${AV_DM}/cuda/host/DeviceCache.cpp
  ${AV_DM}/cuda/host/DeviceMipmapImage.cpp
  ${AV_DM}/cuda/host/DeviceStreamManager.cpp
  ${AV_DM}/cuda/host/patchPattern.cpp
  ${AV_DM}/cuda/host/utils.cpp
)
# .cu files are HIP to CMake; host .cpp files include cuda_runtime.h and are compiled as
# HIP too so the compat shim and hip headers resolve identically (CUDA_SEPARABLE_COMPILATION
# in upstream implies nvcc handled them; here clang does).
set_source_files_properties(${port_cu} ${port_host_cpp} PROPERTIES LANGUAGE HIP)

add_library(cheshire_depthmap_port OBJECT ${port_cu} ${port_host_cpp})
target_include_directories(cheshire_depthmap_port BEFORE PRIVATE
  ${CHESHIRE_ROOT}/hip/compat/include          # cuda_runtime.h / cuda_fp16.h / math_constants.h shims
  ${CHESHIRE_ROOT}/hip/port/generated          # aliceVision/config.hpp stand-in
  ${AV_SRC}
  ${CHESHIRE_VCPKG_INSTALLED}/include
  ${CHESHIRE_VCPKG_INSTALLED}/include/eigen3
)
target_compile_definitions(cheshire_depthmap_port PRIVATE
  BOOST_ALL_NO_LIB
  BOOST_LOG_DYN_LINK
  _USE_MATH_DEFINES
  NOMINMAX
)
target_link_libraries(cheshire_depthmap_port PRIVATE hip::device)
