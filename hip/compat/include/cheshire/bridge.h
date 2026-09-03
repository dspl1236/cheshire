// Cheshire memory bridge: VRAM first, mapped system RAM when VRAM is short.
//
// Header-only, HIP-only. Wired in through cuda_to_hip.h so AliceVision's memory.hpp
// (cudaMalloc / cudaMallocPitch / cudaMalloc3D / cudaFree) uses it without a source change.
//
// Policy (docs/02-memory-bridge.md):
//   * try hipMalloc*; on hipErrorOutOfMemory, or when the soft VRAM cap would be exceeded,
//     allocate pinned mapped host memory (hipHostMalloc + hipHostGetDevicePointer) instead
//     and hand back the *device* pointer, so kernels and textures see ordinary memory
//     (25 GB/s over PCIe instead of failing);
//   * a registry maps device pointers of spilled blocks to their host pointers so
//     cudaFree() releases them correctly;
//   * environment knobs:
//       CHESHIRE_BRIDGE=0            disable (plain HIP behaviour)
//       CHESHIRE_BRIDGE_VRAM_MB=N    soft cap on bytes this process places in VRAM
//                                   (default: no cap -> spill only on real OOM;
//                                    on Windows WDDM never reports OOM, so set a cap
//                                    to keep hot buffers resident)
//       CHESHIRE_BRIDGE_HOST_MB=N    cap on spilled host bytes (default 25 % of RAM)
//       CHESHIRE_BRIDGE_LOG=1        log every spill to stderr
#pragma once
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_map>
#if defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <unistd.h>
#endif

namespace cheshire { namespace bridge {

enum class Tier { Vram, Host };

struct Stats {
    size_t vramBytes = 0;      // live bytes this process placed in VRAM through the bridge
    size_t hostBytes = 0;      // live bytes spilled to host
    size_t spills = 0;         // number of allocations that went to host
    size_t spillFailures = 0;  // host fallback also failed
};

namespace detail {
struct Rec { void* host; size_t bytes; };

struct State {
    std::mutex m;
    std::unordered_map<void*, Rec> spilled;   // device ptr -> host record
    std::unordered_map<void*, size_t> vram;   // device ptr -> bytes (for the soft cap)
    Stats stats;
    bool enabled = true, log = false;
    size_t vramCap = ~size_t(0), hostCap = 0;
    State() {
        const char* e = std::getenv("CHESHIRE_BRIDGE");
        enabled = !(e && e[0] == '0');
        log = std::getenv("CHESHIRE_BRIDGE_LOG") != nullptr;
        if (const char* v = std::getenv("CHESHIRE_BRIDGE_VRAM_MB")) vramCap = size_t(std::strtoull(v, nullptr, 10)) << 20;
        size_t ram = 0;
#if defined(_WIN32)
        MEMORYSTATUSEX ms; ms.dwLength = sizeof(ms); if (GlobalMemoryStatusEx(&ms)) ram = size_t(ms.ullTotalPhys);
#else
        long pages = sysconf(_SC_PHYS_PAGES), psz = sysconf(_SC_PAGE_SIZE); if (pages > 0 && psz > 0) ram = size_t(pages) * size_t(psz);
#endif
        hostCap = ram / 4;
        if (const char* h = std::getenv("CHESHIRE_BRIDGE_HOST_MB")) hostCap = size_t(std::strtoull(h, nullptr, 10)) << 20;
    }
};
inline State& st() { static State s; return s; }

inline size_t alignUp(size_t v, size_t a) { return (v + a - 1) / a * a; }

inline size_t pitchAlign() {
    static size_t a = [] {
        hipDeviceProp_t p{}; int d = 0;
        if (hipGetDevice(&d) == hipSuccess && hipGetDeviceProperties(&p, d) == hipSuccess && p.texturePitchAlignment > 0)
            return size_t(p.texturePitchAlignment) > 256 ? size_t(p.texturePitchAlignment) : size_t(256);
        return size_t(256);
    }();
    return a;
}

// Allocate `bytes` in mapped host memory; returns the device-visible pointer.
inline hipError_t hostAlloc(void** devPtr, size_t bytes, const char* what) {
    State& s = st();
    std::lock_guard<std::mutex> g(s.m);
    if (s.stats.hostBytes + bytes > s.hostCap) { s.stats.spillFailures++; return hipErrorOutOfMemory; }
    void* h = nullptr;
    hipError_t e = hipHostMalloc(&h, bytes, hipHostMallocMapped);
    if (e != hipSuccess) { s.stats.spillFailures++; return e; }
    void* d = nullptr;
    e = hipHostGetDevicePointer(&d, h, 0);
    if (e != hipSuccess) { (void)hipHostFree(h); s.stats.spillFailures++; return e; }
    s.spilled[d] = Rec{h, bytes};
    s.stats.hostBytes += bytes; s.stats.spills++;
    if (s.log) std::fprintf(stderr, "[cheshire] bridge: %s %zu MB -> host (host total %zu MB, vram total %zu MB)\n",
                            what, bytes >> 20, s.stats.hostBytes >> 20, s.stats.vramBytes >> 20);
    *devPtr = d;
    return hipSuccess;
}

inline bool vramAllowed(size_t bytes) {
    State& s = st();
    std::lock_guard<std::mutex> g(s.m);
    return s.stats.vramBytes + bytes <= s.vramCap;
}
inline void noteVram(void* p, size_t bytes) {
    State& s = st(); std::lock_guard<std::mutex> g(s.m);
    s.vram[p] = bytes; s.stats.vramBytes += bytes;
}
}  // namespace detail

inline bool enabled() { return detail::st().enabled; }
inline Stats stats() { auto& s = detail::st(); std::lock_guard<std::mutex> g(s.m); return s.stats; }
inline Tier tierOf(const void* devPtr) {
    auto& s = detail::st(); std::lock_guard<std::mutex> g(s.m);
    return s.spilled.count(const_cast<void*>(devPtr)) ? Tier::Host : Tier::Vram;
}

inline hipError_t malloc(void** devPtr, size_t bytes) {
    if (!enabled()) return hipMalloc(devPtr, bytes);
    hipError_t e = hipErrorOutOfMemory;
    if (detail::vramAllowed(bytes)) { e = hipMalloc(devPtr, bytes); if (e == hipSuccess) { detail::noteVram(*devPtr, bytes); return e; } (void)hipGetLastError(); }
    return detail::hostAlloc(devPtr, bytes, "1D");
}

inline hipError_t mallocPitch(void** devPtr, size_t* pitch, size_t widthBytes, size_t height) {
    if (!enabled()) return hipMallocPitch(devPtr, pitch, widthBytes, height);
    const size_t p = detail::alignUp(widthBytes, detail::pitchAlign());
    const size_t bytes = p * height;
    hipError_t e = hipErrorOutOfMemory;
    if (detail::vramAllowed(bytes)) {
        e = hipMallocPitch(devPtr, pitch, widthBytes, height);
        if (e == hipSuccess) { detail::noteVram(*devPtr, *pitch * height); return e; }
        (void)hipGetLastError();
    }
    e = detail::hostAlloc(devPtr, bytes, "2D pitched");
    if (e == hipSuccess) *pitch = p;
    return e;
}

inline hipError_t malloc3D(hipPitchedPtr* pp, hipExtent extent) {
    if (!enabled()) return hipMalloc3D(pp, extent);
    const size_t p = detail::alignUp(extent.width, detail::pitchAlign());
    const size_t bytes = p * extent.height * extent.depth;
    hipError_t e = hipErrorOutOfMemory;
    if (detail::vramAllowed(bytes)) {
        e = hipMalloc3D(pp, extent);
        if (e == hipSuccess) { detail::noteVram(pp->ptr, pp->pitch * extent.height * extent.depth); return e; }
        (void)hipGetLastError();
    }
    void* d = nullptr;
    e = detail::hostAlloc(&d, bytes, "3D volume");
    if (e == hipSuccess) { pp->ptr = d; pp->pitch = p; pp->xsize = extent.width; pp->ysize = extent.height; }
    return e;
}

inline hipError_t free(void* devPtr) {
    if (devPtr == nullptr) return hipSuccess;
    auto& s = detail::st();
    void* host = nullptr; size_t bytes = 0;
    {
        std::lock_guard<std::mutex> g(s.m);
        auto it = s.spilled.find(devPtr);
        if (it != s.spilled.end()) { host = it->second.host; bytes = it->second.bytes; s.spilled.erase(it); s.stats.hostBytes -= bytes; }
        else { auto v = s.vram.find(devPtr); if (v != s.vram.end()) { s.stats.vramBytes -= v->second; s.vram.erase(v); } }
    }
    return host ? hipHostFree(host) : hipFree(devPtr);
}

inline void logSummary(const char* tag = "") {
    Stats s = stats();
    std::fprintf(stderr, "[cheshire] bridge%s%s: vram %zu MB live, host %zu MB live, %zu spills, %zu spill failures\n",
                 tag[0] ? " " : "", tag, s.vramBytes >> 20, s.hostBytes >> 20, s.spills, s.spillFailures);
}

}}  // namespace cheshire::bridge
