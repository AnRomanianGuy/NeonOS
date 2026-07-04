#!/usr/bin/env bash
# NeonOS M0 — init + sync LineageOS 22.2 source for sargo. Run inside the guest.
# Idempotent: re-running resumes/updates the sync.
set -euo pipefail
export PATH="$HOME/bin:$PATH"

SRC="$HOME/android/lineage"
mkdir -p "$SRC"
cd "$SRC"

if [ ! -d .repo/manifests ]; then
  repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs < /dev/null
fi

mkdir -p .repo/local_manifests
cp /Volumes/T7/Proiecte/NeonOS/scripts/local_manifest_neon.xml .repo/local_manifests/neon.xml

repo sync -c -j8 --force-sync --no-clone-bundle --no-tags --retry-fetches=3 < /dev/null
echo "=== SYNC COMPLETE ==="
df -h / | tail -1
du -sh "$SRC" 2>/dev/null | tail -1
