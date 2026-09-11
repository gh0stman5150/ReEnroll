---
title: ReEnroll Testing
description: Local checks, dry-run limits and managed endpoint validation.
---

## Repository checks

From the repository root on macOS with Python 3 and Zsh installed:

```zsh
zsh scripts/check.sh
```

The harness syntax-checks the entry point and modules, verifies interpreter
headers, checks Bash extension attributes, rebuilds and syntax-checks the
standalone artifact, and compares it against tracked output. It rejects
remaining module calls, runs fixture-backed smoke tests and checks for unsafe
eval, assignments to Zsh's reserved status parameter, a predictable legacy
marker path, and plain sudo calls.

When source changes intentionally alter generated output, first run
python3 scripts/build_jamf_artifact.py and inspect the artifact diff.
The harness's git diff --exit-code fails while generated changes remain
unstaged against the index. Include intended artifact changes with source;
do not discard them merely to pass this check. CI checks committed output.

## Dry run

On a disposable managed test Mac with normal runtime prerequisites:

```zsh
DRY_RUN=1 zsh ./ReEnroll.sh
```

DRY_RUN=true is also accepted. Guarded API mutations, account changes,
launchd creation, enrollment prompts and webhook delivery are simulated.
This is not an isolated offline sandbox: startup still reads macOS/Jamf
state and can create temporary files and logs. Prefer repository checks for
routine development. Dry runs do not prove live enrollment succeeds.

## Endpoint validation

Test the generated artifact in unattended and Self Service policies. Cover
missing GUI sessions, missing Jamf binary, credential-reader errors, API
failure/fallback, enrollment validation and recovery. Review account targets
and exemptions before any live cleanup.

Logs are in /Library/Application Support/ReEnroll/ReEnroll.log; configuration
state is in the sibling ReEnroll.plist. Redact secrets and identifying data
before sharing logs. Record source revision, artifact, non-secret parameters,
macOS version and observed result.
