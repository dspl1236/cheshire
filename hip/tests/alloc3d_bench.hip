#include <hip/hip_runtime.h>
#include <cstdio>
#include <chrono>
static double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
int main() {
    struct E { size_t w, h, d; int es; } cases[] = {{256, 256, 1500, 1}, {256, 256, 1500, 2}, {184, 205, 243, 1}, {1024, 1024, 8, 4}};
    for (auto& c : cases) {
        hipPitchedPtr p; hipExtent e = make_hipExtent(c.w * c.es, c.h, c.d);
        double t0 = now(); hipError_t r = hipMalloc3D(&p, e); double t1 = now(); (void)hipMemset3D(p, 0, e); (void)hipDeviceSynchronize(); double t2 = now(); (void)hipFree(p.ptr); double t3 = now();
        std::printf("hipMalloc3D %zux%zux%zu x%d B (%zu MB, pitch %zu): %s alloc %.1f ms, memset3D %.1f ms, free %.1f ms\n", c.w, c.h, c.d, c.es, p.pitch * c.h * c.d >> 20, p.pitch, hipGetErrorString(r), (t1 - t0) * 1e3, (t2 - t1) * 1e3, (t3 - t2) * 1e3);
    }
    void* h; double t0 = now(); (void)hipHostMalloc(&h, 96u << 20, 0); double t1 = now(); (void)hipHostFree(h); double t2 = now();
    std::printf("hipHostMalloc 96 MB pinned: %.1f ms, free %.1f ms\n", (t1 - t0) * 1e3, (t2 - t1) * 1e3);
    t0 = now(); (void)hipHostMalloc(&h, 96u << 20, 0); t1 = now(); (void)hipHostFree(h); t2 = now();
    std::printf("hipHostMalloc 96 MB pinned (2nd): %.1f ms, free %.1f ms\n", (t1 - t0) * 1e3, (t2 - t1) * 1e3);
    return 0;
}
