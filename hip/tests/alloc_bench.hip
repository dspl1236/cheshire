// Cheshire probe: cost of device allocations on this stack (WDDM commit), to decide on pooling.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <chrono>
static double now() { return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count(); }
int main() {
    for (size_t mb : {1, 16, 64, 285, 700}) {
        const int reps = mb >= 285 ? 6 : 20; double ta = 0, tf = 0, tm = 0;
        for (int i = 0; i < reps; ++i) {
            void* p; double t0 = now(); (void)hipMalloc(&p, mb << 20); double t1 = now();
            (void)hipMemset(p, 0, mb << 20); (void)hipDeviceSynchronize(); double t2 = now();
            (void)hipFree(p); double t3 = now();
            ta += t1 - t0; tm += t2 - t1; tf += t3 - t2;
        }
        std::printf("%4zu MB: hipMalloc %7.2f ms, first memset %7.2f ms, hipFree %7.2f ms (avg of %d)\n", mb, ta / reps * 1e3, tm / reps * 1e3, tf / reps * 1e3, reps);
    }
    // pitched 2D like AliceVision's depth/sim maps
    double t0 = now(); for (int i = 0; i < 50; ++i) { void* p; size_t pitch; (void)hipMallocPitch(&p, &pitch, 1024 * 8, 1024); (void)hipFree(p); }
    std::printf("hipMallocPitch+free 8 MB x50: %.2f ms each\n", (now() - t0) / 50 * 1e3);
    return 0;
}
