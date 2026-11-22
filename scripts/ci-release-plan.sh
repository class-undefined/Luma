#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/release-common.sh"
cd "$repo_dir"
: "${GITHUB_OUTPUT:?This script must run in a GitHub Actions metadata step}"
: "${GITHUB_EVENT_NAME:?Missing event name}"
: "${GITHUB_REF_TYPE:?Missing ref type}"
: "${GITHUB_REF_NAME:?Missing ref name}"

publish=false
mode=build
if [[ "$GITHUB_REF_TYPE" == tag ]]; then
    version="$(luma_normalize_version "$GITHUB_REF_NAME")"
    tag="$GITHUB_REF_NAME"
else
    version="$(luma_normalize_version "${INPUT_VERSION:-$(luma_source_version "$repo_dir")}")"
    tag="v$version"
fi
case "$GITHUB_EVENT_NAME" in
    push)
        if [[ "$GITHUB_REF_TYPE" == tag ]]; then publish=true; mode=tag
        elif [[ "${GITHUB_REF:-}" == refs/heads/main ]]; then publish=true; mode=version
        fi ;;
    release) publish=true; mode=tag ;;
    workflow_dispatch)
        if [[ "${INPUT_PUBLISH:-true}" == true ]]; then publish=true; mode=version; fi ;;
esac

# A version published from main is immutable; documentation pushes only rebuild it.
# If a tag exists without a Release, recover by rebuilding that exact tagged commit.
if [[ "$mode" == version ]]; then
    : "${GH_REPO:?Missing repository}"
    error_file="$(mktemp "${TMPDIR:-/tmp}/luma-release-check.XXXXXX")"
    trap 'rm -f "$error_file"' EXIT
    recover_tag=false
    if assets="$(gh release view "$tag" --repo "$GH_REPO" --json assets,isDraft --jq 'if .isDraft then "__draft__" else .assets[].name end' 2>"$error_file")"; then
        image="Luma-$version-universal.dmg"
        if [[ "$assets" == __draft__ ]] || { printf '%s\n' "$assets" | /usr/bin/grep -Fxq "$image" && printf '%s\n' "$assets" | /usr/bin/grep -Fxq "$image.sha256"; }; then
            publish=false
            printf 'Version %s already has a complete Release or a user-managed draft; leaving it unchanged.\n' "$version"
        else
            recover_tag=true
            printf 'Version %s is missing release assets; rebuilding its tagged source.\n' "$version"
        fi
    elif /usr/bin/grep -Eiq 'release not found|HTTP 404|Not Found' "$error_file"; then
        recover_tag=true
    else
        cat "$error_file" >&2
        exit 1
    fi
    if [[ "$recover_tag" == true ]] && git show-ref --verify --quiet "refs/tags/$tag"; then
        git checkout --detach "refs/tags/$tag"
    fi
fi
source_sha="$(git rev-parse HEAD)"
printf 'version=%s\nartifact=Luma-%s-macOS-universal\nrelease_tag=%s\nsource_sha=%s\npublish=%s\n' \
    "$version" "$version" "$tag" "$source_sha" "$publish" >> "$GITHUB_OUTPUT"
printf 'Package version: %s; Release tag: %s; publish: %s; commit: %s\n' "$version" "$tag" "$publish" "$source_sha"
