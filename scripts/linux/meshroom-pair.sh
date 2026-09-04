#!/usr/bin/env bash
# Cheshire: pair a Meshroom 2023.3 Linux bundle with the Cheshire HIP AliceVision bundle.
#
# Meshroom runs its nodes as aliceVision_* executables from <Meshroom>/aliceVision/bin. Only
# DepthMap needs the GPU, so the pairing is one file: that binary becomes a wrapper that execs
# the HIP build with the Cheshire bundle's libraries in front, or the original CUDA binary
# (kept as aliceVision_depthMapEstimation.cuda) when nvidia-smi finds an NVIDIA card: the
# choice is made per run, so a node that swaps cards needs no re-pairing. Everything else
# (SfM, meshing, texturing) keeps running from the Meshroom bundle unchanged. `--unpair` restores.
#
#   meshroom-pair.sh <Meshroom dir> [<cheshire bundle dir>]      # default bundle: ~/apps/cheshire/bundle
#   meshroom-pair.sh <Meshroom dir> --unpair
#
# The Meshroom 2023.3 DepthMap node's command line is accepted by the newer AliceVision the HIP
# build is based on except --sgmFilteringAxes, which upstream removed (YX is the only behaviour
# now, and the one docs/04-validation.md validates); the wrapper drops it.
set -euo pipefail
MESHROOM="${1:?Meshroom directory (e.g. ~/apps/Meshroom-2023.3.0)}"
BIN="$MESHROOM/aliceVision/bin"
TARGET="$BIN/aliceVision_depthMapEstimation"
if [ "${2:-}" = "--unpair" ]; then
  if [ -x "$TARGET.cuda" ]; then mv -f "$TARGET.cuda" "$TARGET"; echo "restored CUDA aliceVision_depthMapEstimation"; else echo "not paired"; fi
  exit 0
fi
BUNDLE="${2:-$HOME/apps/cheshire/bundle}"
[ -x "$BUNDLE/bin/aliceVision_depthMapEstimation" ] || { echo "no HIP aliceVision_depthMapEstimation in $BUNDLE/bin"; exit 1; }
[ -d "$BIN" ] || { echo "$BIN not found: is $MESHROOM a Meshroom 2023.x Linux bundle?"; exit 1; }
if [ ! -e "$TARGET.cuda" ]; then
  mv "$TARGET" "$TARGET.cuda"
fi
cat > "$TARGET" <<EOF
#!/bin/bash
# Cheshire pairing (scripts/linux/meshroom-pair.sh): DepthMap on whichever GPU is in the box.
# NVIDIA present (nvidia-smi answers): the original CUDA binary, kept beside this file as
# .cuda. Otherwise the HIP build from the Cheshire bundle. Decided per run, so swapping cards
# needs no re-pairing. CHESHIRE_DEPTHMAP=cuda|hip forces one.
if [ "\${CHESHIRE_DEPTHMAP:-auto}" = cuda ] || { [ "\${CHESHIRE_DEPTHMAP:-auto}" = auto ] && nvidia-smi >/dev/null 2>&1; }; then
  exec "$TARGET.cuda" "\$@"
fi
# Meshroom's environment stays; the Cheshire bundle's libraries go first so the HIP build
# resolves its own OpenImageIO/Boost/ROCm sonames, not the Meshroom bundle's older ones.
export ALICEVISION_ROOT="$BUNDLE"
export LD_LIBRARY_PATH="$BUNDLE/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
# per-node knobs: HSA_OVERRIDE_GFX_VERSION for RDNA2 parts without their own code object,
# CHESHIRE_BRIDGE_* for the memory bridge (see docs/02-memory-bridge.md)
[ -f "$BUNDLE/../env.sh" ] && . "$BUNDLE/../env.sh"
# Meshroom 2023.3 still passes --sgmFilteringAxes "YX"; upstream AliceVision removed the option
# (the HIP build is based on 2026 upstream and always filters YX). Drop it, keep everything else.
ARGS=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    --sgmFilteringAxes) shift 2 ;;
    *) ARGS+=("\$1"); shift ;;
  esac
done
exec "$BUNDLE/bin/aliceVision_depthMapEstimation" "\${ARGS[@]}"
EOF
chmod +x "$TARGET"
echo "paired: $TARGET -> $BUNDLE/bin/aliceVision_depthMapEstimation (CUDA binary kept as $TARGET.cuda)"
