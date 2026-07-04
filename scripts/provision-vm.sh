#!/usr/bin/env bash
# NeonOS M0 — provision the neon-build VM (Ubuntu 24.04 arm64 + Rosetta) for LineageOS 22.2 builds.
# Idempotent: safe to re-run. Run inside the guest as the default user.
set -euo pipefail

echo "== [1/6] Rosetta binfmt check =="
if [ ! -e /proc/sys/fs/binfmt_misc/rosetta ]; then
  echo "ERROR: Rosetta binfmt not registered in guest. VM must be started by Lima with --rosetta (vz)." >&2
  exit 1
fi
echo "Rosetta binfmt: OK"

echo "== [2/6] Enable amd64 multiarch (AOSP prebuilts are x86_64) =="
# Ubuntu arm64 uses ports.ubuntu.com which has no amd64 packages; pin existing
# sources to arm64 and add archive.ubuntu.com for amd64.
if ! grep -q "Architectures:" /etc/apt/sources.list.d/ubuntu.sources; then
  sudo sed -i '/^Components:/a Architectures: arm64' /etc/apt/sources.list.d/ubuntu.sources
fi
sudo tee /etc/apt/sources.list.d/amd64.sources >/dev/null <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-security
Components: main universe multiverse restricted
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
sudo dpkg --add-architecture amd64
sudo apt-get update -qq

echo "== [3/6] Build dependencies =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  bc bison build-essential ccache curl flex git git-lfs gnupg gperf \
  imagemagick libelf-dev libssl-dev libxml2 libxml2-utils lzop m4 \
  libncurses-dev pngcrush rsync schedtool squashfs-tools xsltproc \
  zip unzip zlib1g-dev python3 python-is-python3 openssh-client

echo "== [4/6] amd64 runtime libraries for Rosetta-translated prebuilts =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 zlib1g:amd64 \
  libncurses6:amd64 libtinfo6:amd64 libxml2:amd64 libssl3t64:amd64 \
  libz3-4:amd64 || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 zlib1g:amd64 \
  libncurses6:amd64 libtinfo6:amd64 libxml2:amd64

echo "== [5/6] repo tool + git identity + ccache =="
mkdir -p ~/bin
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo
chmod a+rx ~/bin/repo
grep -q 'HOME/bin' ~/.profile || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.profile
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "NeonOS Builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "builder@neonos.local"
git config --global trailer.changeid.key "Change-Id" || true
grep -q USE_CCACHE ~/.profile || cat >> ~/.profile <<'EOF'
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
EOF
ccache -M 50G >/dev/null

echo "== [6/6] 16 GB swapfile (RAM headroom for link/metalava steps) =="
if [ ! -f /swapfile ]; then
  sudo fallocate -l 16G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

mkdir -p ~/android/lineage
echo
echo "Provisioning complete."
echo "  x86_64 sanity: $(ls /lib64/ld-linux-x86-64.so.2 2>/dev/null || echo 'MISSING ld-linux-x86-64')"
free -h | head -3
df -h / | tail -1
