#!/usr/bin/env bash
# NeonOS M0 — one-command build setup for the Nobara Linux machine.
# Automates docs/BUILDING.md §2–3: packages, repo tool, git identity, ccache,
# source checkout at ~/android/lineage (lineage-22.2 + NeonOS local manifest), repo sync.
#
# Usage: copy the whole scripts/ folder to the Nobara machine, then:  ./setup-nobara.sh
# Idempotent — safe to re-run; an interrupted sync resumes where it stopped.
# After it finishes:  ./build-sargo.sh
set -euo pipefail

SRC="$HOME/android/lineage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/local_manifest_neon.xml"

log() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# --- 0. Sanity checks -------------------------------------------------------
[[ -f "$MANIFEST" ]] || { echo "ERROR: local_manifest_neon.xml not found next to this script — copy the whole scripts/ folder."; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "ERROR: expected an x86_64 host."; exit 1; }
command -v dnf >/dev/null || { echo "ERROR: dnf not found — this script targets Nobara/Fedora."; exit 1; }

avail_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
if (( avail_gb < 400 )); then
  echo "WARNING: only ${avail_gb} GB free on \$HOME — 400+ GB recommended for source + build output."
  read -r -p "Continue anyway? [y/N] " ans; [[ "$ans" == [yY] ]] || exit 1
fi

# --- 1. Build dependencies --------------------------------------------------
log "Installing build dependencies (dnf — asks for sudo password)"
sudo dnf install -y @development-tools android-tools bc bison ccache curl flex \
  git git-lfs gnupg2 gperf ImageMagick libxml2 libxslt lz4 lzop ncurses-devel \
  openssl openssl-devel python3 rsync schedtool squashfs-tools unzip zip zlib-devel perl

# --- 2. repo tool -----------------------------------------------------------
log "Installing the repo tool"
mkdir -p "$HOME/.local/bin"
if [[ ! -x "$HOME/.local/bin/repo" ]]; then
  curl -fsSL -o "$HOME/.local/bin/repo" https://storage.googleapis.com/git-repo-downloads/repo
  chmod a+x "$HOME/.local/bin/repo"
fi
export PATH="$HOME/.local/bin:$PATH"

# --- 3. Git identity (kept if already configured) ---------------------------
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "NeonOS Builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "builder@neonos.local"
git lfs install >/dev/null

# --- 4. ccache ---------------------------------------------------------------
log "Configuring ccache (50 GB)"
ccache -M 50G >/dev/null
if ! grep -q USE_CCACHE "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'EOF'

# NeonOS build environment
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export PATH="$HOME/.local/bin:$PATH"
EOF
fi

# --- 5. Source tree ----------------------------------------------------------
log "Initializing source tree at $SRC (lineage-22.2)"
mkdir -p "$SRC"
cd "$SRC"
[[ -d .repo/manifests ]] || repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
mkdir -p .repo/local_manifests
cp -f "$MANIFEST" .repo/local_manifests/neon.xml

# --- 6. Sync -----------------------------------------------------------------
log "Syncing source (first run downloads 100–150 GB — hours; safe to interrupt and re-run)"
repo sync -c -j8 --no-clone-bundle --no-tags --retry-fetches=3

log "DONE — source ready at $SRC"
echo "Next step:  $SCRIPT_DIR/build-sargo.sh   (unmodified lineage_sargo baseline, M0)"
