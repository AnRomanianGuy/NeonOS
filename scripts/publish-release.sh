#!/usr/bin/env bash
# NeonOS — publish a built sargo OTA zip as a GitHub Release and update that
# channel's ota/sargo.json, the manifest the on-device Updater app polls (see
# updater_server_url in packages/apps/Updater/app/src/main/res/values/strings.xml,
# and the channel spinner in preferences_dialog.xml / UpdatesActivity.java).
#
# Two channels, each its own orphan git branch holding nothing but its own
# ota/sargo.json ("release" and "beta") -- kept separate from main (which is
# docs/scripts/dev only) so publishing a build never touches main at all.
#
# Usage: ./publish-release.sh <release|beta> <path-to-ota-zip> [build.prop path]
#   Defaults build.prop to <zip-dir>/system/build.prop, which is where it
#   lands for a normal build-sargo.sh run (out/target/product/sargo/).
#
# Requires the `gh` CLI, authenticated (`gh auth login`) with push access to
# github.com/AnRomanianGuy/NeonOS.
set -euo pipefail

CHANNEL="${1:?Usage: $0 <release|beta> <path-to-ota-zip> [build.prop path]}"
ZIP_PATH="${2:?Usage: $0 <release|beta> <path-to-ota-zip> [build.prop path]}"
BUILD_PROP="${3:-$(dirname "$ZIP_PATH")/system/build.prop}"
REPO="AnRomanianGuy/NeonOS"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$CHANNEL" in
    release|beta) ;;
    *) echo "Channel must be 'release' or 'beta', got: $CHANNEL" >&2; exit 1 ;;
esac
[ -f "$ZIP_PATH" ] || { echo "OTA zip not found: $ZIP_PATH" >&2; exit 1; }
[ -f "$BUILD_PROP" ] || { echo "build.prop not found: $BUILD_PROP (pass it explicitly as \$3)" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || {
    echo "gh CLI not found. Install it and run 'gh auth login' once, then re-run this script." >&2
    exit 1
}
command -v jq >/dev/null 2>&1 || { echo "jq not found (needed to update ota/sargo.json)." >&2; exit 1; }

get_prop() { grep -m1 "^$1=" "$BUILD_PROP" | cut -d= -f2-; }

# These three match exactly what the Updater app (Utils.isCompatible/canInstall,
# see Constants.PROP_BUILD_DATE/PROP_BUILD_VERSION/PROP_RELEASE_TYPE) compares
# against the device's own props at update-check time -- ro.build.date.utc is
# the actual "is this newer" gate; ro.lineage.build.version stays "22.2" for
# every NeonOS build on this branch (compareVersions() only requires >=, which
# a constant value always satisfies) and isn't the real freshness signal.
DATETIME="$(get_prop ro.build.date.utc)"
VERSION="$(get_prop ro.lineage.build.version)"
ROMTYPE="$(get_prop ro.lineage.releasetype)"
[ -n "$DATETIME" ] && [ -n "$VERSION" ] && [ -n "$ROMTYPE" ] || {
    echo "Could not read ro.build.date.utc / ro.lineage.build.version / ro.lineage.releasetype from $BUILD_PROP" >&2
    exit 1
}

FILENAME="$(basename "$ZIP_PATH")"
SIZE="$(stat -c%s "$ZIP_PATH")"
SHA256="$(sha256sum "$ZIP_PATH" | cut -d' ' -f1)"
TAG="sargo-$CHANNEL-$DATETIME"

echo "== Publishing $FILENAME to the $CHANNEL channel =="
echo "   version=$VERSION  romtype=$ROMTYPE  datetime=$DATETIME  size=$SIZE"
echo "   sha256=$SHA256"

gh release create "$TAG" "$ZIP_PATH" \
    --repo "$REPO" \
    --title "NeonOS sargo $DATETIME ($CHANNEL, $ROMTYPE)" \
    --notes "Automated NeonOS OTA build for sargo.

channel: $CHANNEL
version: $VERSION
romtype: $ROMTYPE
sha256: $SHA256"

DOWNLOAD_URL="$(gh release view "$TAG" --repo "$REPO" --json assets \
    --jq ".assets[] | select(.name==\"$FILENAME\") | .url")"
[ -n "$DOWNLOAD_URL" ] || { echo "Could not resolve the uploaded asset's download URL." >&2; exit 1; }

# The manifest lives only on the $CHANNEL branch, never on main -- use a
# throwaway worktree so this never disturbs whatever's currently checked out
# in $ROOT_DIR (e.g. uncommitted docs edits on main).
WORKTREE_DIR="$(mktemp -d)"
trap 'git -C "$ROOT_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null; rm -rf "$WORKTREE_DIR"' EXIT

git -C "$ROOT_DIR" fetch origin "$CHANNEL"
git -C "$ROOT_DIR" worktree add "$WORKTREE_DIR" "$CHANNEL"

MANIFEST="$WORKTREE_DIR/ota/sargo.json"
jq --arg dt "$DATETIME" --arg fn "$FILENAME" --arg id "$SHA256" \
   --arg rt "$ROMTYPE" --argjson sz "$SIZE" --arg url "$DOWNLOAD_URL" --arg ver "$VERSION" \
   '.response = [{"datetime": ($dt | tonumber), "filename": $fn, "id": $id, "romtype": $rt, "size": $sz, "url": $url, "version": $ver}] + .response' \
   "$MANIFEST" > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"

git -C "$WORKTREE_DIR" add ota/sargo.json
git -C "$WORKTREE_DIR" commit -m "Publish sargo OTA build $DATETIME ($CHANNEL, $ROMTYPE)"
git -C "$WORKTREE_DIR" push origin "$CHANNEL"

echo "Done: release $TAG published, $CHANNEL's ota/sargo.json updated and pushed."
