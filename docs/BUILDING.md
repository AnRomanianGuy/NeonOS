# Building NeonOS — Pixel 3a (`sargo`)

**Base:** LineageOS 22.2 (Android 15), branch `lineage-22.2`
**Primary build host:** the Nobara Linux machine (Fedora-based, x86_64)
**Fallback:** Lima+Rosetta VM on the M4 Mac (dormant — see NEON_PROJECT.md §10)

> During M0 the build target is the **unmodified** `lineage_sargo` (userdebug). From M1 onward this guide switches to the `neon_sargo` target — it will be updated then.

---

## 1. Requirements

| Item | Minimum | Notes |
|---|---|---|
| OS | Nobara / Fedora x86_64 | Native Linux is the officially supported AOSP path |
| Disk | **400–500 GB free** on an internal SSD | ext4 or btrfs (case-sensitive). **Never** exFAT/NTFS or an eCryptfs home |
| RAM | 16 GB (32 GB comfortable) | Nobara ships zram by default, which helps; see job-count rule in §4 |
| Network | ~100–150 GB download for the first sync | |

## 2. One-time setup

> **Shortcut:** everything in §2–§3 is automated by **`scripts/setup-nobara.sh`**. Copy the whole `scripts/` folder to the Nobara machine and run `./setup-nobara.sh` (idempotent; interrupted syncs resume). Then build with `./build-sargo.sh` (§4 automated — picks a safe job count from RAM/cores). The manual steps below document what the script does.

### 2.1 Packages

```bash
sudo dnf install -y @development-tools android-tools bc bison ccache curl flex \
  git git-lfs gnupg2 gperf ImageMagick libxml2 libxslt lz4 lzop ncurses-devel \
  openssl openssl-devel python3 rsync schedtool squashfs-tools unzip zip zlib-devel perl
```

Notes:
- No JDK needed — AOSP bundles its own prebuilt toolchain (clang, JDK, Python).
- If some legacy host tool ever complains about 32-bit libs (rare on Android 15):
  `sudo dnf install -y glibc-devel.i686 zlib-devel.i686 libstdc++.i686`

### 2.2 The `repo` tool

```bash
mkdir -p ~/.local/bin
curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo
chmod a+x ~/.local/bin/repo
# ensure ~/.local/bin is in PATH (Fedora's default ~/.bashrc already does this)
```

### 2.3 Git identity (repo refuses to run without it)

```bash
git config --global user.name  "NeonOS Builder"
git config --global user.email "trooperro75@gmail.com"
git lfs install
```

### 2.4 ccache (makes rebuilds dramatically faster)

```bash
ccache -M 50G
cat >> ~/.bashrc <<'EOF'
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
EOF
```

## 3. Getting the source

```bash
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
```

Add the NeonOS local manifest (device trees, kernel, TheMuppets blobs — all pinned to `lineage-22.2`). The file lives in this project repo:

```bash
mkdir -p .repo/local_manifests
cp /path/to/NeonOS-project/scripts/local_manifest_neon.xml .repo/local_manifests/neon.xml
```

Then sync (hours on first run; safe to interrupt and re-run — it resumes):

```bash
repo sync -c -j8 --no-clone-bundle --no-tags --retry-fetches=3
```

## 4. Building

```bash
cd ~/android/lineage
source build/envsetup.sh
breakfast sargo          # sets up the lineage_sargo-userdebug target
m bacon -jN              # N = min(nproc, RAM_GB / 2); e.g. 16 GB RAM → -j8
```

- `m bacon` produces the flashable OTA zip. First native build: roughly 1.5–4 h depending on CPU; incrementals with ccache are much faster.
- Keep the machine on AC power and don't let it suspend mid-build.

## 5. Artifacts

Everything lands in `out/target/product/sargo/`:

| File | Purpose |
|---|---|
| `lineage-22.2-*-UNOFFICIAL-sargo.zip` | The ROM (sideload this) |
| `boot.img` | Contains Lineage recovery — flashed via fastboot on first install |

Copy what you need off the machine, e.g. `scp` the zip + `boot.img` to the Mac/T7 releases folder.

## 6. Flashing

Full verified procedure (prerequisites, bootloader unlock, recovery, sideload) is maintained in one place: **NEON_PROJECT.md §10 → Flash procedure**. Short version: `fastboot flash boot boot.img` → recovery → Format data → `adb -d sideload lineage-*.zip`.

`fastboot` runs fine from the Nobara machine (`android-tools` is installed). If `fastboot devices` shows nothing as a regular user, add the [android-udev-rules](https://github.com/M0Rf30/android-udev-rules) or run it once with `sudo` to confirm it's a permissions issue.

## 7. Staying up to date / rebuilding

```bash
cd ~/android/lineage
repo sync -c -j8 --no-clone-bundle --no-tags   # pull upstream updates
source build/envsetup.sh && breakfast sargo
m bacon -jN
```

After every build session: update NEON_PROJECT.md (§7 progress, §10–11 findings) per project rules.

## 8. Troubleshooting

- **OOM / machine freezes during link or metalava steps** → lower `-jN` (even `-j4`); confirm zram is active (`zramctl`); add a swapfile if needed.
- **`repo sync` errors on a project** → re-run with `--force-sync`; a single flaky project can also be fixed by deleting it under `.repo/projects/` and re-syncing.
- **`breakfast sargo` can't find the device or vendor tree** → the local manifest wasn't copied before `repo sync`; copy it (§3) and sync again.
- **Signature/verification oddities on sideload** → unofficial test-key builds warn in recovery; that's expected until we sign with NeonOS keys (M1).
- **Never build on exFAT/NTFS** — silent case-collision corruption.
