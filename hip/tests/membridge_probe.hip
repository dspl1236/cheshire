// Cheshire probe 3: what the memory bridge can rely on.
//  (a) oversubscription: does hipMalloc beyond VRAM fail or spill (WDDM shared memory)?
//  (b) kernel read bandwidth from: device memory, hipMallocManaged, hipHostMalloc(mapped) zero-copy
//  (c) H2D / D2H copy bandwidth pageable vs pinned
// Output is plain text so it can be pasted into docs/02-memory-bridge.md.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <chrono>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void reduceRead(const float4* __restrict__ p, size_t n4, float* out) {
    size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x;
    size_t stride = (size_t)gridDim.x * blockDim.x;
    float acc = 0.f;
    for (; i < n4; i += stride) { float4 v = p[i]; acc += v.x + v.y + v.z + v.w; }
    if (acc == 12345.678f) out[0] = acc;  // keep the loads alive
}

static double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

static int bench(const char* name, const void* ptr, size_t bytes, float* dout) {
    size_t n4 = bytes / 16;
    reduceRead<<<28 * 8, 256>>>((const float4*)ptr, n4, dout);  // warm
    if (hipDeviceSynchronize() != hipSuccess) { std::printf("  %-28s launch failed\n", name); return 1; }
    const int reps = 5; double t0 = now();
    for (int r = 0; r < reps; ++r) reduceRead<<<28 * 8, 256>>>((const float4*)ptr, n4, dout);
    if (hipDeviceSynchronize() != hipSuccess) return 1;
    double dt = (now() - t0) / reps;
    std::printf("  %-28s %8.1f GB/s  (%zu MB, %.1f ms)\n", name, bytes / dt / 1e9, bytes >> 20, dt * 1e3);
    return 0;
}

int main(int argc, char** argv) {
    size_t freeB = 0, totB = 0; CHK(hipMemGetInfo(&freeB, &totB));
    std::printf("VRAM free/total: %zu / %zu MB\n", freeB >> 20, totB >> 20);
    hipDeviceProp_t p; CHK(hipGetDeviceProperties(&p, 0));
    std::printf("device: %s  managed=%d pageableMemoryAccess=%d concurrentManagedAccess=%d canMapHost=%d\n",
                p.name, p.managedMemory, p.pageableMemoryAccess, p.concurrentManagedAccess, p.canMapHostMemory);

    float* dout; CHK(hipMalloc(&dout, 64));
    const size_t chunk = 512ull << 20;  // 512 MB
    const size_t benchBytes = 1ull << 30; // 1 GB per bandwidth test

    // ---- (b) bandwidth ----
    std::printf("\n[bandwidth] kernel streaming read of 1 GB\n");
    { void* d; CHK(hipMalloc(&d, benchBytes)); CHK(hipMemset(d, 0, benchBytes)); bench("hipMalloc (VRAM)", d, benchBytes, dout); CHK(hipFree(d)); }
    { void* m = nullptr; if (hipMallocManaged(&m, benchBytes) == hipSuccess) { CHK(hipMemset(m, 0, benchBytes)); bench("hipMallocManaged", m, benchBytes, dout); CHK(hipFree(m)); } else std::printf("  hipMallocManaged: unavailable\n"); }
    { void* h = nullptr; if (hipHostMalloc(&h, benchBytes, hipHostMallocMapped) == hipSuccess) { std::memset(h, 0, benchBytes); void* dp; CHK(hipHostGetDevicePointer(&dp, h, 0)); bench("hipHostMalloc mapped (PCIe)", dp, benchBytes, dout); CHK(hipHostFree(h)); } else std::printf("  hipHostMalloc mapped: unavailable\n"); }
    { void* h = nullptr; if (hipHostMalloc(&h, benchBytes, hipHostMallocMapped | hipHostMallocCoherent) == hipSuccess) { std::memset(h, 0, benchBytes); void* dp; CHK(hipHostGetDevicePointer(&dp, h, 0)); bench("hipHostMalloc coherent", dp, benchBytes, dout); CHK(hipHostFree(h)); } }
    { void* h = nullptr; if (hipHostMalloc(&h, benchBytes, hipHostMallocMapped | hipHostMallocNonCoherent) == hipSuccess) { std::memset(h, 0, benchBytes); void* dp; CHK(hipHostGetDevicePointer(&dp, h, 0)); bench("hipHostMalloc noncoherent", dp, benchBytes, dout); CHK(hipHostFree(h)); } }

    // ---- (c) copy bandwidth ----
    std::printf("\n[copy] 1 GB host<->device\n");
    { void* d; CHK(hipMalloc(&d, benchBytes));
      std::vector<char> pageable(benchBytes, 1);
      double t0 = now(); CHK(hipMemcpy(d, pageable.data(), benchBytes, hipMemcpyHostToDevice)); double dt = now() - t0;
      std::printf("  H2D pageable   %6.1f GB/s\n", benchBytes / dt / 1e9);
      t0 = now(); CHK(hipMemcpy(pageable.data(), d, benchBytes, hipMemcpyDeviceToHost)); dt = now() - t0;
      std::printf("  D2H pageable   %6.1f GB/s\n", benchBytes / dt / 1e9);
      void* pinned; CHK(hipHostMalloc(&pinned, benchBytes, 0));
      t0 = now(); CHK(hipMemcpy(d, pinned, benchBytes, hipMemcpyHostToDevice)); dt = now() - t0;
      std::printf("  H2D pinned     %6.1f GB/s\n", benchBytes / dt / 1e9);
      t0 = now(); CHK(hipMemcpy(pinned, d, benchBytes, hipMemcpyDeviceToHost)); dt = now() - t0;
      std::printf("  D2H pinned     %6.1f GB/s\n", benchBytes / dt / 1e9);
      CHK(hipHostFree(pinned)); CHK(hipFree(d)); }

    // ---- (a) oversubscription ----
    size_t limitMB = (argc > 1) ? std::strtoull(argv[1], nullptr, 10) : (totB >> 20) + 8192;  // default: VRAM + 8 GB
    std::printf("\n[oversubscribe] hipMalloc 512 MB chunks up to %zu MB\n", limitMB);
    std::vector<void*> chunks; size_t got = 0; hipError_t last = hipSuccess;
    while (got < (limitMB << 20)) {
        void* d = nullptr; last = hipMalloc(&d, chunk);
        if (last != hipSuccess) { (void)hipGetLastError(); break; }
        // touch it so it is really backed
        if (hipMemset(d, 1, chunk) != hipSuccess) { (void)hipGetLastError(); last = hipErrorOutOfMemory; break; }
        chunks.push_back(d); got += chunk;
        size_t f = 0, t = 0; (void)hipMemGetInfo(&f, &t);
        if ((chunks.size() % 4) == 0 || got > totB) std::printf("  allocated %6zu MB, hipMemGetInfo free=%6zu MB\n", got >> 20, f >> 20);
    }
    std::printf("  stopped at %zu MB: %s\n", got >> 20, last == hipSuccess ? "reached limit" : hipGetErrorString(last));
    if (got > totB) {
        // bandwidth on the *last* chunk (the one most likely living in system RAM)
        bench("last chunk (beyond VRAM)", chunks.back(), chunk, dout);
        bench("first chunk (in VRAM)", chunks.front(), chunk, dout);
    }
    for (void* d : chunks) (void)hipFree(d);
    CHK(hipFree(dout));
    std::printf("\nRESULT: probe complete\n");
    return 0;
}
