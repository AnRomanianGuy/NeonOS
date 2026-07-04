#!/usr/bin/env bash
# NeonOS M0 — build unmodified LineageOS 22.2 for sargo. Run inside the guest.
# Produces OTA zip + boot.img in out/target/product/sargo/. Full log: ~/build-sargo.log
set -eo pipefail
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache

cd "$HOME/android/lineage"
source build/envsetup.sh
breakfast sargo

# -j6 (not nproc): leaves RAM headroom for metalava/lld under Rosetta on 16 GB
m bacon -j6 2>&1 | tee "$HOME/build-sargo.log" | grep --line-buffered -E "^\[ *[0-9]+% |error:|FAILED:|ninja: build stopped" || true

echo "=== BUILD FINISHED (checking artifacts) ==="
ls -lh out/target/product/sargo/lineage-*.zip out/target/product/sargo/boot.img 2>/dev/null \
  || { echo "BUILD FAILED — see ~/build-sargo.log"; exit 1; }
ccache -s | head -6
