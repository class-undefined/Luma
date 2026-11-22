#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || -z "${RUNNER_TEMP:-}" || -z "${GITHUB_ENV:-}" ]]; then
    printf 'This script is intended for GitHub-hosted workflow jobs.\n' >&2
    exit 2
fi
if [[ -z "${MACOS_CERTIFICATE_P12:-}" ]]; then
    if [[ -n "${MACOS_CERTIFICATE_PASSWORD:-}${MACOS_SIGNING_IDENTITY:-}${APPLE_ID:-}${APPLE_APP_PASSWORD:-}${APPLE_TEAM_ID:-}" ]]; then
        printf 'Signing configuration is incomplete: MACOS_CERTIFICATE_P12 is missing.\n' >&2
        exit 2
    fi
    printf 'CODESIGN_IDENTITY=-\n' >> "$GITHUB_ENV"
    printf 'No Developer ID certificate configured; building with ad hoc signing.\n'
    exit 0
fi
: "${MACOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${MACOS_SIGNING_IDENTITY:?Missing Developer ID Application identity}"
if [[ "$MACOS_SIGNING_IDENTITY" == *$'\n'* ]]; then
    printf 'Signing identity must be a single line.\n' >&2
    exit 2
fi
certificate_path="$RUNNER_TEMP/luma-signing.p12"
keychain_path="$RUNNER_TEMP/luma-signing.keychain-db"
keychain_password="$(openssl rand -base64 32)"
printf '::add-mask::%s\n' "$keychain_password"
printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$certificate_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" -k "$keychain_path" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
rm -f "$certificate_path"
printf 'CODESIGN_IDENTITY=%s\n' "$MACOS_SIGNING_IDENTITY" >> "$GITHUB_ENV"
if [[ -n "${APPLE_ID:-}${APPLE_APP_PASSWORD:-}${APPLE_TEAM_ID:-}" ]]; then
    : "${APPLE_ID:?Missing Apple ID for notarization}"
    : "${APPLE_APP_PASSWORD:?Missing app-specific Apple password}"
    : "${APPLE_TEAM_ID:?Missing Apple Developer team ID}"
    xcrun notarytool store-credentials luma-ci --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --keychain "$keychain_path"
    printf 'NOTARYTOOL_PROFILE=luma-ci\nNOTARYTOOL_KEYCHAIN=%s\n' "$keychain_path" >> "$GITHUB_ENV"
fi
