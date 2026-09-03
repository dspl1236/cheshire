// Cheshire "conversion API": compile AliceVision's CUDA depth-map sources as HIP
// without rewriting them. Force-included (clang -include / clang-cl /FI) or pulled in
// through the cuda_runtime.h shim next to this file.
//
// Style follows llama.cpp's ggml-cuda/vendors/hip.h: a flat macro map from the CUDA
// runtime names the sources use to their HIP equivalents. Only names that the
// AliceVision depthMap tree actually uses are mapped (grep-derived, see
// docs/00-scope-and-findings.md); add to it when a new one shows up in a build error.
#pragma once

#if !defined(__HIP_PLATFORM_AMD__) && !defined(__HIP_PLATFORM_NVIDIA__)
#define __HIP_PLATFORM_AMD__ 1
#endif
#include <hip/hip_runtime.h>
#include <hip/hip_fp16.h>
#include <hip/hip_math_constants.h>

#define CHESHIRE_HIP 1

// ---- error handling -------------------------------------------------------
#define cudaError_t hipError_t
#define cudaSuccess hipSuccess
#define cudaErrorMemoryAllocation hipErrorOutOfMemory
#define cudaGetErrorString hipGetErrorString
#define cudaGetErrorName hipGetErrorName
#define cudaGetLastError hipGetLastError
#define cudaPeekAtLastError hipPeekAtLastError

// ---- device management ----------------------------------------------------
#define cudaDeviceProp hipDeviceProp_t
#define cudaGetDeviceCount hipGetDeviceCount
#define cudaGetDeviceProperties hipGetDeviceProperties
#define cudaGetDevice hipGetDevice
#define cudaSetDevice hipSetDevice
#define cudaDeviceSynchronize hipDeviceSynchronize
#define cudaDeviceReset hipDeviceReset
#define cudaMemGetInfo hipMemGetInfo
#define cudaOccupancyMaxPotentialBlockSize hipOccupancyMaxPotentialBlockSize
#define cudaFuncSetCacheConfig hipFuncSetCacheConfig
#define cudaFuncCachePreferL1 hipFuncCachePreferL1
#define cudaFuncCachePreferShared hipFuncCachePreferShared

// ---- streams --------------------------------------------------------------
#define cudaStream_t hipStream_t
#define cudaStreamCreate hipStreamCreate
#define cudaStreamCreateWithFlags hipStreamCreateWithFlags
#define cudaStreamDestroy hipStreamDestroy
#define cudaStreamSynchronize hipStreamSynchronize
#define cudaStreamNonBlocking hipStreamNonBlocking
#define cudaStreamDefault hipStreamDefault
#define cudaEvent_t hipEvent_t
#define cudaEventCreate hipEventCreate
#define cudaEventRecord hipEventRecord
#define cudaEventSynchronize hipEventSynchronize
#define cudaEventDestroy hipEventDestroy
#define cudaEventElapsedTime hipEventElapsedTime

// ---- memory ---------------------------------------------------------------
#define cudaMalloc hipMalloc
#define cudaFree hipFree
#define cudaMallocHost hipHostMalloc
#define cudaFreeHost hipHostFree
#define cudaMallocManaged hipMallocManaged
#define cudaHostAlloc hipHostMalloc
#define cudaHostAllocMapped hipHostMallocMapped
#define cudaHostGetDevicePointer hipHostGetDevicePointer
// cudaMallocPitch has a templated overload in cuda_runtime.h (AliceVision calls
// cudaMallocPitch<Type>(&buf, ...)); HIP only has the C function, so provide both forms.
inline hipError_t cudaMallocPitch(void** devPtr, size_t* pitch, size_t width, size_t height)
{ return hipMallocPitch(devPtr, pitch, width, height); }
template<class T>
inline hipError_t cudaMallocPitch(T** devPtr, size_t* pitch, size_t width, size_t height)
{ return hipMallocPitch(reinterpret_cast<void**>(devPtr), pitch, width, height); }
#define cudaMalloc3D hipMalloc3D
#define cudaMemset hipMemset
#define cudaMemsetAsync hipMemsetAsync
#define cudaMemset2D hipMemset2D
#define cudaMemset2DAsync hipMemset2DAsync
#define cudaMemcpy hipMemcpy
#define cudaMemcpyAsync hipMemcpyAsync
#define cudaMemcpy2D hipMemcpy2D
#define cudaMemcpy2DAsync hipMemcpy2DAsync
#define cudaMemcpy3D hipMemcpy3D
#define cudaMemcpy3DAsync hipMemcpy3DAsync
#define cudaMemcpy3DParms hipMemcpy3DParms
#define cudaMemcpyToSymbol hipMemcpyToSymbol
#define cudaMemcpyToSymbolAsync hipMemcpyToSymbolAsync
#define cudaMemcpyFromSymbol hipMemcpyFromSymbol
#define cudaMemcpyKind hipMemcpyKind
#define cudaMemcpyHostToDevice hipMemcpyHostToDevice
#define cudaMemcpyDeviceToHost hipMemcpyDeviceToHost
#define cudaMemcpyDeviceToDevice hipMemcpyDeviceToDevice
#define cudaMemcpyHostToHost hipMemcpyHostToHost
#define cudaMemcpyDefault hipMemcpyDefault
#define cudaPitchedPtr hipPitchedPtr
#define make_cudaPitchedPtr make_hipPitchedPtr
#define cudaExtent hipExtent
#define make_cudaExtent make_hipExtent
#define cudaPos hipPos
#define make_cudaPos make_hipPos

// ---- arrays / mipmaps -----------------------------------------------------
#define cudaArray hipArray
#define cudaArray_t hipArray_t
#define cudaArrayGetInfo hipArrayGetInfo
#define cudaMallocArray hipMallocArray
#define cudaFreeArray hipFreeArray
#define cudaArrayDefault hipArrayDefault
#define cudaArraySurfaceLoadStore hipArraySurfaceLoadStore
#define cudaMipmappedArray_t hipMipmappedArray_t
#define cudaMallocMipmappedArray hipMallocMipmappedArray
#define cudaFreeMipmappedArray hipFreeMipmappedArray
#define cudaGetMipmappedArrayLevel hipGetMipmappedArrayLevel
#define cudaChannelFormatDesc hipChannelFormatDesc
#define cudaCreateChannelDesc hipCreateChannelDesc
#define cudaCreateChannelDescHalf hipCreateChannelDescHalf
#define cudaCreateChannelDescHalf1 hipCreateChannelDescHalf1
#define cudaCreateChannelDescHalf2 hipCreateChannelDescHalf2
#define cudaCreateChannelDescHalf4 hipCreateChannelDescHalf4
#define cudaChannelFormatKindFloat hipChannelFormatKindFloat
#define cudaChannelFormatKindUnsigned hipChannelFormatKindUnsigned
#define cudaChannelFormatKindSigned hipChannelFormatKindSigned

// ---- texture / surface objects -------------------------------------------
#define cudaTextureObject_t hipTextureObject_t
#define cudaSurfaceObject_t hipSurfaceObject_t
#define cudaCreateTextureObject hipCreateTextureObject
#define cudaDestroyTextureObject hipDestroyTextureObject
#define cudaCreateSurfaceObject hipCreateSurfaceObject
#define cudaDestroySurfaceObject hipDestroySurfaceObject
#define cudaResourceDesc hipResourceDesc
#define cudaTextureDesc hipTextureDesc
#define cudaResourceViewDesc hipResourceViewDesc
#define cudaResourceTypeArray hipResourceTypeArray
#define cudaResourceTypeMipmappedArray hipResourceTypeMipmappedArray
#define cudaResourceTypeLinear hipResourceTypeLinear
#define cudaResourceTypePitch2D hipResourceTypePitch2D
#define cudaAddressModeClamp hipAddressModeClamp
#define cudaAddressModeWrap hipAddressModeWrap
#define cudaAddressModeBorder hipAddressModeBorder
#define cudaAddressModeMirror hipAddressModeMirror
#define cudaFilterModePoint hipFilterModePoint
#define cudaFilterModeLinear hipFilterModeLinear
#define cudaReadModeElementType hipReadModeElementType
#define cudaReadModeNormalizedFloat hipReadModeNormalizedFloat
// AliceVision uses these two spellings in places
#define cudaReadElementType hipReadModeElementType
#define cudaReadNormalizedFloat hipReadModeNormalizedFloat
#define cudaBoundaryModeZero hipBoundaryModeZero
#define cudaBoundaryModeClamp hipBoundaryModeClamp
#define cudaBoundaryModeTrap hipBoundaryModeTrap

// ---- half precision (names are identical in hip_fp16.h) -------------------
// __half, __half2, half, half2, __float2half, __half2float: no mapping needed.

// ---- math constants (math_constants.h) ------------------------------------
// hip_math_constants.h provides HIP_PI_F etc.; CUDA names are CUDART_*.
#ifndef CUDART_PI_F
#define CUDART_PI_F 3.14159265358979323846f
#define CUDART_PI 3.14159265358979323846
#endif
#ifndef CUDART_INF_F
#define CUDART_INF_F __builtin_inff()
#define CUDART_INF __builtin_inf()
#endif
#ifndef CUDART_NAN_F
#define CUDART_NAN_F __builtin_nanf("")
#define CUDART_NAN __builtin_nan("")
#endif
#ifndef CUDART_MAX_NORMAL_F
#define CUDART_MAX_NORMAL_F 3.402823466e38f
#endif
#ifndef CUDART_MIN_DENORM_F
#define CUDART_MIN_DENORM_F 1.401298464e-45f
#endif
#ifndef CUDART_VERSION
#define CUDART_VERSION HIP_VERSION
#endif

// ---- things that are the same in HIP and need no map ----------------------
// __global__ __device__ __host__ __constant__ __shared__ __forceinline__
// dim3, blockIdx/blockDim/threadIdx/gridDim, __syncthreads, make_float4 ...
// tex2D<T>, tex2DLod<T>, surf2Dwrite, atomicAdd ...
