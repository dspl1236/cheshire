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

## v2 (2026-09-04): placement by class, a planner that knows about the bridge

v1 spilled whatever happened to be allocated after the cap was hit. v2 (`bridge.h`) knows what
it is placing, and the DepthMap planner sizes the work from the bridge's budgets. The policy
below is the one the measurements dictated, not the one the design above predicted: the
design had camera images as the cheapest class to spill; they turned out to be the worst by
far. Measure first.

* **Classes.** Every allocation is tagged: `Volume` (3D pitched: SGM / Refine similarity
  volumes), `Map` (2D pitched: depth / sim / normal maps, per-tile working buffers), `Image`
  (camera mip levels, tagged through a thread-local `ClassScope` by the mipmap emulation) and
  `Other`. Per-class live / peak bytes are kept and printed at exit with `CHESHIRE_BRIDGE_LOG=1`.
* **Cap by default.** The soft VRAM cap defaults to 90 % of the VRAM free when the bridge first
  runs (`CHESHIRE_BRIDGE_VRAM_FRACTION`, or `CHESHIRE_BRIDGE_VRAM_MB`; `0` = v1's no-cap). On
  Windows that keeps WDDM from paging behind our back; on Linux it keeps `hipMalloc` from failing.
* **Placement.** `Image` is VRAM-only. The planner reserves VRAM for the camera images of every
  simultaneous R camera (`bridge::setReserve`), and `Volume` / `Map` / `Other` take VRAM only
  under the cap minus that reserve, then mapped host memory. `CHESHIRE_BRIDGE_HOST_CLASSES=a,b`
  forces classes to host (the experiment knob); `CHESHIRE_BRIDGE_IMAGE_SPILL=1` lets images
  spill after all.
* **Planner.** `DepthMapEstimator::getNbSimultaneousTiles` (patched, `hip/port/bridge_v2/`)
  applies the upstream formula to `bridge::budget()` instead of `hipMemGetInfo * 0.8`, and
  never goes below one tile: when a single tile plus its images does not fit, it runs one tile
  and lets its volumes and maps spill rather than refusing the job (`CHESHIRE_BRIDGE_PLANNER=1`,
  default; `0` = upstream heuristic; `2` = the experiment where images go to host).
* **Linear mip levels.** Array memory cannot live in host RAM, so the mipmap emulation gained a
  second level storage: `CHESHIRE_MIPMAP_STORAGE=linear` puts each level in a pitched linear
  buffer sampled through a `hipResourceTypePitch2D` texture (the mip builder's per-level
  textures are redirected the same way). `hip/tests/linear_tex.hip`: same half4 data,
  normalized coordinates, bilinear filter: **bit-exact** against the array texture, in VRAM
  (578 vs 558 Gtexel/s on a 9x9 patch pass) and over mapped host memory (32 Gtexel/s).

### Measured: what each class costs behind PCIe

RX 9070, 6 views, `scripts/bridge_matrix.py`; every row bit-identical to the uncapped run and
PASS against the CUDA reference. Full table with per-class peaks and the case list:
`docs/validation/bridge-v2/rx9070-mini6-run2.md`.

| build / placement | DepthMap | vs VRAM |
|---|---|---|
| native mipmaps, everything in VRAM (the Windows release) | 17.9 s | |
| emulated mipmaps, array levels, everything in VRAM (what Linux runs) | 20.6 s | 1.0x |
| emulated, linear levels, everything in VRAM | 20.8 s | 1.0x |
| maps in host RAM (879 MB) | 35.9 s | 1.7x |
| similarity volumes in host RAM (6.0 GB) | 96.4 s | 4.7x |
| camera images in host RAM (186 MB) | 460 s | 22x |
| everything in host RAM (7.0 GB) | 543 s | 26x |

Per byte, that is volumes 13 s/GB, maps 17 s/GB, images 1,500 s/GB. Every similarity kernel
samples the camera images as random texture fetches with no reuse across the PCIe link; the
volumes are swept sequentially and the link is used at full width. So the order of things to
spill is the reverse of the design: volumes, then maps, never images. The emulation costs
15 % against native mipmaps on this card, and linear levels cost nothing against array levels,
so linear is the storage the Linux bundle should default to.

### Measured: the planner is worth more than the spill

v1 capped VRAM at 1.5 GB with the planner still sizing 24 tiles from `hipMemGetInfo`:
188 spills, 47.7 s. Same cap, v2 planner:

| VRAM cap | planner | simultaneous tiles | spills | DepthMap |
|---|---|---|---|---|
| none | upstream heuristic | 24 | 0 | 20.8 s |
| 1.5 GB | 0 (v1 behaviour, images now spillable) | 24 | 221 (4.6 GB volumes + 183 MB images in host RAM) | 496 s |
| 1.5 GB | 1 | 4 | 0 | 20.0 s |
| 4 GB | 1 | 8 | 0 | 19.8 s |
| 8 GB | 1 | 18 | 0 | 20.3 s |

Tile parallelism buys nothing on this GPU (4 tiles run as fast as 24), so keeping everything
resident and running fewer tiles at once is free. A card with 1.5 GB to spare runs the job at
full speed where v1 ran it 2.8x slower (and would have run it 25x slower had it been able to
spill the images). The planner change is upstreamable on its own.

### Measured: the final policy below one tile

Same card, caps chosen so that the whole job, then one full R camera, then a single tile no
longer fit (one tile with its images needs 669 MB here). `docs/validation/bridge-v2/rx9070-mini6-run3-final-policy.md`.

| VRAM cap | what the planner did | spills | DepthMap | bit-identical |
|---|---|---|---|---|
| none (native mipmaps) | 24 tiles | 0 | 17.9 s | yes |
| none (emulated, linear) | 24 tiles | 0 | 20.6 s | yes |
| 1.5 GB | 2 tiles | 0 | 20.0 s | yes |
| 1 GB | 1 tile | 0 | 20.3 s | yes |
| 700 MB | 1 tile, 29 MB of maps spill | 191 | 28.5 s | yes |
| 500 MB | 1 tile, 155 MB of volumes + 45 MB of maps spill, images resident | 197 | 77.6 s | yes |
| 500 MB, planner off | 24 tiles, 6 GB of volumes + 879 MB of maps spill | 504 | 111 s | yes |

Down to 1 GB the job runs at full speed. Below one tile it degrades gracefully instead of
failing (AliceVision's own planner throws "Not enough GPU memory to compute a single tile"),
and the images never leave VRAM. Next lever for that regime is smaller tiles
(`tileBufferWidth/Height` 512 quarters the volumes), which the planner could choose itself.
