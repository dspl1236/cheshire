// Cheshire probe: which texture formats / read modes work on this HIP stack.
#include <hip/hip_runtime.h>
#include <hip/hip_fp16.h>
#include <cstdio>
#include <cmath>
#include <vector>
#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { std::fprintf(stderr, "HIP error %s at %s:%d\n", hipGetErrorString(e), __FILE__, __LINE__); return 1; } } while (0)

__global__ void sampleF4(hipTextureObject_t t, float4* out, int w, int h) { int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y; if (x < w && y < h) out[y * w + x] = tex2D<float4>(t, (x + 0.5f) / w, (y + 0.5f) / h); }
__global__ void sampleU4(hipTextureObject_t t, float4* out, int w, int h) { int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y; if (x < w && y < h) { uchar4 v = tex2D<uchar4>(t, x + 0.5f, y + 0.5f); out[y * w + x] = make_float4(v.x, v.y, v.z, v.w); } }
__global__ void sampleF4unnorm(hipTextureObject_t t, float4* out, int w, int h) { int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y; if (x < w && y < h) out[y * w + x] = tex2D<float4>(t, x + 0.5f, y + 0.5f); }

template<class T> static int run(const char* name, hipChannelFormatDesc desc, const std::vector<T>& src, int W, int H, hipTextureReadMode rm, hipTextureFilterMode fm, bool norm, int which, float scale) {
    hipArray_t arr; CHK(hipMallocArray(&arr, &desc, W, H, hipArrayDefault));
    CHK(hipMemcpy2DToArray(arr, 0, 0, src.data(), W * sizeof(T), W * sizeof(T), H, hipMemcpyHostToDevice));
    hipResourceDesc rd{}; rd.resType = hipResourceTypeArray; rd.res.array.array = arr;
    hipTextureDesc td{}; td.addressMode[0] = td.addressMode[1] = hipAddressModeClamp; td.filterMode = fm; td.readMode = rm; td.normalizedCoords = norm ? 1 : 0;
    hipTextureObject_t t; hipError_t e = hipCreateTextureObject(&t, &rd, &td, nullptr);
    if (e != hipSuccess) { std::printf("%-58s create FAILED: %s\n", name, hipGetErrorString(e)); (void)hipFreeArray(arr); return 1; }
    float4* d; CHK(hipMalloc(&d, W * H * sizeof(float4)));
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    if (which == 0) sampleF4<<<g, b>>>(t, d, W, H); else if (which == 1) sampleU4<<<g, b>>>(t, d, W, H); else sampleF4unnorm<<<g, b>>>(t, d, W, H);
    CHK(hipGetLastError()); CHK(hipDeviceSynchronize());
    std::vector<float4> out(W * H); CHK(hipMemcpy(out.data(), d, W * H * sizeof(float4), hipMemcpyDeviceToHost));
    int bad = 0; for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) { float4 v = out[y * W + x]; if (std::fabs(v.x * scale - (x % 200)) > 0.6f || std::fabs(v.y * scale - (y % 200)) > 0.6f) ++bad; }
    std::printf("%-58s %s (%d bad; [5,3] = %.3f %.3f %.3f %.3f)\n", name, bad ? "FAIL" : "OK", bad, out[3 * W + 5].x, out[3 * W + 5].y, out[3 * W + 5].z, out[3 * W + 5].w);
    (void)hipDestroyTextureObject(t); (void)hipFree(d); (void)hipFreeArray(arr); return bad ? 1 : 0;
}

int main() {
    const int W = 64, H = 32; int fails = 0;
    std::vector<uchar4> u(W * H); for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) u[y * W + x] = make_uchar4(x % 200, y % 200, 7, 9);
    std::vector<ushort4> hh(W * H); for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) hh[y * W + x] = make_ushort4(__half_as_ushort(__float2half(float(x % 200))), __half_as_ushort(__float2half(float(y % 200))), __half_as_ushort(__float2half(7.f)), __half_as_ushort(__float2half(9.f)));
    std::vector<float4> f(W * H); for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) f[y * W + x] = make_float4(x % 200, y % 200, 7, 9);
    fails += run("float4 ElementType linear norm (control)", hipCreateChannelDesc<float4>(), f, W, H, hipReadModeElementType, hipFilterModeLinear, true, 0, 1.f);
    fails += run("uchar4 NormalizedFloat linear norm  tex2D<float4>", hipCreateChannelDesc<uchar4>(), u, W, H, hipReadModeNormalizedFloat, hipFilterModeLinear, true, 0, 255.f);
    fails += run("uchar4 NormalizedFloat point norm   tex2D<float4>", hipCreateChannelDesc<uchar4>(), u, W, H, hipReadModeNormalizedFloat, hipFilterModePoint, true, 0, 255.f);
    fails += run("uchar4 ElementType point unnorm     tex2D<uchar4>", hipCreateChannelDesc<uchar4>(), u, W, H, hipReadModeElementType, hipFilterModePoint, false, 1, 1.f);
    fails += run("half4 (Half4 desc) ElementType linear norm", hipCreateChannelDescHalf4(), hh, W, H, hipReadModeElementType, hipFilterModeLinear, true, 0, 1.f);
    fails += run("half4 (Half4 desc) ElementType point norm", hipCreateChannelDescHalf4(), hh, W, H, hipReadModeElementType, hipFilterModePoint, true, 0, 1.f);
    fails += run("half4 (manual 16x4 float desc) ElementType linear", hipCreateChannelDesc(16, 16, 16, 16, hipChannelFormatKindFloat), hh, W, H, hipReadModeElementType, hipFilterModeLinear, true, 0, 1.f);
    fails += run("half4 (Half4 desc) ElementType linear UNNORM coords", hipCreateChannelDescHalf4(), hh, W, H, hipReadModeElementType, hipFilterModeLinear, false, 2, 1.f);
    fails += run("float4 ElementType linear UNNORM coords", hipCreateChannelDesc<float4>(), f, W, H, hipReadModeElementType, hipFilterModeLinear, false, 2, 1.f);
    std::printf("RESULT: %d failing combos\n", fails); return fails ? 2 : 0;
}
