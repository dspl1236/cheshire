// Cheshire test 4: the memory bridge under a soft VRAM cap.
// Sets CHESHIRE_BRIDGE_VRAM_MB=1024 for itself, allocates 3 x 700 MB pitched 2D buffers and
// one 3D volume through the cuda* names (as AliceVision's memory.hpp does), checks that the
// overflow landed in host memory, that a kernel can read/write it and that a pitch2D texture
// can be created over a spilled buffer (depth/sim maps are read through textures).
#include <cstdlib>
#if defined(_WIN32)
#  include <stdlib.h>
#endif
#include <cheshire/cuda_to_hip.h>
#include <cstdio>
#include <vector>

#define CHK(x) do { hipError_t e = (x); if (e != hipSuccess) { \
  std::fprintf(stderr, "HIP error %s (%d) at %s:%d\n", hipGetErrorString(e), (int)e, __FILE__, __LINE__); return 1; } } while (0)

__global__ void fill(float* p, size_t pitch, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    *reinterpret_cast<float*>(reinterpret_cast<char*>(p) + y * pitch + x * 4) = float(x + y);
}
__global__ void sampleTex(hipTextureObject_t t, float* out, int w, int h) {
    int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x >= w || y >= h) return;
    out[y * w + x] = tex2D<float>(t, x + 0.5f, y + 0.5f);
}

int main() {
#if defined(_WIN32)
    _putenv_s("CHESHIRE_BRIDGE_VRAM_MB", "1024");
    _putenv_s("CHESHIRE_BRIDGE_LOG", "1");
#else
    setenv("CHESHIRE_BRIDGE_VRAM_MB", "1024", 1);
    setenv("CHESHIRE_BRIDGE_LOG", "1", 1);
#endif
    const int W = 8192, H = 22400;  // 8192*4 B * 22400 rows = 700 MB
    float* bufs[3]; size_t pitch[3];
    for (int i = 0; i < 3; ++i) {
        CHK(cudaMallocPitch<float>(&bufs[i], &pitch[i], W * sizeof(float), H));
        std::printf("buf%d: pitch=%zu tier=%s\n", i, pitch[i], cheshire::bridge::tierOf(bufs[i]) == cheshire::bridge::Tier::Vram ? "VRAM" : "HOST");
    }
    int bad = 0;
    if (cheshire::bridge::tierOf(bufs[0]) != cheshire::bridge::Tier::Vram) { std::printf("expected buf0 in VRAM\n"); bad++; }
    if (cheshire::bridge::tierOf(bufs[2]) != cheshire::bridge::Tier::Host) { std::printf("expected buf2 spilled to HOST\n"); bad++; }

    // kernel writes into the spilled buffer, texture reads it back
    dim3 b(16, 16), g((W + 15) / 16, (H + 15) / 16);
    fill<<<g, b>>>(bufs[2], pitch[2], W, H); CHK(hipGetLastError()); CHK(hipDeviceSynchronize());
    hipResourceDesc rd{}; rd.resType = hipResourceTypePitch2D; rd.res.pitch2D.devPtr = bufs[2];
    rd.res.pitch2D.desc = hipCreateChannelDesc<float>(); rd.res.pitch2D.width = W; rd.res.pitch2D.height = 64; rd.res.pitch2D.pitchInBytes = pitch[2];
    hipTextureDesc td{}; td.addressMode[0] = td.addressMode[1] = hipAddressModeClamp; td.filterMode = hipFilterModePoint; td.readMode = hipReadModeElementType;
    hipTextureObject_t tex = 0;
    hipError_t te = hipCreateTextureObject(&tex, &rd, &td, nullptr);
    std::printf("pitch2D texture over spilled buffer: %s\n", te == hipSuccess ? "OK" : hipGetErrorString(te));
    if (te == hipSuccess) {
        float* out; CHK(cudaMalloc(&out, W * 64 * sizeof(float)));
        dim3 g2((W + 15) / 16, 4);
        sampleTex<<<g2, b>>>(tex, out, W, 64); CHK(hipGetLastError());
        std::vector<float> h(W * 64); CHK(hipMemcpy(h.data(), out, h.size() * 4, hipMemcpyDeviceToHost));
        int tb = 0; for (int y = 0; y < 64; ++y) for (int x = 0; x < W; ++x) if (h[y * W + x] != float(x + y)) ++tb;
        std::printf("texture readback of spilled buffer: %s (%d bad)\n", tb ? "FAIL" : "OK", tb); bad += tb ? 1 : 0;
        CHK(hipDestroyTextureObject(tex)); CHK(cudaFree(out));
    } else bad++;

    // 3D volume path (AliceVision similarity volumes use cudaMalloc3D)
    hipPitchedPtr pp{}; hipExtent ext = make_hipExtent(512 * 2, 512, 300);  // 150 MB of u16
    CHK(cudaMalloc3D(&pp, ext));
    std::printf("3D volume: pitch=%zu tier=%s\n", pp.pitch, cheshire::bridge::tierOf(pp.ptr) == cheshire::bridge::Tier::Vram ? "VRAM" : "HOST");
    CHK(hipMemset(pp.ptr, 0x5a, pp.pitch * ext.height * ext.depth)); CHK(hipDeviceSynchronize());

    for (int i = 0; i < 3; ++i) CHK(cudaFree(bufs[i]));
    CHK(cudaFree(pp.ptr));
    cheshire::bridge::logSummary("after free");
    auto s = cheshire::bridge::stats();
    if (s.hostBytes != 0 || s.vramBytes != 0) { std::printf("leak in registry: vram=%zu host=%zu\n", s.vramBytes, s.hostBytes); bad++; }
    std::printf("RESULT: %s\n", bad ? "FAIL" : "ALL OK");
    return bad ? 2 : 0;
}
