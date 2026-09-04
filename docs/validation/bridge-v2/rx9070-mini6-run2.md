| case | build | knobs | DepthMap s | tiles | spills | volume VRAM/host MB | image VRAM/host MB | map VRAM/host MB | bit-identical | vs CUDA |
|---|---|---|---|---|---|---|---|---|---|---|
| native-default | native mipmap | `defaults` | 17.895 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| native-planner0 | native mipmap | `CHESHIRE_BRIDGE_PLANNER=0` | 17.554 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| native-cap1500 | native mipmap | `CHESHIRE_BRIDGE_VRAM_MB=1500` | 16.836 | 4 | 0 | 998 / 0 | 0 / 0 | 170 / 0 | yes | PASS |
| emu-array | emulated | `CHESHIRE_MIPMAP_STORAGE=array` | 20.623 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| emu-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear` | 20.785 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | PASS |
| emu-linear-img-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image` | 460.49 | 24 | 48 | 5988 / 0 | 0 / 186 | 879 / 0 | yes | PASS |
| emu-linear-map-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=map` | 35.888 | 24 | 442 | 5988 / 0 | 186 / 0 | 0 / 879 | yes | PASS |
| emu-linear-vol-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=volume` | 96.372 | 24 | 75 | 0 / 5988 | 186 / 0 | 879 / 0 | yes | PASS |
| emu-linear-all-host | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_HOST_CLASSES=image,map,volume,other` | 543.26 | 24 | 565 | 0 / 5988 | 0 / 186 | 0 / 879 | yes | PASS |
| emu-linear-cap1500-p0 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=0` | 495.668 | 24 | 221 | 1406 / 4581 | 3 / 183 | 90 / 789 | yes | PASS |
| emu-linear-cap1500-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500` | 19.96 | 4 | 0 | 998 / 0 | 186 / 0 | 170 / 0 | yes | PASS |
| emu-linear-cap1500-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500 CHESHIRE_BRIDGE_PLANNER=2` | 19.533 | 4 | 0 | 998 / 0 | 186 / 0 | 170 / 0 | yes | PASS |
| emu-linear-cap4000-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000` | 19.796 | 8 | 0 | 1996 / 0 | 186 / 0 | 312 / 0 | yes | PASS |
| emu-linear-cap4000-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=4000 CHESHIRE_BRIDGE_PLANNER=2` | 19.898 | 11 | 0 | 2744 / 0 | 186 / 0 | 418 / 0 | yes | PASS |
| emu-linear-cap8000-p1 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=8000` | 20.308 | 18 | 0 | 4491 / 0 | 186 / 0 | 667 / 0 | yes | PASS |
| emu-linear-cap8000-p2 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=8000 CHESHIRE_BRIDGE_PLANNER=2` | 20.649 | 22 | 0 | 5489 / 0 | 186 / 0 | 808 / 0 | yes | PASS |
