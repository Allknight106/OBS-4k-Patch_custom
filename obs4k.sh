#!/bin/zsh
# obs4k.sh: build, update and check "OBS Studio 4K", a copy of OBS Studio whose
# macOS virtual camera offers 4K (see README.md).
#
#   ./obs4k.sh check                  Compare your installed apps with the latest OBS release,
#                                     and test whether the 4K patch still applies to it.
#   ./obs4k.sh update [VERSION]       Download OBS VERSION (default: latest release), patch it,
#                                     build, sign and install it. Quit OBS Studio 4K first.
#   ./obs4k.sh prepare [VERSION]      Only download and patch the source (no build).
#   ./obs4k.sh install [VERSION]      Install an already built VERSION.
#
# Options (after the command):
#   --team TEAMID       Apple Developer Team ID. Found automatically when Xcode is signed in
#                       to exactly one paid team. Or set OBS4K_TEAM.
#   --no-install        Build only.
#
# Environment overrides:
#   OBS4K_WORK_DIR      Where sources and builds go (default: ./work next to this script).
#   OBS4K_PREFIX        Bundle ID prefix (default com.obs4k.obs-studio). Must be unique to your
#                       Apple team; change it if someone else already registered it.

set -euo pipefail

REPO_DIR=${0:A:h}
WORK_DIR=${OBS4K_WORK_DIR:-$REPO_DIR/work}
PREFIX=${OBS4K_PREFIX:-com.obs4k.obs-studio}
APP_NAME="OBS Studio 4K"
CAMERA_NAME="OBS Virtual Camera 4K"
APP_DEST="/Applications/$APP_NAME.app"
STOCK_APP="/Applications/OBS.app"
CONFIG=RelWithDebInfo
SETTINGS_DIR="$HOME/Library/Application Support/obs-studio"

# Keep these fixed: macOS and apps like Riverside identify the virtual camera by
# them, so changing them makes the camera show up as a new device.
DEVICE_UUID=${OBS4K_DEVICE_UUID:-F0A3376C-FD8C-4FF2-B554-F100BA6DAABC}
SOURCE_UUID=${OBS4K_SOURCE_UUID:-5B6B42E6-2553-4C21-8F8C-9EE8604C5E31}
SINK_UUID=${OBS4K_SINK_UUID:-9B43A152-AE31-461B-9DE6-91063BF08906}

say() { print -P "%B==>%b $*"; }
die() { print -u2 -P "%F{red}error:%f $*"; exit 1; }

app_version() {
  [[ -d "$1" ]] && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || echo "not installed"
}

latest_release() {
  curl -fsSL https://api.github.com/repos/obsproject/obs-studio/releases/latest |
    python3 -I -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
}

detect_team() {
  defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -I -c '
import plistlib, sys
try:
    d = plistlib.loads(sys.stdin.buffer.read())
except Exception:
    sys.exit()
teams = {t["teamID"] for lst in d.get("IDEProvisioningTeamByIdentifier", {}).values()
         for t in lst if not t.get("isFreeProvisioningTeam")}
print(" ".join(sorted(teams)))'
}

src_dir_for() { print -r -- "$WORK_DIR/obs-studio-$1-sources"; }
built_app_for() { print -r -- "$(src_dir_for "$1")/build_macos/frontend/$CONFIG/OBS.app"; }

cmd_check() {
  "$REPO_DIR/scripts/check-upstream.sh" "$@"
  local stock=$(app_version "$STOCK_APP") mine=$(app_version "$APP_DEST")
  print
  print -r -- "## This Mac"
  print -r -- "- Stock OBS: $stock"
  print -r -- "- $APP_NAME: $mine"
  if [[ "$stock" != "not installed" && "$mine" != "not installed" && "$stock" != "$mine" ]]; then
    print -r -- "- **Versions differ.** Both apps share one settings folder, so rebuild with: ./obs4k.sh update $stock"
  fi
}

cmd_prepare() {
  local version=$1 src tarball
  src=$(src_dir_for "$version")
  tarball="$WORK_DIR/OBS-Studio-$version-Sources.tar.gz"
  mkdir -p "$WORK_DIR"

  if [[ ! -f "$tarball" ]]; then
    say "Downloading OBS $version source"
    curl -fL --progress-bar -o "$tarball.part" \
      "https://github.com/obsproject/obs-studio/releases/download/$version/OBS-Studio-$version-Sources.tar.gz"
    mv "$tarball.part" "$tarball"
  fi

  say "Unpacking a fresh copy to $src"
  rm -rf "$src"
  local top=$(tar -tzf "$tarball" | head -1 | cut -d/ -f1)
  tar -xzf "$tarball" -C "$WORK_DIR"
  [[ "$WORK_DIR/$top" == "$src" ]] || mv "$WORK_DIR/$top" "$src"

  say "Applying patches"
  local p
  for p in "$REPO_DIR"/patches/*.patch; do
    if (cd "$src" && patch -p1 --dry-run -f -s < "$p" >/dev/null 2>&1); then
      (cd "$src" && patch -p1 -f -s < "$p")
      print "  applied ${p:t}"
    elif (cd "$src" && patch -p1 -R --dry-run -f -s < "$p" >/dev/null 2>&1); then
      print "  ${p:t} is already part of OBS $version, skipped"
    else
      die "${p:t} does not apply to OBS $version. The patch needs updating for this version."
    fi
  done

  say "Giving the build its own app and camera IDs"
  python3 -I "$REPO_DIR/scripts/apply-renames.py" "$REPO_DIR/renames.txt" "$src" \
    --prefix "$PREFIX" --app-name "$APP_NAME" --camera-name "$CAMERA_NAME"

  grep -q '"name": "macos"' "$src/CMakePresets.json" || die "OBS $version no longer has a 'macos' CMake preset."
  cat > "$src/CMakeUserPresets.json" <<EOF
{
  "version": 8,
  "configurePresets": [
    {
      "name": "macos-4k",
      "displayName": "macOS, 4K virtual camera",
      "inherits": ["macos"],
      "binaryDir": "\${sourceDir}/build_macos",
      "cacheVariables": {
        "VIRTUALCAM_DEVICE_UUID": {"type": "STRING", "value": "$DEVICE_UUID"},
        "VIRTUALCAM_SOURCE_UUID": {"type": "STRING", "value": "$SOURCE_UUID"},
        "VIRTUALCAM_SINK_UUID": {"type": "STRING", "value": "$SINK_UUID"},
        "OBS_VERSION_OVERRIDE": {"type": "STRING", "value": "$version"},
        "SPARKLE_APPCAST_URL": {"type": "STRING", "value": ""},
        "SPARKLE_PUBLIC_KEY": {"type": "STRING", "value": ""}
      }
    }
  ]
}
EOF
  say "Source ready: $src"
}

cmd_build() {
  local version=$1 team=$2 src
  src=$(src_dir_for "$version")
  [[ -f "$src/CMakeUserPresets.json" ]] || die "Run ./obs4k.sh prepare $version first."
  cd "$src"
  say "Configuring (team $team)"
  CODESIGN_TEAM="$team" cmake --preset macos-4k
  say "Building. The first build of a new version takes 20-40 minutes"
  cmake --build build_macos --config "$CONFIG" -- -allowProvisioningUpdates -allowProvisioningDeviceRegistration

  local app=$(built_app_for "$version")
  local ext="$app/Contents/Library/SystemExtensions/$PREFIX.mac-camera-extension.systemextension"
  [[ -d "$ext" ]] || die "The camera extension is missing from the built app (signing problem?)."
  codesign --verify --deep --strict "$app" || die "The built app's signature doesn't verify."
  say "Built and signed: $app"
}

cmd_install() {
  local version=$1 app staging backup
  app=$(built_app_for "$version")
  [[ -d "$app" ]] || die "No build for OBS $version. Run ./obs4k.sh update $version"
  if pgrep -qf "$APP_DEST/Contents/MacOS/OBS"; then
    die "Quit $APP_NAME first, then run: ./obs4k.sh install $version"
  fi

  if [[ -d "$SETTINGS_DIR" ]]; then
    backup="$WORK_DIR/settings-backups/obs-studio-$(date +%Y%m%d-%H%M%S)"
    say "Backing up your OBS settings to $backup"
    mkdir -p "${backup:h}"
    ditto "$SETTINGS_DIR" "$backup"
  fi

  # Copy to a staging name first so the app is never half-installed.
  staging="/Applications/.$APP_NAME-installing.app"
  rm -rf "$staging"
  ditto "$app" "$staging"
  codesign --verify --deep --strict "$staging" || { rm -rf "$staging"; die "Copied app failed verification."; }
  rm -rf "$APP_DEST"
  mv "$staging" "$APP_DEST"
  print -r -- "$version" > "$REPO_DIR/OBS_VERSION"
  say "Installed $APP_NAME $version"
  print "  Open it, click Start Virtual Camera, and pick \"$CAMERA_NAME\" in your app."
  print "  OBS_VERSION now says $version; commit and push it so the weekly check stays quiet."
}

# ---- argument parsing ----
command=${1:-}
[[ -n "$command" ]] && shift
version="" team=${OBS4K_TEAM:-} install=true
while (( $# )); do
  case $1 in
    --team) team=${2:?--team needs a value}; shift 2 ;;
    --no-install) install=false; shift ;;
    -*) die "unknown option $1" ;;
    *) version=$1; shift ;;
  esac
done

case $command in
  check) cmd_check ${version:+$version} ;;
  prepare|update|install)
    [[ -n "$version" ]] || version=$(latest_release)
    case $command in
      prepare) cmd_prepare "$version" ;;
      install) cmd_install "$version" ;;
      update)
        if [[ -z "$team" ]]; then
          teams=($(detect_team))
          (( ${#teams} == 1 )) || die "Couldn't pick an Apple team automatically (found: ${teams:-none}). Use --team TEAMID."
          team=$teams[1]
        fi
        stock=$(app_version "$STOCK_APP")
        if [[ "$stock" != "not installed" && "$stock" != "$version" ]]; then
          print -P "%F{yellow}note:%f stock OBS is $stock but you're building $version. Both share one settings folder, so keeping them on the same version is safest."
        fi
        cmd_prepare "$version"
        cmd_build "$version" "$team"
        $install && cmd_install "$version"
        ;;
    esac
    ;;
  *) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
