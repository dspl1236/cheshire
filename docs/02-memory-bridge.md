# Memory bridge: measured facts and design

## Probe results (RX 9070 16 GB, PCIe 4.0 x16 on a Ryzen 5600X, Windows 11, ROCm 7.2.1)

`hip/tests/membridge_probe.hip`, 2026-09-03:

```
device: AMD Radeon RX 9070  managed=0 pageableMemoryAccess=0 concurrentManagedAccess=0 canMapHost=1

[bandwidth] kernel streaming read of 1 GB
  hipMalloc (VRAM)                585.4 GB/s
  hipMallocManaged                 26.6 GB/s
  hipHostMalloc mapped (PCIe)      24.6 GB/s
  hipHostMalloc coherent           24.6 GB/s
  hipHostMalloc noncoherent        26.6 GB/s

[copy] 1 GB host<->device
  H2D pageable 16.2 GB/s   D2H pageable 16.0 GB/s
  H2D pinned   28.3 GB/s   D2H pinned   28.1 GB/s

[oversubscribe] hipMalloc 512 MB chunks up to 24576 MB
  ... allocated 16384 MB, hipMemGetInfo free=0 MB
  ... allocated 24576 MB, hipMemGetInfo free=0 MB      <- keeps succeeding
  stopped at 24576 MB: reached limit
  last chunk (beyond VRAM)   25.9 GB/s
  first chunk (in VRAM)     619.3 GB/s
```

## What that means

1. **On Windows the driver already bridges.** WDDM backs `hipMalloc` with system RAM
   once VRAM is full (up to roughly half of system RAM). Kernels keep running; touching
   spilled memory costs ~24x in bandwidth. `hipMemGetInfo` reports 0 free from that point,
   so AliceVision's planner (`DepthMapEstimator::getNbSimultaneousTiles`, which takes
   `available * 0.8`) would refuse work that the card can actually run.
2. **Managed memory is not migrating memory here.** `managed=0`: `hipMallocManaged`
   succeeds but behaves like mapped host memory (26 GB/s, no page migration into VRAM).
   Do not build the bridge on managed memory.
3. **Host-resident memory is a 25 GB/s tier**, the same for mapped, coherent and
   non-coherent flavours. That is fast enough for read-mostly data that is touched
   sparsely (camera mipmaps sampled through textures: the depth-map kernels read a few
   texels per output pixel), and far too slow for data that is streamed every iteration
   (similarity volumes, which SGM sweeps repeatedly).
4. **On Linux (the production node) none of the WDDM behaviour exists.** ROCm `hipMalloc`
   fails hard at the VRAM limit. The bridge must place data explicitly there.

## Design

A small allocator policy layer, `bridge/`, used by the HIP depth-map backend:

* **Tiers**: `Vram` (`hipMalloc*`), `HostMapped` (`hipHostMalloc(hipHostMallocMapped)` +
  device pointer), with `hipMemcpy` staging where a kernel needs contiguous VRAM.
* **Placement by access pattern**, decided per buffer class, not per allocation:

  | Buffer class (AliceVision name) | Access pattern | Tier when VRAM is short |
  |---|---|---|
  | similarity volume (`CudaDeviceMemoryPitched<TSim,3>`) | streamed by SGM passes | always Vram; shrink tile instead |
  | depth/sim maps, normal maps (2D pitched) | streamed | Vram |
  | camera mipmap images (`DeviceMipmapImage`, T cameras) | sparse texture reads | spill to HostMapped, LRU by camera |
  | camera params (`__constant__`) | tiny | unchanged |
  | host staging (`CudaHostMemoryHeap`) | copy source | pinned (already) |

  Textures cannot be created over host memory on all drivers, so spilled mipmaps are
  kept as pitched host buffers and copied into a VRAM texture slot on demand (a second
  LRU of texture slots in front of the camera LRU). This turns "out of memory" into
  "more PCIe traffic", which at 25-28 GB/s is a few ms per 100 MB image.
* **Capacity planning**: replace the `hipMemGetInfo * 0.8` heuristic with a budget =
  VRAM budget + host budget (user-settable, default 25% of system RAM), and let the
  planner size `nbSimultaneousTiles` from the VRAM budget only while the T-camera cache
  is sized from the total. Log the split so a job's `job-settings.json` records it.
* **Hard rule**: never let a similarity volume land in host memory. If the volume for
  one tile does not fit in VRAM, reduce the tile size (AliceVision already tiles;
  `TileParams` is the knob), not the tier.

The bridge is a HIP-only addition inside the ported backend; the CUDA build path is
untouched, which keeps the port upstreamable.

## Implementation v1 (2026-09-03) — `hip/compat/include/cheshire/bridge.h`

Header-only, wired through the compat layer: AliceVision's `memory.hpp` calls
`cudaMalloc` / `cudaMallocPitch<T>` / `cudaMalloc3D` / `cudaFree`, and in a HIP build
those names resolve to `cheshire::bridge::{malloc, mallocPitch, malloc3D, free}`.
No upstream source change.

* VRAM first; on `hipErrorOutOfMemory` **or** when a soft cap would be exceeded, the block
  is allocated as pinned mapped host memory and the *device* pointer is returned, so
  kernels and texture objects use it unchanged.
* A registry (device ptr -> host ptr, bytes) makes `cudaFree` release the right thing and
  keeps live VRAM / host byte counts (`bridge::stats()`, `bridge::logSummary()`).
* Knobs: `CHESHIRE_BRIDGE=0` (off), `CHESHIRE_BRIDGE_VRAM_MB` (soft VRAM cap; the only way
  to trigger spilling on Windows, where WDDM never reports OOM), `CHESHIRE_BRIDGE_HOST_MB`
  (spill cap, default 25 % of RAM), `CHESHIRE_BRIDGE_LOG=1`.
* Host pitch = row bytes rounded up to the device texture pitch alignment (>= 256 B).

`hip/tests/bridge_test.hip` on the RX 9070 with a 1 GB cap: 3 x 700 MB pitched buffers ->
1 in VRAM, 2 spilled; kernel writes + `tex2D` reads over a spilled buffer verified
bit-exact; 3D volume path exercised; registry drains to zero after `cudaFree`.

Not yet done (v2): tier-aware placement per buffer class (keep similarity volumes in
VRAM by shrinking tiles instead of spilling them) and a host-resident camera-mipmap
tier in `DeviceCache`; the planner (`getNbSimultaneousTiles`) still sizes from
`hipMemGetInfo * 0.8`.

## First real-workload spill test (2026-09-03)

`CHESHIRE_BRIDGE_VRAM_MB=1500` on the 6-view set forces almost every depth-map buffer past the
soft cap (188 spills, 5.4 GB of host memory live at the peak):

| GPU | uncapped | 1.5 GB VRAM cap | output |
|---|---|---|---|
| RX 9070, Windows, PCIe 4.0 | 17.4 s | 47.7 s (2.7x) | bit-identical |
| RX 6750 XT, Linux (house-pc, PCIe 3.0, i3) | 31.0 s | 161.9 s (5.2x) | bit-identical |

So the bridge does what v1 promised: a job that would not fit still finishes with exactly the
same result, at PCIe speed. On the node the first attempt stopped at 3.7 GB because the default
host budget is 25 % of RAM (14 GB box); `CHESHIRE_BRIDGE_HOST_MB=7000` lifted it. Two lessons
for v2: the slowdown is dominated by similarity volumes landing in host memory (v1 spills
whatever comes when the cap is hit - the tier rules in the design above are not implemented
yet), and the planner still sizes tile parallelism from `hipMemGetInfo`, so it never chooses
to spill on purpose; the cap only helps when the planner's estimate is wrong.
