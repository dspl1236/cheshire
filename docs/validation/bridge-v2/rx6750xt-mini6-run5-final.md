| case | build | knobs | DepthMap s | tiles | spills | volume VRAM/host MB | image VRAM/host MB | map VRAM/host MB | bit-identical | vs CUDA |
|---|---|---|---|---|---|---|---|---|---|---|
| default-array | emulated | `CHESHIRE_MIPMAP_STORAGE=array` | 31.068 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | FAIL |
| default-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear` | 31.244 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | FAIL |
| planner0-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_PLANNER=0` | 31.372 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | FAIL |
| img-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image` | 40.002 | 24 | 48 | 5988 / 0 | 0 / 186 | 879 / 0 | yes | FAIL |
| vol-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=volume CHESHIRE_BRIDGE_HOST_MB=7000` | 174.356 | 24 | 75 | 0 / 5988 | 186 / 0 | 879 / 0 | yes | FAIL |
| map-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=map` | 50.209 | 24 | 442 | 5988 / 0 | 186 / 0 | 0 / 879 | yes | FAIL |
| cap4000 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000` | 30.586 | 8 | 0 | 1996 / 0 | 186 / 0 | 312 / 0 | yes | FAIL |
| cap1500 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_HOST_MB=7000` | 30.471 | 2 | 0 | 499 / 0 | 186 / 0 | 100 / 0 | yes | FAIL |
| cap1500-p0-v1like | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=0 CHESHIRE_BRIDGE_HOST_MB=7000` | 190.507 | 24 | 504 | 187 / 5988 | 186 / 0 | 32 / 879 | yes | FAIL |
| cap700 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=700 CHESHIRE_BRIDGE_HOST_MB=7000` | 31.069 | 1 | 191 | 249 / 0 | 186 / 0 | 58 / 29 | yes | FAIL |
| cap500 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=500 CHESHIRE_BRIDGE_HOST_MB=7000` | 118.659 | 1 | 197 | 187 / 155 | 186 / 0 | 32 / 45 | yes | FAIL |
