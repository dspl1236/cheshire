// Cheshire standalone-port stand-in for AliceVision's CMake-generated config.hpp.
// The HIP backend compiles the existing CUDA sources, so from the code's point of view
// the DEPTHMAP backend *is* the CUDA one.
#pragma once

#define ALICEVISION_IS_DEFINED(F) F() == 1

#define ALICEVISION_HAVE_OPENMP() 1
#define ALICEVISION_HAVE_SSE() 0
#define ALICEVISION_HAVE_MOSEK() 0
#define ALICEVISION_HAVE_OPENCV() 0
#define ALICEVISION_HAVE_OCVSIFT() 0
#define ALICEVISION_HAVE_ALEMBIC() 0
#define ALICEVISION_HAVE_USD() 0
#define ALICEVISION_HAVE_CCTAG() 0
#define ALICEVISION_HAVE_APRILTAG() 0
#define ALICEVISION_HAVE_POPSIFT() 0
#define ALICEVISION_HAVE_CUDA() 1
#define ALICEVISION_HAVE_SYCL() 0
#define ALICEVISION_DEPTHMAP_BACKEND_CUDA() 1
#define ALICEVISION_DEPTHMAP_BACKEND_SYCL() 0
#define ALICEVISION_HAVE_ONNX() 0
#define ALICEVISION_HAVE_ONNX_GPU() 0
#define ALICEVISION_HAVE_HIP() 1
