#!/usr/bin/env bash
# NeonOS — build for sargo. Run on the build host (primary: Nobara machine;
# also works in the fallback VM).
# Produces OTA zip + boot.img in out/target/product/sargo/. Full log: ~/build-sargo.log
#
# Usage: ./build-sargo.sh [lunch-target]
#   Defaults to neon_sargo-<release>-userdebug (NeonOS). Pass
#   lineage_sargo-<release>-userdebug to rebuild the untouched LineageOS
#   baseline for A/B regression comparison.
#   (breakfast sargo always resolves to lineage_sargo regardless of what's
#   registered in AndroidProducts.mk, so an explicit `lunch` is required here.
#   Lunch combos in this tree need the 3-part <product>-<release>-<variant>
#   form, not the older 2-part shorthand — <release> comes from the same
#   vendor/lineage/vars/aosp_target_release file breakfast() itself sources.)
set -eo pipefail
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache

cd "$HOME/android/lineage"
source build/envsetup.sh
source vendor/lineage/vars/aosp_target_release   # sets $aosp_target_release, e.g. "bp1a"

TARGET="${1:-neon_sargo-${aosp_target_release}-userdebug}"
lunch "$TARGET"

# vendor/lineage/build/envsetup.sh's check_product() (called by lunch() above)
# only sets/exports LINEAGE_BUILD for products literally named "lineage_<device>"
# — it strips that exact prefix to get the device codename. That gate controls
# whether build/make/core/config.mk pulls in vendor/lineage/config/BoardConfigLineage.mk,
# which registers Soong's "lineageVarsPlugin" config (KERNEL_BUILD_OUT_PREFIX,
# PATH_OVERRIDE_SOONG, etc. — needed by vendor/lineage/build/soong/Android.bp's
# kernel-header genrules) plus the bootanimation/charger Soong config. Since
# NeonOS products are named "neon_<device>" instead, LINEAGE_BUILD silently
# stays empty and that whole block gets skipped, breaking the build. Not fixed
# upstream (avoids patching vendor/lineage directly) — re-derive it here the
# same way check_product() does, just for our own prefix.
case "$TARGET" in
  neon_*)
    export LINEAGE_BUILD="$(echo "$TARGET" | sed -E 's/^neon_([^-]+)-.*/\1/')"
    # ro.lineage.releasetype (compared by the Updater app, see
    # packages/apps/Updater's Constants.PROP_RELEASE_TYPE) defaults to
    # UNOFFICIAL unless RELEASE_TYPE is one of RELEASE/NIGHTLY/SNAPSHOT/
    # EXPERIMENTAL (vendor/lineage/config/version.mk) — there's no literal
    # "OFFICIAL" value the build system recognizes; RELEASE is LineageOS's
    # own term for what NeonOS's own release builds are. Left unset for
    # lineage_* baseline-comparison builds, which should report their real
    # (unofficial) status.
    export RELEASE_TYPE=RELEASE
    ;;
esac

# jobs = min(nproc, RAM/2 GB): leaves headroom for metalava/lld link steps
jobs=$(nproc)
mem_gb=$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)
(( mem_gb / 2 < jobs )) && jobs=$(( mem_gb / 2 ))
(( jobs < 2 )) && jobs=2
echo "Building ${TARGET} with -j${jobs} (${mem_gb} GB RAM, $(nproc) cores)"

# Capture m bacon's own exit code via PIPESTATUS, not the grep filter's — grep
# exiting 0/1 depending on whether it happened to match a line is unrelated to
# whether the build itself succeeded, and out/target/product/sargo/ is shared
# across lunch targets (all sargo builds land there), so a failed build can
# leave a *previous* successful build's artifacts looking deceptively fresh.
m bacon -j"$jobs" 2>&1 | tee "$HOME/build-sargo.log" | grep --line-buffered -E "^\[ *[0-9]+% |error:|FAILED:|ninja: build stopped" || true
build_status=${PIPESTATUS[0]}

echo "=== BUILD FINISHED (checking artifacts) ==="
if [[ $build_status -ne 0 ]]; then
  echo "BUILD FAILED (m bacon exited ${build_status}) — see ~/build-sargo.log"
  exit 1
fi
ls -lh out/target/product/sargo/lineage-*.zip out/target/product/sargo/boot.img
ccache -s | head -6
