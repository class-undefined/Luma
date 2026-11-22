#!/bin/bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/release-common.sh"
cd "$repo_dir"
configuration="${1:-release}"
case "$configuration" in
    debug|release) ;;
    *) printf 'Usage: %s [debug|release] [--universal]\n' "$0" >&2; exit 2 ;;
esac
build_args=(-c "$configuration")
if [[ "${2:-}" == "--universal" ]]; then
    build_args+=(--arch arm64 --arch x86_64)
elif [[ -n "${2:-}" ]]; then
    printf 'Unknown option: %s\n' "$2" >&2
    exit 2
fi
if [[ $# -gt 2 ]]; then printf 'Too many arguments.\n' >&2; exit 2; fi
version="$(luma_normalize_version "${LUMA_VERSION:-$(luma_source_version "$repo_dir")}")"
bundle_version="$(luma_bundle_version "$version")"
build_number="${LUMA_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)}"
if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    printf 'Invalid build number: %s\n' "$build_number" >&2
    exit 2
fi
output_dir="${LUMA_OUTPUT_DIR:-$repo_dir/build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app_dir="$output_dir/Luma.app"
staging_dir="$(mktemp -d "$output_dir/.luma-build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
staged_app="$staging_dir/Luma.app"

swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$bin_dir/Luma" "$staged_app/Contents/MacOS/Luma"
chmod +x "$staged_app/Contents/MacOS/Luma"
cp "$repo_dir/Packaging/Info.plist" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $bundle_version" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staged_app/Contents/Info.plist"
cp "$repo_dir/Packaging/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
ditto "$bin_dir/Luma_Luma.bundle" "$staged_app/Contents/Resources/Luma_Luma.bundle"
plutil -lint "$staged_app/Contents/Info.plist"
identity="${CODESIGN_IDENTITY:--}"
signing_args=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then signing_args+=(--options runtime --timestamp); fi
codesign "${signing_args[@]}" "$staged_app"
codesign --verify --strict --deep "$staged_app"
# Move whole bundles so rebuilding never truncates an executable that is running.
if [[ -e "$app_dir" ]]; then mv "$app_dir" "$staging_dir/previous.app"; fi
if ! mv "$staged_app" "$app_dir"; then
    if [[ -e "$staging_dir/previous.app" ]]; then mv "$staging_dir/previous.app" "$app_dir"; fi
    exit 1
fi
printf '\nBuilt %s (%s, build %s)\n' "$app_dir" "$version" "$build_number"
