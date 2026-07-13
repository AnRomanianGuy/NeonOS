# NeonOS OTA — GitHub-hosted updates (M4)

**GitHub presence:** [github.com/AnRomanianGuy/NeonOS](https://github.com/AnRomanianGuy/NeonOS) (public)
**On-device app:** NeonOS Updater (Settings → System update), `packages/apps/Updater`

---

## 1. Two channels, two branches

NeonOS ships two update channels, each its own **orphan git branch** holding
nothing but its own `ota/sargo.json` — kept separate from `main` (docs/scripts/
dev only) so publishing a build never touches `main`:

- **`release`** branch — stable channel.
- **`beta`** branch — beta channel. **This is where builds get published for
  now**, until there's a first real stable release.

On-device, Settings → System update → preferences → **Update channel** is a
dropdown (Release / Beta) that picks which branch the Updater polls. Default
is **Beta**.

## 2. How it works

1. A build is produced normally via `scripts/build-sargo.sh`, which outputs a
   signed OTA zip in `out/target/product/sargo/`.
2. `scripts/publish-release.sh <release|beta> <zip>` uploads that zip as a
   GitHub Release, then updates and pushes `ota/sargo.json` on the chosen
   channel branch.
3. The Updater app's `updater_server_url`
   (`packages/apps/Updater/app/src/main/res/values/strings.xml`) is
   `https://raw.githubusercontent.com/AnRomanianGuy/NeonOS/{channel}/ota/sargo.json`
   — `{channel}` is substituted at request time
   (`Utils.getServerURL()`) from the user's dropdown selection
   (`Constants.PREF_UPDATE_CHANNEL`, a `SharedPreferences` key, default
   `"beta"`), resolving to `release` or `beta` — i.e. which **branch** of
   this repo it fetches the manifest from.
4. Any compatible, newer build in that channel's manifest gets offered for
   download + install through the standard A/B update flow.

## 3. `ota/sargo.json` schema

Unmodified upstream LineageOS Updater format (`packages/apps/Updater/README.md`) —
one static file per channel, since NeonOS only ships one device:

```json
{
  "response": [
    {
      "datetime": 1783944195,
      "filename": "neon_sargo-ota.zip",
      "id": "<sha256 of the zip>",
      "romtype": "RELEASE",
      "size": 1124006435,
      "url": "https://github.com/AnRomanianGuy/NeonOS/releases/download/...",
      "version": "0.1"
    }
  ]
}
```

`version` and `romtype` intentionally do **not** use the upstream Updater's
usual sources (`ro.lineage.build.version`, which stays a constant `22.2` for
every NeonOS build on this branch and would be a meaningless/wrong-looking
NeonOS version number): `version` is NeonOS's own `ro.neon.version`
(`"0.1"`), and both the Updater's compatibility check
(`Utils.isCompatible`/`canInstall`, see `Constants.PROP_NEON_VERSION`) and
`publish-release.sh` were switched to match — the manifest's `version` and
the device's `ro.neon.version` are compared directly, so bumping NeonOS's
own version (e.g. to `"0.2"`) is what actually needs to happen for a release
to be considered a real version upgrade; `datetime` remains the deciding
"is this newer" gate day-to-day between builds that share a version number.
`romtype` must match the device's `ro.lineage.releasetype` — `build-sargo.sh`
sets `RELEASE_TYPE=RELEASE` for `neon_*` targets (the build system has no
literal "OFFICIAL" value; `RELEASE` is LineageOS's own term for what NeonOS's
release builds are), so this now reads `RELEASE` rather than the default
`UNOFFICIAL`. All three of `publish-release.sh`'s `datetime`/`version`/`romtype`
values are read straight out of the build's own `system/build.prop`, not
hardcoded, so this stays correct if either of these ever changes again.

## 4. Publishing a new build

```bash
./scripts/publish-release.sh beta out/target/product/sargo/neon_sargo-ota.zip
```

(or `release` once a build is actually meant to be promoted to the stable
channel). Requires the `gh` CLI, authenticated once with push access to this
repo (`gh auth login`). The script creates a GitHub Release tagged
`sargo-<channel>-<datetime>` with the zip attached, then updates that
channel branch's `ota/sargo.json` via a throwaway `git worktree` (never
touches whatever's checked out in the main working copy) and pushes it.

## 5. Security patches

Same channel mechanism: after a monthly ASB lands in `lineage-22.2` and a
fresh build is produced, publish it the same way — no separate
infrastructure needed.

## 6. What's deliberately NOT part of this

- **Signing keys** stay private/local-only forever (permanent project rule) —
  only the OTA zip and the manifest are public. The zip's own payload
  signature (from NeonOS's own release keys, already generated in M1) is
  what `update_engine` actually verifies on-device; the manifest is
  discovery/metadata only.
- **No per-device/per-release-type server-side routing beyond the channel
  itself** — `updater_server_url` only has the one custom `{channel}` token;
  the app's other optional placeholders (`{device}`/`{type}`/`{incr}`) go
  unused since NeonOS ships one device from one static file per channel.
  Revisit if a second device is ever added.
