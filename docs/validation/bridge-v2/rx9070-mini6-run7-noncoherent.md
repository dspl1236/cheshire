| case | build | knobs | DepthMap s | tiles | spills | volume VRAM/host MB | image VRAM/host MB | map VRAM/host MB | bit-identical | vs CUDA |
|---|---|---|---|---|---|---|---|---|---|---|
| native-default | native mipmap | `defaults` | 17.975 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| native-planner0 | native mipmap | `CHESHIRE_BRIDGE_PLANNER=0` | 16.95 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| native-cap1500 | native mipmap | `CHESHIRE_BRIDGE_VRAM_MB=1500` | 16.353 | 2 | 0 | 499 / 0 | 0 / 0 | 100 / 0 | yes | PASS |
| emu-array | emulated | `CHESHIRE_MIPMAP_STORAGE=array` | 20.368 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| emu-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear` | 20.196 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | PASS |
| emu-linear-img-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image` | 20.393 | 24 | 48 | 5988 / 0 | 0 / 186 | 879 / 0 | yes | PASS |
| emu-linear-map-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=map` | 25.46 | 24 | 442 | 5988 / 0 | 186 / 0 | 0 / 879 | yes | PASS |
| emu-linear-vol-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=volume` | 76.551 | 24 | 75 | 0 / 5988 | 186 / 0 | 879 / 0 | yes | PASS |
| emu-linear-all-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image,map,volume,other` | 84.233 | 24 | 565 | 0 / 5988 | 0 / 186 | 0 / 879 | yes | PASS |
| emu-linear-cap1500-p0 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=0` | 83.501 | 24 | 504 | 187 / 5988 | 186 / 0 | 32 / 879 | yes | PASS |
| emu-linear-cap1500-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500` | 19.927 | 2 | 0 | 499 / 0 | 186 / 0 | 100 / 0 | yes | PASS |
| emu-linear-cap1500-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=2` | 22.592 | 4 | 192 | 936 / 62 | 186 / 0 | 165 / 29 | yes | PASS |
| emu-linear-cap4000-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000` | 19.887 | 8 | 0 | 1996 / 0 | 186 / 0 | 312 / 0 | yes | PASS |
| emu-linear-cap4000-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000 CHESHIRE_BRIDGE_PLANNER=2` | 22.449 | 11 | 175 | 2744 / 0 | 186 / 0 | 418 / 29 | yes | PASS |
| emu-linear-cap8000-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=8000` | 20.341 | 18 | 0 | 4491 / 0 | 186 / 0 | 667 / 0 | yes | PASS |
| emu-linear-cap8000-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=8000 CHESHIRE_BRIDGE_PLANNER=2` | 20.556 | 22 | 7 | 5489 / 0 | 186 / 0 | 808 / 5 | yes | PASS |
