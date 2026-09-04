// Cheshire: do GPU atomics work on mapped host memory? (The bridge spills 2D maps there; the fused
// SGM aggregation does atomicMin into one of them.) ROCm-Linux maps hipHostMalloc memory
// fine-grained by default, and atomics to fine-grained system memory over PCIe need PCIe atomics
// the platform may not have. Compares VRAM, mapped host (default = coherent) and mapped host
// non-coherent (coarse-grained: device-cached) for atomicMin / atomicAdd, plus a plain store +
// memsetAsync ordering check on the same buffers.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void kMin(unsigned* buf, int n, int reps) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n * reps) return;
    // each of `reps` threads per slot proposes a value; the min must be slot index
    atomicMin(&buf[i % n], (unsigned)(i % n) + (unsigned)(i / n) * 7u);
}
__global__ void kAdd(unsigned* buf, int n, int reps) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n * reps) return;
    atomicAdd(&buf[i % n], 1u);
}
__global__ void kStore(unsigned* buf, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) buf[i] = (unsigned)i * 3u;
}

static int check(const char* name, unsigned* d, void* h, int n, int reps, hipStream_t s) {
    std::vector<unsigned> out(n);
    int bad = 0;
    // atomicMin: init 0xFFFFFFFF, expect slot index
    CHK(hipMemsetAsync(d, 0xFF, n * sizeof(unsigned), s));
    kMin<<<(n * reps + 255) / 256, 256, 0, s>>>(d, n, reps); CHK(hipGetLastError());
    CHK(hipStreamSynchronize(s));
    CHK(hipMemcpy(out.data(), h ? h : d, n * sizeof(unsigned), h ? hipMemcpyHostToHost : hipMemcpyDeviceToHost));
    int badMin = 0; for (int i = 0; i < n; ++i) if (out[i] != (unsigned)i) ++badMin;
    // atomicAdd: init 0, expect reps
    CHK(hipMemsetAsync(d, 0, n * sizeof(unsigned), s));
    kAdd<<<(n * reps + 255) / 256, 256, 0, s>>>(d, n, reps); CHK(hipGetLastError());
    CHK(hipStreamSynchronize(s));
    CHK(hipMemcpy(out.data(), h ? h : d, n * sizeof(unsigned), h ? hipMemcpyHostToHost : hipMemcpyDeviceToHost));
    int badAdd = 0; for (int i = 0; i < n; ++i) if (out[i] != (unsigned)reps) ++badAdd;
    // store then memset ordering: store, memsetAsync(0x11) on the same stream -> expect 0x11111111
    kStore<<<(n + 255) / 256, 256, 0, s>>>(d, n); CHK(hipGetLastError());
    CHK(hipMemsetAsync(d, 0x11, n * sizeof(unsigned), s));
    CHK(hipStreamSynchronize(s));
    CHK(hipMemcpy(out.data(), h ? h : d, n * sizeof(unsigned), h ? hipMemcpyHostToHost : hipMemcpyDeviceToHost));
    int badOrd = 0; for (int i = 0; i < n; ++i) if (out[i] != 0x11111111u) ++badOrd;
    // memset then store ordering: memsetAsync(0), store -> expect i*3
    CHK(hipMemsetAsync(d, 0, n * sizeof(unsigned), s));
    kStore<<<(n + 255) / 256, 256, 0, s>>>(d, n); CHK(hipGetLastError());
    CHK(hipStreamSynchronize(s));
    CHK(hipMemcpy(out.data(), h ? h : d, n * sizeof(unsigned), h ? hipMemcpyHostToHost : hipMemcpyDeviceToHost));
    int badOrd2 = 0; for (int i = 0; i < n; ++i) if (out[i] != (unsigned)i * 3u) ++badOrd2;
    std::printf("%-28s atomicMin bad=%d/%d  atomicAdd bad=%d/%d  store->memset bad=%d  memset->store bad=%d\n",
                name, badMin, n, badAdd, n, badOrd, badOrd2);
    bad += badMin + badAdd + badOrd + badOrd2;
    return bad ? 2 : 0;
}

int main() {
    const int n = 1 << 16, reps = 64;
    int dev = 0; CHK(hipGetDevice(&dev));
    std::printf("device %d\n", dev); std::fflush(stdout);
    hipStream_t s; CHK(hipStreamCreate(&s));
    int rc = 0;
    { unsigned* d; CHK(hipMalloc(&d, n * sizeof(unsigned))); rc |= check("VRAM", d, nullptr, n, reps, s); CHK(hipFree(d)); }
    { void* h; unsigned* d; CHK(hipHostMalloc(&h, n * sizeof(unsigned), hipHostMallocMapped));
      CHK(hipHostGetDevicePointer((void**)&d, h, 0)); rc |= check("host mapped (default)", d, h, n, reps, s); CHK(hipHostFree(h)); }
    { void* h; unsigned* d; CHK(hipHostMalloc(&h, n * sizeof(unsigned), hipHostMallocMapped | hipHostMallocCoherent));
      CHK(hipHostGetDevicePointer((void**)&d, h, 0)); rc |= check("host mapped coherent", d, h, n, reps, s); CHK(hipHostFree(h)); }
    { void* h; unsigned* d; CHK(hipHostMalloc(&h, n * sizeof(unsigned), hipHostMallocMapped | hipHostMallocNonCoherent));
      CHK(hipHostGetDevicePointer((void**)&d, h, 0)); rc |= check("host mapped non-coherent", d, h, n, reps, s); CHK(hipHostFree(h)); }
    std::printf(rc ? "RESULT: some placements FAIL\n" : "RESULT: all OK\n");
    return rc;
}
