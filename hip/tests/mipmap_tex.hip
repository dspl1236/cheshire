// Cheshire smoke test 2: the exact texture features AliceVision depthMap needs.
//  - hipMallocMipmappedArray (float4 and half4 channel formats)
//  - hipGetMipmappedArrayLevel + surface write into a level (surf2Dwrite)
//  - texture object over the mipmapped array, linear filter, normalized coords
//  - tex2DLod<float4> sampling between levels
//  - pitched 2D memory texture (hipResourceTypePitch2D) as used for depth/sim maps
//  - managed memory and mapped pinned host memory (memory-bridge prerequisites)
#include <hip/hip_runtime.h>
#include <hip/hip_fp16.h>
#include <cstdio>
#include <cmath>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void fillLevel0(hipSurfaceObject_t surf, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    float4 v = make_float4((float)x, (float)y, 1.f, 1.f);
    surf2Dwrite(v, surf, x * (int)sizeof(float4), y);
}

__global__ void downsample(hipSurfaceObject_t dst, hipTextureObject_t src, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    float u = (x + 0.5f) / w, v = (y + 0.5f) / h;
    float4 c = tex2D<float4>(src, u, v);
    surf2Dwrite(c, dst, x * (int)sizeof(float4), y);
}

__global__ void sampleLod(hipTextureObject_t tex, float* out, int w, int h, float lod) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    float u = (x + 0.5f) / w, v = (y + 0.5f) / h;
    float4 c = tex2DLod<float4>(tex, u, v, lod);
    out[y * w + x] = c.x;
}

__global__ void samplePitch(hipTextureObject_t tex, float* out, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    out[y * w + x] = tex2D<float>(tex, x + 0.5f, y + 0.5f);
}

int main() {
    const int W = 256, H = 128, LEVELS = 4;
    hipChannelFormatDesc desc = hipCreateChannelDesc<float4>();
    hipMipmappedArray_t mip = nullptr;
    hipExtent ext = make_hipExtent(W, H, 0);
    CHK(hipMallocMipmappedArray(&mip, &desc, ext, LEVELS, hipArraySurfaceLoadStore));
    std::printf("hipMallocMipmappedArray float4 %dx%d x%d levels: OK\n", W, H, LEVELS);

    // level 0 fill via surface
    std::vector<hipArray_t> lv(LEVELS);
    for (int l = 0; l < LEVELS; ++l) CHK(hipGetMipmappedArrayLevel(&lv[l], mip, l));
    hipResourceDesc rd{}; rd.resType = hipResourceTypeArray; rd.res.array.array = lv[0];
    hipSurfaceObject_t s0; CHK(hipCreateSurfaceObject(&s0, &rd));
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    fillLevel0<<<g, b>>>(s0, W, H); CHK(hipGetLastError()); CHK(hipDeviceSynchronize());
    std::printf("surf2Dwrite level0: OK\n");

    // build levels 1..n by sampling the previous level through a texture (AliceVision pattern)
    for (int l = 1; l < LEVELS; ++l) {
        int w = W >> l, h = H >> l;
        hipResourceDesc prd{}; prd.resType = hipResourceTypeArray; prd.res.array.array = lv[l - 1];
        hipTextureDesc td{}; td.addressMode[0] = td.addressMode[1] = hipAddressModeClamp;
        td.filterMode = hipFilterModeLinear; td.readMode = hipReadModeElementType; td.normalizedCoords = 1;
        hipTextureObject_t pt; CHK(hipCreateTextureObject(&pt, &prd, &td, nullptr));
        hipResourceDesc srd{}; srd.resType = hipResourceTypeArray; srd.res.array.array = lv[l];
        hipSurfaceObject_t sl; CHK(hipCreateSurfaceObject(&sl, &srd));
        dim3 gl((w + 15) / 16, (h + 15) / 16);
        downsample<<<gl, b>>>(sl, pt, w, h); CHK(hipGetLastError()); CHK(hipDeviceSynchronize());
        CHK(hipDestroyTextureObject(pt)); CHK(hipDestroySurfaceObject(sl));
    }
    std::printf("mip chain built via tex2D+surf2Dwrite: OK\n");

    // texture object over the whole mipmapped array, sample with tex2DLod
    hipResourceDesc mrd{}; mrd.resType = hipResourceTypeMipmappedArray; mrd.res.mipmap.mipmap = mip;
    hipTextureDesc mtd{}; mtd.addressMode[0] = mtd.addressMode[1] = hipAddressModeClamp;
    mtd.filterMode = hipFilterModeLinear; mtd.mipmapFilterMode = hipFilterModeLinear;
    mtd.readMode = hipReadModeElementType; mtd.normalizedCoords = 1;
    mtd.maxMipmapLevelClamp = (float)(LEVELS - 1); mtd.minMipmapLevelClamp = 0;
    hipTextureObject_t mt; CHK(hipCreateTextureObject(&mt, &mrd, &mtd, nullptr));
    float* dout; CHK(hipMalloc(&dout, W * H * 4));
    std::vector<float> out(W * H);
    int bad = 0;
    const float lods[3] = {0.f, 1.f, 2.5f};
    for (int li = 0; li < 3; ++li) {
        float lod = lods[li];
        sampleLod<<<g, b>>>(mt, dout, W, H, lod); CHK(hipGetLastError());
        CHK(hipMemcpy(out.data(), dout, W * H * 4, hipMemcpyDeviceToHost));
        // level0 stores x in .x; a box-averaged ramp stays a ramp, so any lod should return ~x
        int lbad = 0;
        for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) if (std::fabs(out[y * W + x] - x) > 1.5f + lod) ++lbad;
        std::printf("tex2DLod lod=%.1f: %s (%d off, sample[10,10]=%.2f)\n", lod, lbad ? "MISMATCH" : "OK", lbad, out[10 * W + 10]);
        bad += lbad;
    }

    // pitched 2D float texture (depth/sim maps use hipResourceTypePitch2D)
    float* dp; size_t pitch; CHK(hipMallocPitch((void**)&dp, &pitch, W * 4, H));
    std::vector<float> hp(W * H); for (int i = 0; i < W * H; ++i) hp[i] = (float)(i % 97);
    CHK(hipMemcpy2D(dp, pitch, hp.data(), W * 4, W * 4, H, hipMemcpyHostToDevice));
    hipResourceDesc prd2{}; prd2.resType = hipResourceTypePitch2D; prd2.res.pitch2D.devPtr = dp;
    prd2.res.pitch2D.desc = hipCreateChannelDesc<float>(); prd2.res.pitch2D.width = W; prd2.res.pitch2D.height = H; prd2.res.pitch2D.pitchInBytes = pitch;
    hipTextureDesc ptd{}; ptd.addressMode[0] = ptd.addressMode[1] = hipAddressModeClamp; ptd.filterMode = hipFilterModePoint; ptd.readMode = hipReadModeElementType; ptd.normalizedCoords = 0;
    hipTextureObject_t pt2; CHK(hipCreateTextureObject(&pt2, &prd2, &ptd, nullptr));
    samplePitch<<<g, b>>>(pt2, dout, W, H); CHK(hipGetLastError());
    CHK(hipMemcpy(out.data(), dout, W * H * 4, hipMemcpyDeviceToHost));
    int pbad = 0; for (int i = 0; i < W * H; ++i) if (out[i] != hp[i]) ++pbad;
    std::printf("pitch2D float texture: %s (%d bad)\n", pbad ? "FAIL" : "OK", pbad); bad += pbad;

    // half4 mipmapped array allocation (AliceVision's ALICEVISION_DEPTHMAP_TEXTURE_USE_HALF path)
    hipChannelFormatDesc hd = hipCreateChannelDescHalf4();
    hipMipmappedArray_t mipH = nullptr;
    hipError_t eh = hipMallocMipmappedArray(&mipH, &hd, ext, LEVELS, hipArraySurfaceLoadStore);
    std::printf("hipMallocMipmappedArray half4: %s\n", eh == hipSuccess ? "OK" : hipGetErrorString(eh));
    if (eh == hipSuccess) CHK(hipFreeMipmappedArray(mipH));

    // managed + pinned host memory availability (memory bridge prerequisites)
    void* mm = nullptr; hipError_t em = hipMallocManaged(&mm, 64 << 20);
    std::printf("hipMallocManaged 64MB: %s\n", em == hipSuccess ? "OK" : hipGetErrorString(em)); if (em == hipSuccess) hipFree(mm);
    void* hm = nullptr; hipError_t ep = hipHostMalloc(&hm, 64 << 20, hipHostMallocMapped);
    void* dptr = nullptr; if (ep == hipSuccess) ep = hipHostGetDevicePointer(&dptr, hm, 0);
    std::printf("hipHostMalloc(mapped)+device ptr: %s\n", ep == hipSuccess ? "OK" : hipGetErrorString(ep)); if (hm) hipHostFree(hm);

    CHK(hipDestroyTextureObject(mt)); CHK(hipDestroyTextureObject(pt2)); CHK(hipDestroySurfaceObject(s0));
    CHK(hipFree(dout)); CHK(hipFree(dp)); CHK(hipFreeMipmappedArray(mip));
    std::printf("RESULT: %s\n", bad ? "FAIL" : "ALL OK");
    return bad ? 2 : 0;
}
