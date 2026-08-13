#!/bin/zsh --no-rcs

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "${repo_root}"

for file in ReEnroll.sh lib/*.zsh; do
    zsh -n "${file}"
done

python3 scripts/build_jamf_artifact.py
zsh -n dist/ReEnroll-jamf.zsh
git diff --exit-code -- dist/ReEnroll-jamf.zsh
if grep -q 'sourceModule "' dist/ReEnroll-jamf.zsh; then
    echo "Standalone Jamf artifact still references external modules." >&2
    exit 1
fi

zsh tests/module_smoke.zsh

if grep -R -n 'eval[[:space:]]' lib ReEnroll.sh; then
    echo "Unsafe eval invocation found." >&2
    exit 1
fi

echo "All checks passed."
