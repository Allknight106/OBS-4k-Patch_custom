#!/usr/bin/env bash
# Checks mainline OBS against this repo's 4K virtual camera patch.
#
#   scripts/check-upstream.sh [VERSION]
#
# VERSION defaults to the latest OBS release. Prints a Markdown report and,
# when run in GitHub Actions, writes these step outputs:
#   latest, tracked, new_release, patch_ok, renames_ok, upstream_fixed, needs_attention
# Works on macOS and Linux (needs curl, tar, patch, python3).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API="https://api.github.com/repos/obsproject/obs-studio"
RAW="https://raw.githubusercontent.com/obsproject/obs-studio"
CAM_DIR="plugins/mac-virtualcam/src/camera-extension"

json() { python3 -I -c "import json,sys; d=json.load(sys.stdin); print(d$1)"; }
curl_gh() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    curl -fsSL -H "Authorization: Bearer $GH_TOKEN" "$@"
  else
    curl -fsSL "$@"
  fi
}

tracked="$(tr -d '[:space:]' < "$REPO_DIR/OBS_VERSION")"
latest="${1:-$(curl_gh "$API/releases/latest" | json "['tag_name']")}"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/obs4k-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# 1. Download that release's source and test the patch and renames against it.
curl -fsSL -o "$tmp/src.tar.gz" \
  "https://github.com/obsproject/obs-studio/releases/download/$latest/OBS-Studio-$latest-Sources.tar.gz"
tar -xzf "$tmp/src.tar.gz" -C "$tmp"
src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"

patch_ok=true
patch_report=""
for p in "$REPO_DIR"/patches/*.patch; do
  name="$(basename "$p")"
  if (cd "$src" && patch -p1 --dry-run -f -s < "$p" > /dev/null 2>&1); then
    patch_report+="- \`$name\`: applies cleanly"$'\n'
    (cd "$src" && patch -p1 -f -s < "$p" > /dev/null)
  elif (cd "$src" && patch -p1 -R --dry-run -f -s < "$p" > /dev/null 2>&1); then
    patch_report+="- \`$name\`: **already included in OBS $latest**"$'\n'
  else
    patch_ok=false
    patch_report+="- \`$name\`: **does not apply**. The patched code changed upstream and the patch needs updating."$'\n'
  fi
done

if rename_out="$(python3 -I "$REPO_DIR/scripts/apply-renames.py" "$REPO_DIR/renames.txt" "$src" --check 2>&1)"; then
  renames_ok=true
else
  renames_ok=false
fi

# 2. Has mainline OBS fixed the 1080p limit itself? Stock OBS hard-codes one
#    format with `return [_streamFormat]`; if that line is gone, upstream changed it.
master_src="$(curl -fsSL "$RAW/master/$CAM_DIR/OBSCameraStreamSource.swift" || true)"
if [[ -n "$master_src" ]] && ! grep -qF 'return [_streamFormat]' <<< "$master_src"; then
  upstream_fixed=true
else
  upstream_fixed=false
fi
issue_state="$(curl_gh "$API/issues/13559" | json "['state']" || echo unknown)"

new_release=false
[[ "$latest" != "$tracked" ]] && new_release=true
needs_attention=false
if $new_release || ! $patch_ok || ! $renames_ok || $upstream_fixed; then
  needs_attention=true
fi

yesno() { $1 && echo "$2" || echo "$3"; }

cat <<EOF
## OBS 4K patch check

| | |
|---|---|
| Latest OBS release | **$latest** |
| Last version built with this repo | $tracked |
| New release since then | $(yesno $new_release "**yes, rebuild OBS Studio 4K**" no) |
| Patches apply to $latest | $(yesno $patch_ok yes "**no**") |
| ID renames still match | $(yesno $renames_ok yes "**no**") |
| Mainline OBS changed the camera format code | $(yesno $upstream_fixed "**yes, check whether stock OBS now does 4K**" no) |
| Upstream issue #13559 | $issue_state |

### Patches
$patch_report
EOF
if ! $renames_ok; then
  printf '### Renames\n```\n%s\n```\n' "$rename_out"
fi
if $new_release && $patch_ok && $renames_ok; then
  printf '\n### Next step\nOn the Mac, after updating stock OBS: `./obs4k.sh update %s`\n' "$latest"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "latest=$latest"
    echo "tracked=$tracked"
    echo "new_release=$new_release"
    echo "patch_ok=$patch_ok"
    echo "renames_ok=$renames_ok"
    echo "upstream_fixed=$upstream_fixed"
    echo "needs_attention=$needs_attention"
  } >> "$GITHUB_OUTPUT"
fi
