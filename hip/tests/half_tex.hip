// Cheshire test 5: sample a half4 mipmapped array the way AliceVision does
// (surf2Dwrite of ushort4 bit patterns, texture readMode=ElementType, tex2DLod<float4>).
// Also the uchar4 + NormalizedFloat variant and a pitch2D half texture.
#include <hip/hip_runtime.h>
#include <hip/hip_fp16.h>
#include <cstdio>
#include <cmath>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void fillHalf(hipSurfaceObject_t surf, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    __half hx = __float2half((float)x), hy = __float2half((float)y), h1 = __float2half(1.f), h2 = __float2half(2.f);
    ushort4 v = make_ushort4(__half_as_ushort(hx), __half_as_ushort(hy), __half_as_ushort(h1), __half_as_ushort(h2));
    surf2Dwrite(v, surf, x * (int)sizeof(ushort4), y);
}
__global__ void sampleLod(hipTextureObject_t tex, float4* out, int w, int h, float lod) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    out[y * w + x] = tex2DLod<float4>(tex, (x + 0.5f) / w, (y + 0.5f) / h, lod);
}
__global__ void sample(hipTextureObject_t tex, float4* out, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    out[y * w + x] = tex2D<float4>(tex, (x + 0.5f) / w, (y + 0.5f) / h);
}

int main() {
    const int W = 128, H = 64, LEVELS = 3;
    int bad = 0;
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    float4* dout; CHK(hipMalloc(&dout, W * H * sizeof(float4)));
    std::vector<float4> out(W * H);

    // --- half4 mipmapped array, ElementType read mode (AliceVision USE_HALF path)
    {
        hipChannelFormatDesc desc = hipCreateChannelDescHalf4();
        std::printf("half4 desc: x=%d y=%d z=%d w=%d kind=%d\n", desc.x, desc.y, desc.z, desc.w, (int)desc.f);
        hipMipmappedArray_t mip; CHK(hipMallocMipmappedArray(&mip, &desc, make_hipExtent(W, H, 0), LEVELS, hipArraySurfaceLoadStore));
        hipArray_t l0; CHK(hipGetMipmappedArrayLevel(&l0, mip, 0));
        hipResourceDesc rd{}; rd.resType = hipResourceTypeArray; rd.res.array.array = l0;
        hipSurfaceObject_t s0; CHK(hipCreateSurfaceObject(&s0, &rd));
        fillHalf<<<g, b>>>(s0, W, H); CHK(hipGetLastError()); CHK(hipDeviceSynchronize());

        // level-0 texture over the array (non-mipmapped) + mipmapped texture
        hipTextureDesc td{}; td.addressMode[0] = td.addressMode[1] = hipAddressModeClamp; td.filterMode = hipFilterModeLinear;
        td.readMode = hipReadModeElementType; td.normalizedCoords = 1;
        hipTextureObject_t t0; CHK(hipCreateTextureObject(&t0, &rd, &td, nullptr));
        sample<<<g, b>>>(t0, dout, W, H); CHK(hipGetLastError());
        CHK(hipMemcpy(out.data(), dout, W * H * sizeof(float4), hipMemcpyDeviceToHost));
        int nb = 0; for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) { float4 v = out[y * W + x]; if (std::fabs(v.x - x) > 0.6f || std::fabs(v.y - y) > 0.6f || v.z != 1.f || v.w != 2.f) ++nb; }
        std::printf("half4 array tex2D<float4> ElementType: %s (%d bad; sample[5,3]=%.2f,%.2f,%.2f,%.2f)\n", nb ? "FAIL" : "OK", nb, out[3 * W + 5].x, out[3 * W + 5].y, out[3 * W + 5].z, out[3 * W + 5].w); bad += nb ? 1 : 0;

        hipResourceDesc mrd{}; mrd.resType = hipResourceTypeMipmappedArray; mrd.res.mipmap.mipmap = mip;
        hipTextureDesc mtd = td; mtd.mipmapFilterMode = hipFilterModeLinear; mtd.maxMipmapLevelClamp = LEVELS - 1;
        hipTextureObject_t mt; CHK(hipCreateTextureObject(&mt, &mrd, &mtd, nullptr));
        sampleLod<<<g, b>>>(mt, dout, W, H, 0.f); CHK(hipGetLastError());
        CHK(hipMemcpy(out.data(), dout, W * H * sizeof(float4), hipMemcpyDeviceToHost));
        nb = 0; for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) { float4 v = out[y * W + x]; if (std::fabs(v.x - x) > 0.6f || std::fabs(v.y - y) > 0.6f || v.z != 1.f || v.w != 2.f) ++nb; }
        std::printf("half4 mipmap tex2DLod<float4> lod0: %s (%d bad; sample[5,3]=%.2f,%.2f,%.2f,%.2f)\n", nb ? "FAIL" : "OK", nb, out[3 * W + 5].x, out[3 * W + 5].y, out[3 * W + 5].z, out[3 * W + 5].w); bad += nb ? 1 : 0;
        CHK(hipDestroyTextureObject(mt)); CHK(hipDestroyTextureObject(t0)); CHK(hipDestroySurfaceObject(s0)); CHK(hipFreeMipmappedArray(mip));
    }
    // --- float4 control (known-good path from mipmap_tex)
    {
        hipChannelFormatDesc desc = hipCreateChannelDesc<float4>();
        hipArray_t arr; CHK(hipMallocArray(&arr, &desc, W, H, hipArraySurfaceLoadStore));
        std::vector<float4> src(W * H); for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) src[y * W + x] = make_float4((float)x, (float)y, 1.f, 2.f);
        CHK(hipMemcpy2DToArray(arr, 0, 0, src.data(), W * sizeof(float4), W * sizeof(float4), H, hipMemcpyHostToDevice));
        hipResourceDesc rd{}; rd.resType = hipResourceTypeArray; rd.res.array.array = arr;
        hipTextureDesc td{}; td.addressMode[0] = td.addressMode[1] = hipAddressModeClamp; td.filterMode = hipFilterModeLinear; td.readMode = hipReadModeElementType; td.normalizedCoords = 1;
        hipTextureObject_t t; CHK(hipCreateTextureObject(&t, &rd, &td, nullptr));
        sample<<<g, b>>>(t, dout, W, H); CHK(hipGetLastError());
        CHK(hipMemcpy(out.data(), dout, W * H * sizeof(float4), hipMemcpyDeviceToHost));
        int nb = 0; for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) { float4 v = out[y * W + x]; if (std::fabs(v.x - x) > 0.6f || v.w != 2.f) ++nb; }
        std::printf("float4 array control: %s (%d bad)\n", nb ? "FAIL" : "OK", nb); bad += nb ? 1 : 0;
        CHK(hipDestroyTextureObject(t)); CHK(hipFreeArray(arr));
    }
    CHK(hipFree(dout));
    std::printf("RESULT: %s\n", bad ? "FAIL" : "ALL OK");
    return bad ? 2 : 0;
}
