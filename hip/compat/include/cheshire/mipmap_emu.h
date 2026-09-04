// Cheshire: mipmapped-array emulation for HIP stacks without hipMallocMipmappedArray
// (Linux ROCm 7.2 reports "Mipmap not supported on one of the devices", e.g. RX 5500 XT).
//
// A "mipmapped array" becomes one plain 2D array per level; a texture object over it becomes
// a small device-side table of one texture object per level, and the 64-bit handle AliceVision
// carries around (cudaTextureObject_t) is the device pointer of that table. Device code samples
// with tex2DLod(handle, u, v, level) -> tex2D(table[int(level + 0.5)], u, v): AliceVision only
// samples at integer levels (level = log2(scale / minDownscale)), so bilinear at that level is
// exactly what trilinear at an integer LOD returns. Fractional levels (custom patch-pattern
// subparts) are rounded to the nearest level.
//
// Active when CHESHIRE_EMULATE_MIPMAP is defined (the default under HIP); define
// CHESHIRE_NATIVE_MIPMAP to use hipMallocMipmappedArray where the platform supports it.
#pragma once
#include <hip/hip_runtime.h>

namespace cheshire { namespace mip {

constexpr int kMaxLevels = 16;
struct TexSet { hipTextureObject_t t[kMaxLevels]; int n; };

}}  // namespace cheshire::mip

template<class T>
__device__ inline T cheshire_tex2DLod(hipTextureObject_t handle, float u, float v, float level)
{
    const cheshire::mip::TexSet* s = reinterpret_cast<const cheshire::mip::TexSet*>(handle);
    int l = int(level + 0.5f);
    l = l < 0 ? 0 : (l >= s->n ? s->n - 1 : l);
    return tex2D<T>(s->t[l], u, v);
}

// host-side implementation (plain __host__ functions: parsed in both compilation passes)
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace cheshire { namespace mip {

struct MipRec { std::vector<hipArray_t> levels; hipChannelFormatDesc desc; size_t w, h; };
struct TexRec { std::vector<hipTextureObject_t> levels; TexSet* dev; };

struct Registry {
    std::mutex m;
    std::unordered_map<void*, MipRec> mips;   // fake hipMipmappedArray_t -> arrays
    std::unordered_map<void*, TexRec> texs;   // fake texture handle (device TexSet*) -> level textures
};
inline Registry& reg() { static Registry r; return r; }

inline hipError_t mallocMipmappedArray(hipMipmappedArray_t* out, const hipChannelFormatDesc* desc, hipExtent extent, unsigned int levels, unsigned int flags) {
    (void)flags;  // surfaces are not used with the emulated levels (buffer-copy mip builder)
    if (levels == 0 || levels > (unsigned)kMaxLevels) return hipErrorInvalidValue;
    MipRec rec; rec.desc = *desc; rec.w = extent.width; rec.h = extent.height;
    size_t w = extent.width, h = extent.height;
    for (unsigned l = 0; l < levels; ++l) {
        hipArray_t a = nullptr;
        hipError_t e = hipMallocArray(&a, desc, w ? w : 1, h ? h : 1, hipArrayDefault);
        if (e != hipSuccess) { for (auto x : rec.levels) (void)hipFreeArray(x); return e; }
        rec.levels.push_back(a);
        w /= 2; h /= 2;
    }
    void* handle = rec.levels[0];  // the level-0 array pointer doubles as the fake mipmap handle
    { std::lock_guard<std::mutex> g(reg().m); reg().mips[handle] = std::move(rec); }
    *out = reinterpret_cast<hipMipmappedArray_t>(handle);
    return hipSuccess;
}

inline hipError_t getMipmappedArrayLevel(hipArray_t* out, hipMipmappedArray_t mip, unsigned int level) {
    std::lock_guard<std::mutex> g(reg().m);
    auto it = reg().mips.find(reinterpret_cast<void*>(mip));
    if (it == reg().mips.end() || level >= it->second.levels.size()) return hipErrorInvalidValue;
    *out = it->second.levels[level];
    return hipSuccess;
}

inline hipError_t freeMipmappedArray(hipMipmappedArray_t mip) {
    MipRec rec;
    { std::lock_guard<std::mutex> g(reg().m);
      auto it = reg().mips.find(reinterpret_cast<void*>(mip));
      if (it == reg().mips.end()) return hipErrorInvalidValue;
      rec = std::move(it->second); reg().mips.erase(it); }
    hipError_t err = hipSuccess;
    for (auto a : rec.levels) { hipError_t e = hipFreeArray(a); if (e != hipSuccess) err = e; }
    return err;
}

// hipArrayGetInfo may be unavailable on some stacks; answer from the registry for our levels.
inline hipError_t arrayGetInfo(hipChannelFormatDesc* desc, hipExtent* extent, unsigned int* flags, hipArray_t array) {
    std::lock_guard<std::mutex> g(reg().m);
    for (auto& kv : reg().mips) {
        const MipRec& r = kv.second;
        for (size_t l = 0; l < r.levels.size(); ++l) if (r.levels[l] == array) {
            if (desc) *desc = r.desc;
            if (extent) { extent->width = (r.w >> l) ? (r.w >> l) : 1; extent->height = (r.h >> l) ? (r.h >> l) : 1; extent->depth = 0; }
            if (flags) *flags = 0;
            return hipSuccess;
        }
    }
    return hipArrayGetInfo(desc, extent, flags, array);
}

inline hipError_t createTextureObject(hipTextureObject_t* out, const hipResourceDesc* rd, const hipTextureDesc* td, const hipResourceViewDesc* vd) {
    if (rd->resType != hipResourceTypeMipmappedArray) return hipCreateTextureObject(out, rd, td, vd);
    MipRec* rec = nullptr;
    { std::lock_guard<std::mutex> g(reg().m);
      auto it = reg().mips.find(reinterpret_cast<void*>(rd->res.mipmap.mipmap));
      if (it != reg().mips.end()) rec = &it->second; }
    if (!rec) return hipCreateTextureObject(out, rd, td, vd);  // a native mipmapped array
    TexRec tr; tr.dev = nullptr;
    hipTextureDesc ld = *td; ld.mipmapFilterMode = hipFilterModePoint; ld.maxMipmapLevelClamp = 0; ld.minMipmapLevelClamp = 0; ld.mipmapLevelBias = 0;
    for (auto a : rec->levels) {
        hipResourceDesc lrd{}; lrd.resType = hipResourceTypeArray; lrd.res.array.array = a;
        hipTextureObject_t t = 0;
        hipError_t e = hipCreateTextureObject(&t, &lrd, &ld, nullptr);
        if (e != hipSuccess) { for (auto x : tr.levels) (void)hipDestroyTextureObject(x); return e; }
        tr.levels.push_back(t);
    }
    TexSet host{}; host.n = int(tr.levels.size());
    for (int i = 0; i < host.n; ++i) host.t[i] = tr.levels[i];
    hipError_t e = hipMalloc(reinterpret_cast<void**>(&tr.dev), sizeof(TexSet));
    if (e == hipSuccess) e = hipMemcpy(tr.dev, &host, sizeof(TexSet), hipMemcpyHostToDevice);
    if (e != hipSuccess) { for (auto x : tr.levels) (void)hipDestroyTextureObject(x); if (tr.dev) (void)hipFree(tr.dev); return e; }
    { std::lock_guard<std::mutex> g(reg().m); reg().texs[tr.dev] = tr; }
    *out = reinterpret_cast<hipTextureObject_t>(tr.dev);
    return hipSuccess;
}

inline hipError_t destroyTextureObject(hipTextureObject_t tex) {
    TexRec tr; bool ours = false;
    { std::lock_guard<std::mutex> g(reg().m);
      auto it = reg().texs.find(reinterpret_cast<void*>(tex));
      if (it != reg().texs.end()) { tr = it->second; reg().texs.erase(it); ours = true; } }
    if (!ours) return hipDestroyTextureObject(tex);
    hipError_t err = hipSuccess;
    for (auto t : tr.levels) { hipError_t e = hipDestroyTextureObject(t); if (e != hipSuccess) err = e; }
    if (hipFree(tr.dev) != hipSuccess) err = hipErrorInvalidValue;
    return err;
}

}}  // namespace cheshire::mip
