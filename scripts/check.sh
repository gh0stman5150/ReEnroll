#!/bin/zsh --no-rcs

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "${repo_root}"

for file in ReEnroll.sh lib/*.zsh; do
    zsh -n "${file}"
done

if [[ "$(head -n 1 ReEnroll.sh)" != '#!/bin/zsh --no-rcs' ]]; then
    echo "ReEnroll Jamf source must use /bin/zsh --no-rcs." >&2
    exit 1
fi

for file in "Extras/Extension Attributes"/*(N.); do
    if [[ "$(head -n 1 "${file}")" != '#!/bin/bash' ]]; then
        echo "Jamf Extension Attribute must use /bin/bash: ${file}" >&2
        exit 1
    fi
    /bin/bash -n "${file}"
done

python3 scripts/build_jamf_artifact.py
zsh -n dist/ReEnroll-jamf.zsh
if [[ "$(head -n 1 dist/ReEnroll-jamf.zsh)" != '#!/bin/zsh --no-rcs' ]]; then
    echo "Standalone Jamf artifact must use /bin/zsh --no-rcs." >&2
    exit 1
fi
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

if grep -R -nE \
    -e '^[[:space:]]*(local|typeset)([[:space:]]+-[[:alnum:]]+)*[[:space:]]+([^#[:space:]]+[[:space:]]+)*status([=[:space:]]|$)' \
    -e '^[[:space:]]*status[[:space:]]*=' \
    lib ReEnroll.sh; then
    echo "Assignment to zsh's read-only status parameter found." >&2
    exit 1
fi

if grep -R -n '/var/tmp/jamfTempMarker.txt' lib ReEnroll.sh; then
    echo "Predictable Jamf log marker path found." >&2
    exit 1
fi

if grep -R -nE '(^|[[:space:]])sudo([[:space:]]|$)' lib ReEnroll.sh; then
    echo "Plain sudo invocation found in root-run Jamf code." >&2
    exit 1
fi

echo "All checks passed."
