#!/bin/bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app_dir="$repo_dir/build/Luma.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Luma" "$app_dir/Contents/MacOS/Luma"
chmod +x "$app_dir/Contents/MacOS/Luma"
cp "$repo_dir/Packaging/Info.plist" "$app_dir/Contents/Info.plist"
cp "$repo_dir/Packaging/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
ditto "$bin_dir/Luma_Luma.bundle" "$app_dir/Contents/Resources/Luma_Luma.bundle"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
codesign --verify --strict --deep "$app_dir"
printf '\nBuilt %s\n' "$app_dir"
