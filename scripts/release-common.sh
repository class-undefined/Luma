#!/bin/bash
# Shared by local packaging and GitHub Actions. Compatible with macOS Bash 3.2.

luma_normalize_version() {
    local value="${1#v}"
    local number='(0|[1-9][0-9]*)'
    local identifier='[0-9A-Za-z-]+'
    local pattern="^${number}\\.${number}\\.${number}(-${identifier}(\\.${identifier})*)?(\\+${identifier}(\\.${identifier})*)?$"
    if [[ ! "$value" =~ $pattern ]]; then
        printf 'Invalid version: %s (expected 1.2.3 or 1.2.3-rc.1)\n' "$1" >&2
        return 2
    fi
    printf '%s\n' "$value"
}

luma_source_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Packaging/Info.plist"
}

luma_bundle_version() {
    local value
    value="$(luma_normalize_version "$1")" || return
    printf '%s\n' "${value%%[-+]*}"
}
