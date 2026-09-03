#!/usr/bin/env bash
# Cheshire node glue: vendor-neutral replacement for the `nvidia-smi` precondition in the
# photogrammetry node's `reconstruct` script. Prints "<vendor> <name> <vram MB>" and exits 0
# when a usable GPU is found, 1 otherwise. Usage: gpu-precheck.sh [--quiet]
set -uo pipefail
if command -v amd-smi >/dev/null 2>&1; then
  name=$(amd-smi static --asic --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); g=d[0] if isinstance(d,list) else d; a=g.get("asic",g); print(a.get("market_name","AMD GPU"))' 2>/dev/null || echo "AMD GPU")
  vram=$(amd-smi static --vram --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); g=d[0] if isinstance(d,list) else d; v=g.get("vram",g); s=v.get("size",{}); print(s.get("value", s) if isinstance(s,dict) else s)' 2>/dev/null || echo "?")
  echo "amd $name $vram"; exit 0
fi
if command -v rocm-smi >/dev/null 2>&1 && rocm-smi --showproductname >/dev/null 2>&1; then
  name=$(rocm-smi --showproductname 2>/dev/null | grep -i "Card Series" | head -1 | sed 's/.*:\s*//')
  vram=$(rocm-smi --showmeminfo vram --csv 2>/dev/null | tail -1 | awk -F, '{printf "%d", $2/1048576}')
  echo "amd ${name:-AMD GPU} ${vram:-?}"; exit 0
fi
if command -v nvidia-smi >/dev/null 2>&1; then
  line=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
  [ -n "$line" ] && { echo "nvidia ${line%%,*} $(echo "$line" | awk -F, '{print $2+0}')"; exit 0; }
fi
[ "${1:-}" = "--quiet" ] || echo "no usable GPU found (looked for amd-smi, rocm-smi, nvidia-smi)" >&2
exit 1
