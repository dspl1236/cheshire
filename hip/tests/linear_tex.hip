// Cheshire: are pitched linear (hipResourceTypePitch2D) textures a drop-in for array textures
// for the camera mip levels? Same half4 data, normalized coords, linear filter, clamp; sampled at
// random sub-texel positions from (a) a hipArray, (b) a pitched VRAM buffer, (c) a pitched
// mapped-host buffer (a spilled level). Reports bit-exactness and sampling throughput.
#include <hip/hip_runtime.h>
#include <hip/hip_fp16.h>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void sample(hipTextureObject_t tex, const float2* uv, float4* out, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n) return;
    out[i] = tex2D<float4>(tex, uv[i].x, uv[i].y);
}
// patch-like access pattern: every thread reads a 9x9 neighbourhood around its own pixel
__global__ void patch(hipTextureObject_t tex, float* out, int w, int h, float iw, float ih) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    float acc = 0.f;
    for (int j = -4; j <= 4; ++j) for (int i = -4; i <= 4; ++i) {
        float4 c = tex2D<float4>(tex, (x + i + 0.5f) * iw, (y + j + 0.5f) * ih);
        acc += c.x + c.y + c.z;
    }
    out[y * w + x] = acc;
}

static hipTextureDesc texDesc() {
    hipTextureDesc td{}; td.normalizedCoords = 1; td.filterMode = hipFilterModeLinear;
    td.addressMode[0] = td.addressMode[1] = td.addressMode[2] = hipAddressModeClamp; td.readMode = hipReadModeElementType;
    return td;
}

int main() {
    const int W = 2048, H = 1536, N = 1 << 20;
    hipDeviceProp_t prop{}; CHK(hipGetDeviceProperties(&prop, 0));
    std::printf("device: %s  texturePitchAlignment=%zu\n", prop.name, (size_t)prop.texturePitchAlignment);

    std::mt19937 rng(7); std::uniform_real_distribution<float> U(0.f, 1.f);
    std::vector<__half> src((size_t)W * H * 4);
    for (auto& v : src) v = __float2half(U(rng) * 2.f - 0.5f);
    std::vector<float2> uv(N);
    for (auto& p : uv) p = make_float2(U(rng) * 1.1f - 0.05f, U(rng) * 1.1f - 0.05f);  // includes clamped edges

    hipChannelFormatDesc desc = hipCreateChannelDescHalf4();
    const size_t rowBytes = (size_t)W * 8;

    // (a) array
    hipArray_t arr; CHK(hipMallocArray(&arr, &desc, W, H, hipArrayDefault));
    CHK(hipMemcpy2DToArray(arr, 0, 0, src.data(), rowBytes, rowBytes, H, hipMemcpyHostToDevice));
    hipResourceDesc ra{}; ra.resType = hipResourceTypeArray; ra.res.array.array = arr;
    // (b) pitched VRAM
    void* dv; size_t pitchV; CHK(hipMallocPitch(&dv, &pitchV, rowBytes, H));
    CHK(hipMemcpy2D(dv, pitchV, src.data(), rowBytes, rowBytes, H, hipMemcpyHostToDevice));
    hipResourceDesc rv{}; rv.resType = hipResourceTypePitch2D; rv.res.pitch2D.devPtr = dv; rv.res.pitch2D.desc = desc;
    rv.res.pitch2D.width = W; rv.res.pitch2D.height = H; rv.res.pitch2D.pitchInBytes = pitchV;
    // (c) pitched mapped host (spilled level)
    void* hh; CHK(hipHostMalloc(&hh, pitchV * H, hipHostMallocMapped));
    void* dh; CHK(hipHostGetDevicePointer(&dh, hh, 0));
    CHK(hipMemcpy2D(dh, pitchV, src.data(), rowBytes, rowBytes, H, hipMemcpyHostToDevice));
    hipResourceDesc rh = rv; rh.res.pitch2D.devPtr = dh;

    hipTextureDesc td = texDesc();
    hipTextureObject_t ta, tv, th;
    CHK(hipCreateTextureObject(&ta, &ra, &td, nullptr));
    hipError_t ev = hipCreateTextureObject(&tv, &rv, &td, nullptr);
    std::printf("pitch2D texture, normalized coords + linear filter, half4, VRAM: %s\n", ev == hipSuccess ? "OK" : hipGetErrorString(ev));
    if (ev != hipSuccess) return 1;
    hipError_t eh = hipCreateTextureObject(&th, &rh, &td, nullptr);
    std::printf("pitch2D texture over mapped host memory: %s\n", eh == hipSuccess ? "OK" : hipGetErrorString(eh));

    float2* duv; CHK(hipMalloc(&duv, N * sizeof(float2))); CHK(hipMemcpy(duv, uv.data(), N * sizeof(float2), hipMemcpyHostToDevice));
    float4* out[3]; for (auto& o : out) CHK(hipMalloc(&o, N * sizeof(float4)));
    hipTextureObject_t texs[3] = {ta, tv, eh == hipSuccess ? th : tv};
    const char* names[3] = {"array", "pitch2D VRAM", "pitch2D host"};
    for (int k = 0; k < 3; ++k) { sample<<<(N + 255) / 256, 256>>>(texs[k], duv, out[k], N); CHK(hipGetLastError()); }
    CHK(hipDeviceSynchronize());
    std::vector<float4> h0(N), h1(N);
    CHK(hipMemcpy(h0.data(), out[0], N * sizeof(float4), hipMemcpyDeviceToHost));
    int bad = 0;
    for (int k = 1; k < 3; ++k) {
        CHK(hipMemcpy(h1.data(), out[k], N * sizeof(float4), hipMemcpyDeviceToHost));
        int diff = 0; float maxd = 0.f;
        for (int i = 0; i < N; ++i) {
            if (std::memcmp(&h0[i], &h1[i], sizeof(float4)) != 0) { ++diff;
                float d = std::fabs(h0[i].x - h1[i].x) + std::fabs(h0[i].y - h1[i].y) + std::fabs(h0[i].z - h1[i].z) + std::fabs(h0[i].w - h1[i].w);
                if (d > maxd) maxd = d; }
        }
        std::printf("%-13s vs array: %d / %d samples differ (max abs diff %.3g) -> %s\n", names[k], diff, N, maxd, diff ? "NOT bit-exact" : "bit-exact");
        bad += diff ? 1 : 0;
    }
    // throughput with a patch-like access pattern
    float* dpatch; CHK(hipMalloc(&dpatch, (size_t)W * H * sizeof(float)));
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    for (int k = 0; k < 3; ++k) {
        patch<<<g, b>>>(texs[k], dpatch, W, H, 1.f / W, 1.f / H); CHK(hipDeviceSynchronize());  // warm
        auto t0 = std::chrono::steady_clock::now();
        const int reps = 20;
        for (int r = 0; r < reps; ++r) patch<<<g, b>>>(texs[k], dpatch, W, H, 1.f / W, 1.f / H);
        CHK(hipDeviceSynchronize());
        double s = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count() / reps;
        double texels = double(W) * H * 81;
        std::printf("%-13s 9x9 patch pass over %dx%d: %.2f ms  (%.1f Gtexel/s)\n", names[k], W, H, s * 1e3, texels / s / 1e9);
    }
    std::printf(bad ? "RESULT: pitch2D differs from array\n" : "RESULT: pitch2D levels are a bit-exact substitute for array levels\n");
    return 0;
}
