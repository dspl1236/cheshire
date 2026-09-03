// Cheshire smoke test 1: device query + vector add on the AMD GPU.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s at %s:%d\n", hipGetErrorString(e), __FILE__, __LINE__); return 1; } } while (0)

__global__ void vadd(const float* a, const float* b, float* c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

int main() {
    int n = 0; CHK(hipGetDeviceCount(&n));
    std::printf("HIP devices: %d\n", n);
    for (int d = 0; d < n; ++d) {
        hipDeviceProp_t p; CHK(hipGetDeviceProperties(&p, d));
        std::printf(" [%d] %s arch=%s CUs=%d warp=%d VRAM=%zu MB shared/block=%zu maxTex2D=%dx%d canMapHost=%d managed=%d\n",
            d, p.name, p.gcnArchName, p.multiProcessorCount, p.warpSize,
            (size_t)(p.totalGlobalMem >> 20), p.sharedMemPerBlock, p.maxTexture2D[0], p.maxTexture2D[1],
            p.canMapHostMemory, p.managedMemory);
    }
    size_t freeB = 0, totB = 0; CHK(hipMemGetInfo(&freeB, &totB));
    std::printf("mem free/total: %zu / %zu MB\n", freeB >> 20, totB >> 20);

    const int N = 1 << 20;
    std::vector<float> a(N, 1.f), b(N, 2.f), c(N, 0.f);
    float *da, *db, *dc;
    CHK(hipMalloc(&da, N * 4)); CHK(hipMalloc(&db, N * 4)); CHK(hipMalloc(&dc, N * 4));
    CHK(hipMemcpy(da, a.data(), N * 4, hipMemcpyHostToDevice));
    CHK(hipMemcpy(db, b.data(), N * 4, hipMemcpyHostToDevice));
    vadd<<<(N + 255) / 256, 256>>>(da, db, dc, N);
    CHK(hipGetLastError());
    CHK(hipMemcpy(c.data(), dc, N * 4, hipMemcpyDeviceToHost));
    int bad = 0; for (int i = 0; i < N; ++i) if (c[i] != 3.f) ++bad;
    std::printf("vadd: %s (%d bad)\n", bad ? "FAIL" : "OK", bad);
    CHK(hipFree(da)); CHK(hipFree(db)); CHK(hipFree(dc));
    return bad ? 2 : 0;
}
