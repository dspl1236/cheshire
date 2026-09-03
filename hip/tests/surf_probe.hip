// Cheshire probe: surface stores into 16-bit (half4) and 8-bit (uchar4) arrays.
// Reads back with hipMemcpy2DFromArray (no texture) and checks the raw bytes.
#include <hip/hip_runtime.h>
#include <cstdio>
#include <cstring>
#include <vector>
#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { std::fprintf(stderr, "HIP error %s at %s:%d\n", hipGetErrorString(e), __FILE__, __LINE__); return 1; } } while (0)

template<class T> __device__ inline T pattern(int x, int y);
template<> __device__ inline ushort4 pattern<ushort4>(int x, int y) { return make_ushort4(x, y, 7, 9); }
template<> __device__ inline uint2 pattern<uint2>(int x, int y) { return make_uint2((unsigned)x | ((unsigned)y << 16), 7u | (9u << 16)); }
template<> __device__ inline uchar4 pattern<uchar4>(int x, int y) { return make_uchar4(x, y, 7, 9); }
template<> __device__ inline unsigned int pattern<unsigned int>(int x, int y) { return (unsigned)x | ((unsigned)y << 8) | (7u << 16) | (9u << 24); }

template<class T> __global__ void store(hipSurfaceObject_t s, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x < w && y < h) surf2Dwrite(pattern<T>(x, y), s, x * (int)sizeof(T), y);
}

template<class T> static int run(const char* name, hipChannelFormatDesc desc, int W, int H, int texel) {
    hipArray_t arr; CHK(hipMallocArray(&arr, &desc, W, H, hipArraySurfaceLoadStore));
    hipResourceDesc rd{}; rd.resType = hipResourceTypeArray; rd.res.array.array = arr;
    hipSurfaceObject_t s; CHK(hipCreateSurfaceObject(&s, &rd));
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    store<T><<<g, b>>>(s, W, H); CHK(hipGetLastError()); CHK(hipDeviceSynchronize());
    std::vector<unsigned char> back(W * H * texel, 0xAA);
    CHK(hipMemcpy2DFromArray(back.data(), W * texel, arr, 0, 0, W * texel, H, hipMemcpyDeviceToHost));
    int bad = 0;
    for (int y = 0; y < H; ++y) for (int x = 0; x < W; ++x) {
        const unsigned char* p = &back[(y * W + x) * texel];
        if (texel == 8) { unsigned short v[4]; std::memcpy(v, p, 8); if (v[0] != x || v[1] != y || v[2] != 7 || v[3] != 9) ++bad; }
        else { if (p[0] != x || p[1] != y || p[2] != 7 || p[3] != 9) ++bad; }
    }
    std::printf("%-48s %s (%d bad; first texel bytes %02x %02x %02x %02x)\n", name, bad ? "FAIL" : "OK", bad, back[0], back[1], back[2], back[3]);
    (void)hipDestroySurfaceObject(s); (void)hipFreeArray(arr); return bad ? 1 : 0;
}

int main() {
    const int W = 48, H = 20; int f = 0;
    f += run<ushort4>("half4 array <- surf2Dwrite(ushort4)", hipCreateChannelDescHalf4(), W, H, 8);
    f += run<uint2>("half4 array <- surf2Dwrite(uint2)", hipCreateChannelDescHalf4(), W, H, 8);
    f += run<ushort4>("ushort4 (unsigned desc) <- surf2Dwrite(ushort4)", hipCreateChannelDesc<ushort4>(), W, H, 8);
    f += run<uchar4>("uchar4 array <- surf2Dwrite(uchar4)", hipCreateChannelDesc<uchar4>(), W, H, 4);
    f += run<unsigned int>("uchar4 array <- surf2Dwrite(u32)", hipCreateChannelDesc<uchar4>(), W, H, 4);
    f += run<unsigned int>("uint (32-bit) array <- surf2Dwrite(u32)", hipCreateChannelDesc<unsigned int>(), W, H, 4);
    std::printf("RESULT: %d failing combos\n", f); return f ? 2 : 0;
}
