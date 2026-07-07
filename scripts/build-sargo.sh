#!/usr/bin/env bash
# NeonOS M0 — build unmodified LineageOS 22.2 for sargo. Run on the build host
# (primary: Nobara machine; also works in the fallback VM).
# Produces OTA zip + boot.img in out/target/product/sargo/. Full log: ~/build-sargo.log
set -eo pipefail
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache

cd "$HOME/android/lineage"
source build/envsetup.sh
breakfast sargo

# jobs = min(nproc, RAM/2 GB): leaves headroom for metalava/lld link steps
jobs=$(nproc)
mem_gb=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)
(( mem_gb / 2 < jobs )) && jobs=$(( mem_gb / 2 ))
(( jobs < 2 )) && jobs=2
echo "Building with -j${jobs} (${mem_gb} GB RAM, $(nproc) cores)"

m bacon -j"$jobs" 2>&1 | tee "$HOME/build-sargo.log" | grep --line-buffered -E "^\[ *[0-9]+% |error:|FAILED:|ninja: build stopped" || true

echo "=== BUILD FINISHED (checking artifacts) ==="
ls -lh out/target/product/sargo/lineage-*.zip out/target/product/sargo/boot.img 2>/dev/null \
  || { echo "BUILD FAILED — see ~/build-sargo.log"; exit 1; }
ccache -s | head -6
