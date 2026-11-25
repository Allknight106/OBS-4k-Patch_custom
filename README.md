# OBS 4K Virtual Camera patch (macOS)

On macOS, OBS Studio's virtual camera tells apps its largest size is **1920x1080**, even when your OBS canvas is 4K. Apps that pick a camera format, such as Riverside, Chrome/WebRTC tools and video-call apps, then use 1080p. This is [obsproject/obs-studio#13559](https://github.com/obsproject/obs-studio/issues/13559).

This repo builds **OBS Studio 4K**, a copy of OBS whose virtual camera ("**OBS Virtual Camera 4K**") offers 3840x2160, 2560x1440, 1920x1080 and 1280x720. It installs next to stock OBS, so you can keep stock OBS for everything else and let it update normally.

> Unofficial and not affiliated with the OBS Project. The 4K change is [this commit by cbusillo](https://github.com/cbusillo/obs-studio/commit/869bc81), posted on the issue above.

## What's in here

| Path | What it is |
|---|---|
| `patches/` | The 4K virtual camera patch, applied to the OBS source |
| `renames.txt` | Gives the build its own app and camera IDs (`com.obs4k.obs-studio`) so you can sign it with your own Apple team and install it beside stock OBS |
| `obs4k.sh` | Downloads an OBS release, patches it, builds, signs and installs it. Also checks for updates. |
| `scripts/check-upstream.sh` | Tests the patch against the latest OBS release and checks whether mainline OBS fixed the issue |
| `.github/workflows/check-upstream.yml` | Runs that check every Monday and opens an issue when something needs doing |
| `OBS_VERSION` | The OBS version this repo was last built with |

## Requirements

- A Mac with Xcode installed, and CMake (`brew install cmake`)
- A **paid Apple Developer account** ($99/year). macOS only loads a camera extension signed by a developer team; a free Apple ID can't sign one.
- Xcode signed in to that account: Xcode → Settings → Accounts
- Your Mac registered as a device: developer.apple.com → Certificates, IDs & Profiles → Devices → **+**. Get the UDID with `system_profiler SPHardwareDataType | grep "Provisioning UDID"`.

## Build and install

```bash
./obs4k.sh update            # latest OBS release
./obs4k.sh update 33.0.3     # a specific version
```

It finds your Team ID from Xcode (or pass `--team TEAMID`). The first build takes 20–40 minutes. Quit OBS Studio 4K before it installs; the script backs up your OBS settings to `work/settings-backups/` first.

**After the first install:**
1. Quit stock OBS, open **OBS Studio 4K**, click **Start Virtual Camera**.
2. Approve the extension: System Settings → General → Login Items & Extensions → Camera Extensions → **OBS Virtual Camera 4K**.
3. Give the new app its own permissions under System Settings → Privacy & Security: **Screen & System Audio Recording** and **Input Monitoring**. Then quit and reopen it.
4. Fully restart your browser or call app and pick **OBS Virtual Camera 4K**.

## Keeping it updated

Both apps share one settings folder (`~/Library/Application Support/obs-studio`), so:

- Run **only one at a time**.
- Keep them on the **same OBS version**. When stock OBS updates, run `./obs4k.sh update <that version>`.
- OBS Studio 4K doesn't auto-update (that's turned off so stock OBS can't replace it).
- Development signing expires after about a year. If the 4K camera stops appearing, rebuild.

Check where you stand any time:

```bash
./obs4k.sh check
```

### Weekly check on GitHub

The workflow in `.github/workflows/check-upstream.yml` runs every Monday (or on demand from the Actions tab) and opens an issue when:

- **a new OBS version is out**: update stock OBS, then run `./obs4k.sh update <version>` and commit the changed `OBS_VERSION`
- **the patch or renames no longer apply** to the new version, so they need updating before you rebuild
- **mainline OBS changed the virtual camera format code**: stock OBS may now do 4K on its own, and you may not need this build any more

GitHub pauses scheduled workflows in repos with no activity for 60 days. If that happens, re-enable it from the Actions tab.

## Uninstall

Delete `/Applications/OBS Studio 4K.app` (macOS asks to remove its camera extension). Your settings stay, since they belong to stock OBS as well.

## License

GPL-2.0, the same as OBS Studio. See `LICENSE`.
