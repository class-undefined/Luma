#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$repo_dir/scripts/build.sh" debug
open -n "$repo_dir/build/Luma.app" --args "$@"
