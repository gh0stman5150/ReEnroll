#!/bin/zsh --no-rcs

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "${repo_root}"

for file in ReEnroll.sh lib/*.zsh; do
    zsh -n "${file}"
done

zsh tests/module_smoke.zsh

echo "All checks passed."
