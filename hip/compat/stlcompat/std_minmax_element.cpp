// Cheshire toolchain shim: MSVC STL vectorized-algorithm helpers that a newer toolset
// exports from msvcp140 / msvcprt.lib but MSVC 14.50.35717 (this box) does not.
// The prebuilt vcpkg dependency archive (alicevision/vcpkg 2026.09.01) was compiled with
// that newer STL, so CoinUtils etc. reference these symbols. Semantics follow
// microsoft/STL xutility: pointer to the first extremal element, `last` for an empty range.
#include <cstddef>
#include <cstdint>

extern "C" {

const void* __stdcall __std_min_element_4i(const void* first, const void* last) noexcept {
    const int32_t* p = static_cast<const int32_t*>(first);
    const int32_t* e = static_cast<const int32_t*>(last);
    if (p == e) return last;
    const int32_t* best = p;
    for (++p; p != e; ++p) if (*p < *best) best = p;
    return best;
}

const void* __stdcall __std_max_element_4i(const void* first, const void* last) noexcept {
    const int32_t* p = static_cast<const int32_t*>(first);
    const int32_t* e = static_cast<const int32_t*>(last);
    if (p == e) return last;
    const int32_t* best = p;
    for (++p; p != e; ++p) if (*best < *p) best = p;
    return best;
}

const void* __stdcall __std_max_element_8i(const void* first, const void* last) noexcept {
    const int64_t* p = static_cast<const int64_t*>(first);
    const int64_t* e = static_cast<const int64_t*>(last);
    if (p == e) return last;
    const int64_t* best = p;
    for (++p; p != e; ++p) if (*best < *p) best = p;
    return best;
}

const void* __stdcall __std_min_element_8i(const void* first, const void* last) noexcept {
    const int64_t* p = static_cast<const int64_t*>(first);
    const int64_t* e = static_cast<const int64_t*>(last);
    if (p == e) return last;
    const int64_t* best = p;
    for (++p; p != e; ++p) if (*p < *best) best = p;
    return best;
}

const void* __stdcall __std_min_element_4u(const void* first, const void* last) noexcept {
    const uint32_t* p = static_cast<const uint32_t*>(first);
    const uint32_t* e = static_cast<const uint32_t*>(last);
    if (p == e) return last;
    const uint32_t* best = p;
    for (++p; p != e; ++p) if (*p < *best) best = p;
    return best;
}

const void* __stdcall __std_max_element_4u(const void* first, const void* last) noexcept {
    const uint32_t* p = static_cast<const uint32_t*>(first);
    const uint32_t* e = static_cast<const uint32_t*>(last);
    if (p == e) return last;
    const uint32_t* best = p;
    for (++p; p != e; ++p) if (*best < *p) best = p;
    return best;
}

}  // extern "C"
