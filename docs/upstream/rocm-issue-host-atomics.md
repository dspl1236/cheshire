# Draft: ROCm issue

Target: https://github.com/ROCm/clr/issues (HIP runtime) or https://github.com/ROCm/ROCm/issues.
Attach `hip/tests/host_atomics.hip`. Fill in nothing; every number below was measured.

---

**Title:** atomicMin into mapped host memory (hipHostMallocMapped, fine-grained) silently returns wrong results on a platform without PCIe atomics; atomicAdd is fine; non-coherent memory is fine

## Summary

On a Linux box whose PCIe root does not support AtomicOps, `atomicMin` from a kernel into
memory from `hipHostMalloc(..., hipHostMallocMapped)` (fine-grained, coherent) is wrong on
every element, with no error reported anywhere. `atomicAdd` on the same memory is correct.
Both are correct on `hipHostMallocMapped | hipHostMallocNonCoherent` memory, and on the same
test under Windows / PAL with an RX 9070.

I understand fine-grained system memory needs PCIe atomics for device atomics to be
carried to the host, and that not every atomic is a PCIe atomic (add/swap/compare-and-swap
are; min is not). What I am reporting is that the runtime lets the kernel run and the
operation silently produces wrong data, instead of either emulating it, failing the
allocation/launch, or documenting that the result is undefined on such platforms. In my
application (AliceVision's SGM aggregation, which `atomicMin`s into a per-row accumulator)
every depth map came out wrong and nothing in the logs pointed at memory.

## Environment

| | |
|---|---|
| GPU | Radeon RX 6750 XT (gfx1031) |
| CPU / platform | Intel Core i3-4330 (Haswell), consumer chipset, PCIe 3.0, no PCIe AtomicOps |
| OS | Linux Mint 22.3, kernel 7.0.0-31-generic, in-kernel amdgpu (no DKMS) |
| ROCm | HIP runtime 7.2 (`libamdhip64.so.7.2.70200`), `libhsa-runtime64.so.1.18.70200`, from the ROCm 7.2 apt repository |
| Control | same test on Windows 11, RX 9070 (gfx1201), ROCm 7.2.1 pip wheels, Adrenalin 26.8.1: all cases pass |

## Reproducer

`host_atomics.hip` (attached, ~100 lines). For each placement it runs, on one stream:
`memset` to 0xFF, 64 threads per slot `atomicMin` their candidate (slot index is the
minimum), read back; `memset` to 0, 64 threads per slot `atomicAdd(1)`, read back; then two
store/memset ordering checks. Build for the card and run:

```
hipcc --offload-arch=gfx1031 -O2 host_atomics.hip -o host_atomics
./host_atomics
```

## Output on the RX 6750 XT / Linux

```
device 0
VRAM                         atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped (default)        atomicMin bad=65536/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped coherent         atomicMin bad=65536/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped non-coherent     atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
RESULT: some placements FAIL
```

## Output on the RX 9070 / Windows (control)

```
device: AMD Radeon RX 9070
VRAM                         atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped (default)        atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped coherent         atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
host mapped non-coherent     atomicMin bad=0/65536  atomicAdd bad=0/65536  store->memset bad=0  memset->store bad=0
RESULT: all OK
```

## Expected

One of: the atomic is performed correctly (emulated through the device cache, as the
non-coherent case shows is possible); or the kernel launch / allocation fails with a clear
error on platforms without PCIe atomics; or the documentation for `hipHostMallocMapped`
states which atomics are undefined on such platforms. Silent wrong results are the one
outcome that costs users days.

## Context

Found while building a VRAM-to-system-RAM spill layer for AliceVision's depth-map stage on
Radeon cards (https://github.com/dspl1236/cheshire, `docs/02-memory-bridge.md` has the
full measurement). Switching the spill tier to `hipHostMallocNonCoherent` fixed it and, as
a bonus, made texture sampling from host memory ~20x faster on both platforms because the
device can cache it.
