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
remaining module calls, runs fixture-backed smoke tests (including each
extension attribute against a stand-in `defaults` command) and checks for unsafe
eval, assignments to Zsh's reserved status parameter, a predictable legacy
marker path, and plain sudo calls.

tests/module_smoke.zsh runs each `test_*` function as a separate case in its
own subshell, so stubs and settings never carry over between cases. Each case
gets its own folder in a private temporary directory. A failed assertion is
counted and the run continues, so every case reports; the script exits 1 if
any assertion failed, a case stopped early or a case reached an unstubbed
system command (dscl, dseditgroup, launchctl, curl, kill and others are
tripwires). Run selected cases with `zsh tests/module_smoke.zsh <name> ...`
(the function name without `test_`). tests/entrypoint_smoke.zsh sources
ReEnroll.sh without running main and counts failures the same way. Neither
script changes accounts, groups, launchd jobs or Jamf state. The only real
system query is a read-only OpenDirectory lookup of an account that does not
exist. No real account's password is checked, because a failed check counts
as a failed login for that account.

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

At the login window, confirm that an unattended policy (`$8` `false`) logs
"continuing unattended" and runs to completion, and that a dialog policy
(`$8` `true`) exits after about 20 seconds. For account cleanup, use
disposable accounts: a targeted administrator must be kept, a targeted
standard account deleted with its home folder, and a targeted account whose
home is a symlink or outside `/Users` deleted with the folder left in place.
Set `$6` to the console user's name once and confirm the run refuses to
demote or delete it. Check that Device ReEnroll Status reads `Enrolled Device`
only after a run that redeployed, enrolled or verified the Mac.

For the profiles-renew flow, also stop a run with SIGKILL after it promotes
a non-admin test user, and separately restart the Mac at that point. Confirm
the admin guard demotes the user within a minute (or at boot), logs
`[ADMIN GUARD]` lines, and removes its LaunchDaemon. Confirm the
`ReEnrollPromoted*` keys are cleared from ReEnroll.plist.

Logs are in /Library/Application Support/ReEnroll/ReEnroll.log; configuration
state is in the sibling ReEnroll.plist. Redact secrets and identifying data
before sharing logs. Record source revision, artifact, non-secret parameters,
macOS version and observed result.
