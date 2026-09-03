# Validation: HIP depth maps vs the CUDA node

## Method
Same photos, same SfM, same DepthMap parameters; only the GPU stage differs.

1. Photos: [alicevision/dataset_monstree](https://github.com/alicevision/dataset_monstree)
   (`mini6` = 6 images, `full` = 41 images), copied to `house-pc:/data/scans/monstree-*`.
2. CUDA reference: Meshroom 2023.3.0 `meshroom_batch` on house-pc (GTX 1080 Ti, CUDA 11.3)
   with `FeatureExtraction:describerTypes=sift FeatureExtraction:forceCpuExtraction=False
   DepthMap:downscale=2` (the node's `standard` preset). The whole cache through
   `DepthMapFilter` is copied to `data/ref/<dataset>/` (tar over ssh).
3. HIP run: `scripts\run-depthmap.cmd <dataset>` feeds the reference `sfm.abc` and
   `PrepareDenseScene` images to the Windows/HIP `aliceVision_depthMapEstimation` with the
   exact command line Meshroom recorded in `DepthMap/*/0.status`, then runs
   `scripts/compare_depthmaps.py` (per-view valid-mask agreement, relative depth error
   distribution, simMap MAD, side-by-side PNGs).

Pass criterion (initial): >= 98 % of jointly-valid pixels within 1 % relative depth and
>= 95 % valid-mask agreement per view. The algorithms are deterministic, so differences
should come only from fast-math / FMA contraction and texture-filter precision.

## Reference numbers

| dataset | node | DepthMap wall time | notes |
|---|---|---|---|
| monstree-mini6 | GTX 1080 Ti, CUDA 11.3 | 31.9 s (6 views, 6 tiles/view, `--rangeSize 12`) | `data/ref/monstree-mini6/DepthMap/820d.../0.status` |
| monstree-mini6 | **RX 9070, HIP (Cheshire)** | **21.2 s** (same 6 views / 36 tiles, float4 camera textures) | `build/run-mini6.log` |
| monstree-full (41 views) | GTX 1080 Ti, CUDA 11.3 | 105.5 s | `data/ref/monstree-full/DepthMap/*/0.status` |
| monstree-full (41 views) | **RX 9070, HIP (Cheshire)** | **154.7 s** (float4 camera textures; not yet tuned) | `build/run-full.log` |

## Results

### monstree-mini6, 2026-09-03 — PASS

```
       view valid ref valid tst  agree  meanRel   medRel   p95Rel  <0.5%    <1%    <5%  simMAD
 1136735892     0.972     0.972  1.000   0.0056   0.0000   0.0008  0.985  0.989  0.994  0.2759
 1175796198     0.972     0.972  1.000   0.0019   0.0000   0.0007  0.984  0.988  0.993  0.1261
 1178536846     0.972     0.972  1.000   0.0107   0.0000   0.0012  0.978  0.984  0.990  0.2315
 1302207262     0.972     0.972  1.000   0.0088   0.0000   0.0010  0.980  0.985  0.990  0.2505
 1383319223     0.968     0.968  1.000   0.0039   0.0000   0.0009  0.983  0.987  0.992  0.1410
  677904057     0.972     0.972  1.000   0.0019   0.0000   0.0007  0.986  0.990  0.994  0.1368
RESULT: PASS
```

Valid masks identical, median relative depth error 0, p95 about 0.1 %, 98-99 % of pixels
within 1 %. The residual 1-2 % of pixels off by more than 1 % and the simMap MAD are
consistent with two different AliceVision versions (Meshroom 2023.3 = AliceVision 3.1 on the
node vs the 2026 development tree here) plus FMA/texture-filter differences; a same-version
CUDA reference would tighten this, and the 41-image set will show whether it holds at scale.

What it took to get from "runs" to "PASS": the first HIP run produced all-invalid maps
because **HIP on Windows samples half4 (16-bit float) texture arrays as zeros**
(`hip/tests/half_tex.hip` isolates it; float4 arrays are fine). AliceVision's camera
mipmaps use half4 by default; the HIP build now selects the float4 path (2x camera-image
VRAM). Revisit when ROCm fixes half textures on Windows, or when profiling shows texture
bandwidth matters.

### monstree-full (41 views), 2026-09-03 - strict criterion FAIL, agreement otherwise excellent

Full per-view table, CSV/JSON and downscaled best/median/worst panels:
[docs/validation/monstree-full/index.md](validation/monstree-full/index.md)
(mini6: [docs/validation/monstree-mini6/index.md](validation/monstree-mini6/index.md)).

* mask agreement >= 95 % on 41/41 views (40 of them exactly 1.000; view 1227295871 at 0.971)
* per-view **median** relative depth error is 0.0000 on all 41 views
* fraction within 1 %: median over views 0.988; 34 views >= 0.97; worst view 0.917 (1430763847),
  then 0.925 (528863451) and 0.928 (1317225462); largest per-view p95 = 7.1 %
* wall time 154.7 s on the RX 9070 vs 105.5 s on the 1080 Ti (mini6 was 21 s vs 32 s); the
  41-view run is not yet profiled - float4 textures double image bandwidth and the planner's
  tile parallelism has not been looked at

The strict bar (every view >= 98 % within 1 %) is not met on the large set. Looking at the
worst view (`docs/validation/monstree-full/worst_*.png`), the two maps are the same map;
differences are scattered speckle in low-texture regions with no tile or stripe structure,
which is the signature of different AliceVision versions (3.1 on the node vs 2026 dev tree)
and FMA/texture-filter precision, not of a broken kernel. To settle it properly the plan is a
same-version CUDA reference (build this AliceVision tree with CUDA on a NVIDIA box, or run the
CUDA backend of this exact tree on the node) - until then the numbers above are the honest
statement: identical validity masks, zero median error, ~1-8 % of pixels per view differing
by more than 1 %.
