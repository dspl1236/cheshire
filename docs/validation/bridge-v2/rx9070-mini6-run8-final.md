| case | build | knobs | DepthMap s | tiles | spills | volume VRAM/host MB | image VRAM/host MB | map VRAM/host MB | bit-identical | vs CUDA |
|---|---|---|---|---|---|---|---|---|---|---|
| native-default | native mipmap | `defaults` | 17.905 | 24 | 0 | 5988 / 0 | 0 / 0 | 879 / 0 | yes | PASS |
| emu-linear | emulated | `CHESHIRE_MIPMAP_STORAGE=linear` | 20.249 | 24 | 0 | 5988 / 0 | 186 / 0 | 879 / 0 | yes | PASS |
| emu-linear-cap1500 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1500` | 19.72 | 2 | 0 | 499 / 0 | 186 / 0 | 100 / 0 | yes | PASS |
| emu-linear-cap1000 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=1000` | 19.734 | 1 | 0 | 249 / 0 | 186 / 0 | 64 / 0 | yes | PASS |
| emu-linear-cap700 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=700` | 22.268 | 1 | 191 | 249 / 0 | 186 / 0 | 58 / 29 | yes | PASS |
| emu-linear-cap500 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=500` | 46.926 | 1 | 197 | 187 / 155 | 186 / 0 | 32 / 45 | yes | PASS |
| emu-linear-cap500-p0 | emulated | `CHESHIRE_MIPMAP_STORAGE=linear CHESHIRE_BRIDGE_VRAM_MB=500 CHESHIRE_BRIDGE_PLANNER=0` | 83.681 | 24 | 504 | 187 / 5988 | 186 / 0 | 32 / 879 | yes | PASS |
| native-cap500 | native mipmap | `CHESHIRE_BRIDGE_VRAM_MB=500` | 40.478 | 1 | 17 | 187 / 155 | 0 / 0 | 32 / 45 | yes | PASS |
