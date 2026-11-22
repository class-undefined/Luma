#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/release-common.sh"
version="${LUMA_VERSION:-$(luma_source_version "$repo_dir")}"
output_dir="${LUMA_OUTPUT_DIR:-$repo_dir/build}"
architecture=universal
skip_build=false
usage() {
    printf 'Usage: %s [--version VERSION] [--native] [--skip-build] [--output-dir DIRECTORY]\n' "$0"
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|--output-dir)
            if [[ $# -lt 2 || -z "$2" ]]; then usage >&2; exit 2; fi
            if [[ "$1" == --version ]]; then version="$2"; else output_dir="$2"; fi
            shift 2 ;;
        --native) architecture="$(uname -m)"; shift ;;
        --skip-build) skip_build=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done
version="$(luma_normalize_version "$version")"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app="$output_dir/Luma.app"
identity="${CODESIGN_IDENTITY:--}"
if [[ -n "${NOTARYTOOL_PROFILE:-}" && "$identity" == "-" ]]; then
    printf 'Notarization requires a Developer ID CODESIGN_IDENTITY.\n' >&2
    exit 2
fi
if [[ "$skip_build" == false ]]; then
    build_args=(release)
    if [[ "$architecture" == universal ]]; then build_args+=(--universal); fi
    LUMA_VERSION="$version" LUMA_OUTPUT_DIR="$output_dir" "$repo_dir/scripts/build.sh" "${build_args[@]}"
fi
[[ -d "$app" ]] || { printf 'Missing app: %s\n' "$app" >&2; exit 1; }
actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[[ "$actual" == "$(luma_bundle_version "$version")" ]] || { printf 'App version does not match %s. Rebuild the app.\n' "$version" >&2; exit 1; }
codesign --verify --strict --deep "$app"
staging_dir="$(mktemp -d "$output_dir/.luma-dmg.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
notary_args=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    notary_args=(--keychain-profile "$NOTARYTOOL_PROFILE" --wait)
    if [[ -n "${NOTARYTOOL_KEYCHAIN:-}" ]]; then notary_args+=(--keychain "$NOTARYTOOL_KEYCHAIN"); fi
    ditto -c -k --keepParent "$app" "$staging_dir/Luma-notarization.zip"
    xcrun notarytool submit "$staging_dir/Luma-notarization.zip" "${notary_args[@]}"
    xcrun stapler staple "$app"
fi
mkdir "$staging_dir/image"
ditto "$app" "$staging_dir/image/Luma.app"
ln -s /Applications "$staging_dir/image/Applications"
printf '将 Luma.app 拖入 Applications 文件夹完成安装。\nRequires macOS 14 or later.\n' > "$staging_dir/image/安装说明.txt"
image_name="Luma-$version-$architecture.dmg"
hdiutil create -quiet -volname "Luma $version" -srcfolder "$staging_dir/image" -fs HFS+ -format UDZO "$staging_dir/$image_name"
if [[ "$identity" != "-" ]]; then codesign --force --sign "$identity" --timestamp "$staging_dir/$image_name"; fi
if [[ ${#notary_args[@]} -gt 0 ]]; then
    xcrun notarytool submit "$staging_dir/$image_name" "${notary_args[@]}"
    xcrun stapler staple "$staging_dir/$image_name"
fi
"$repo_dir/scripts/verify-dmg.sh" "$staging_dir/$image_name" "$version" "$architecture"
mv -f "$staging_dir/$image_name" "$output_dir/$image_name"
(cd "$output_dir" && shasum -a 256 "$image_name" > "$image_name.sha256")
printf '\nDMG: %s\nSHA256: %s\n' "$output_dir/$image_name" "$output_dir/$image_name.sha256"
