#!/bin/bash
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
swift test
"$repo_dir/scripts/build.sh" debug
"$repo_dir/build/Luma.app/Contents/MacOS/Luma" --ui-test
cat "$repo_dir/build/validation/results.txt"
