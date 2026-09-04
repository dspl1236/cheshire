| case | build | knobs | DepthMap s | tiles | spills | volume VRAM/host MB | image VRAM/host MB | map VRAM/host MB | bit-identical | vs CUDA |
|---|---|---|---|---|---|---|---|---|---|---|
| default-array | emulated | `CHESHIRE_MIPMAP_STORAGE=array` | 31.113 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | FAIL |
| default-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear` | 31.639 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | FAIL |
| planner0-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_PLANNER=0` | 31.325 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | FAIL |
| img-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image` | 2529.006 | 24 | 48 | 5988 / 0 | 0 / 186 | 879 / 0 | yes | FAIL |
| vol-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=volume` | None | 24 | 42 | 0 / 3656 | 0 / 0 | 65 / 0 | no (nan) | FAIL |
| map-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=map` | 58.055 | 24 | 442 | 5988 / 0 | 186 / 0 | 0 / 879 | no (0.949) | FAIL |
| cap4000 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000` | 30.882 | 8 | 0 | 1996 / 0 | 186 / 0 | 312 / 0 | yes | FAIL |
| cap1500 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_HOST_MB=7000` | 30.533 | 2 | 0 | 499 / 0 | 186 / 0 | 100 / 0 | yes | FAIL |
| cap1500-p0-v1like | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=0 CHESHIRE_BRIDGE_HOST_MB=7000` | 292.419 | 24 | 504 | 187 / 5988 | 186 / 0 | 32 / 879 | no (0.949) | FAIL |
| cap700 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=700 CHESHIRE_BRIDGE_HOST_MB=7000` | 30.626 | 1 | 191 | 249 / 0 | 186 / 0 | 58 / 29 | no (0.949) | FAIL |
