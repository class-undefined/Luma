#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/release-common.sh"
if [[ $# -lt 1 || $# -gt 3 ]]; then
    printf 'Usage: %s <image.dmg> [expected-version] [universal|arm64|x86_64]\n' "$0" >&2
    exit 2
fi
image="$(cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")"
hdiutil verify -quiet "$image"
mount_dir="$(mktemp -d "${TMPDIR:-/tmp}/luma-dmg-verify.XXXXXX")"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then hdiutil detach -quiet "$mount_dir" || hdiutil detach -quiet -force "$mount_dir"; fi
    rmdir "$mount_dir" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$mount_dir" "$image"
mounted=true
app="$mount_dir/Luma.app"
[[ -x "$app/Contents/MacOS/Luma" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" ]]
[[ -d "$app/Contents/Resources/Luma_Luma.bundle" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == app.luma.viewer ]]
[[ -L "$mount_dir/Applications" && "$(readlink "$mount_dir/Applications")" == /Applications ]]
codesign --verify --strict --deep "$app"
if [[ -n "${2:-}" ]]; then
    expected="$(luma_bundle_version "$2")"
    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
    [[ "$actual" == "$expected" ]] || { printf 'Version mismatch: %s != %s\n' "$actual" "$expected" >&2; exit 1; }
fi
architectures=" $(lipo -archs "$app/Contents/MacOS/Luma") "
case "${3:-}" in
    universal) [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] ;;
    arm64|x86_64) [[ "$architectures" == " $3 " ]] ;;
    '') ;;
    *) printf 'Unknown architecture: %s\n' "$3" >&2; exit 2 ;;
esac
printf 'Verified DMG: %s\n' "$image"
