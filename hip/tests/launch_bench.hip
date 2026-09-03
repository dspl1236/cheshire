// Cheshire probe: kernel launch overhead on this HIP stack (the SGM aggregation issues
// ~3 launches per volume row: thousands of small kernels per tile).
#include <hip/hip_runtime.h>
#include <cstdio>
#include <chrono>
__global__ void tiny(float* p, int n) { int i = blockIdx.x * blockDim.x + threadIdx.x; if (i < n) p[i] += 1.f; }
__global__ void slice(float* p, int w, int z) { int x = blockIdx.x * blockDim.x + threadIdx.x, zz = blockIdx.y * blockDim.y + threadIdx.y; if (x < w && zz < z) p[zz * w + x] += 1.f; }
static double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
int main() {
    float* d; (void)hipMalloc(&d, 512 * 256 * 4); hipStream_t s; (void)hipStreamCreate(&s);
    for (int rep = 0; rep < 2; ++rep) {
        const int N = 5000;
        tiny<<<1, 64, 0, s>>>(d, 64); (void)hipStreamSynchronize(s);
        double t0 = now(); for (int i = 0; i < N; ++i) tiny<<<1, 64, 0, s>>>(d, 64); double t1 = now(); (void)hipStreamSynchronize(s); double t2 = now();
        std::printf("tiny kernel x%d: enqueue %.1f us/launch, end-to-end %.1f us/launch\n", N, (t1 - t0) / N * 1e6, (t2 - t0) / N * 1e6);
        dim3 b(32, 32), g((512 + 31) / 32, (256 + 31) / 32);
        t0 = now(); for (int i = 0; i < N; ++i) slice<<<g, b, 0, s>>>(d, 512, 256); t1 = now(); (void)hipStreamSynchronize(s); t2 = now();
        std::printf("512x256 slice (32x32 blocks) x%d: enqueue %.1f us, end-to-end %.1f us/launch\n", N, (t1 - t0) / N * 1e6, (t2 - t0) / N * 1e6);
        dim3 b2(64, 4), g2((512 + 63) / 64, (256 + 3) / 4);
        t0 = now(); for (int i = 0; i < N; ++i) slice<<<g2, b2, 0, s>>>(d, 512, 256); t1 = now(); (void)hipStreamSynchronize(s); t2 = now();
        std::printf("512x256 slice (64x4 blocks)  x%d: enqueue %.1f us, end-to-end %.1f us/launch\n", N, (t1 - t0) / N * 1e6, (t2 - t0) / N * 1e6);
    }
    return 0;
}
