---
title: ReEnroll Agent Guidance
description: Jamf enrollment recovery, modular builds and safety checks.
---

## Purpose and authority

Repair or renew Jamf enrollment, including framework redeployment, profile
renewal, inventory checks, LAPS and explicitly targeted account cleanup.
This file owns contributor guidance. In MacProjects, consult the
[shared workspace rules](../AGENTS.md#shared-rules).
[README.md](README.md) owns deployment parameters and credential setup;
[testing.md](docs/testing.md) explains local and managed-device checks.

The [Copilot entry point](.github/copilot-instructions.md) links here and does
not maintain a second copy of these rules.

## Layout

- ReEnroll.sh: Zsh entry point and source configuration.
- lib/: dialog, Jamf API, launchd, webhooks, LAPS and enrollment modules.
- scripts/build_jamf_artifact.py: standalone artifact generator.
- dist/ReEnroll-jamf.zsh: deployable Jamf script.
- Extras/Extension Attributes/: Bash inventory scripts.
- tests/: Zsh smoke tests and synthetic JSON fixtures.
- scripts/check.sh: syntax, artifact, smoke and safety harness.

## Jamf execution requirement

The generated ReEnroll script must run successfully through Jamf Pro as root
using #!/bin/zsh --no-rcs, without a checkout or external modules. Deploy
dist/ReEnroll-jamf.zsh, never the modular ReEnroll.sh by itself. Extension
attributes must run through Jamf using #!/bin/bash. Python builders and
developer check scripts do not need to execute as Jamf policies.

Preserve unattended execution and console-user gating for Self Service UI.
The AppleScript fallback must enter the user's bootstrap and UID context.
Do not require terminal input or add plain sudo elevation to root-run code.

## Safety and coding invariants

- Preserve dedicated signed credential-reader checks and keychain defaults.
  Parameters $4/$5 are legacy credentials gated by an explicit compatibility
  switch; do not turn them into the default authentication path.
- Preserve Jamf API version fallback and explicit API error handling.
- Review targeted_users, exempt_users, enrollment/site switches, organization
  identifiers and support placeholders before building deployment output.
- Maintain guarded dry-run behavior, unique temporary markers, token cleanup
  and launchd delegation. Dry run still reads local state and writes logs;
  it is not an offline sandbox.
- Account cleanup and LAPS rotation are real mutations. Test using fixtures
  and disposable managed Macs, not by running the entry point for usage.
- Do not use eval or assign to Zsh's reserved status parameter.
- Keep log and configuration state under the documented ReEnroll support
  directory and preserve current exit behavior.

## Build and validation

From this repository on macOS with Python 3, Zsh and actionlint:

```zsh
python3 scripts/build_jamf_artifact.py
actionlint .github/workflows/ci.yml
zsh scripts/check.sh
git diff --check
```

The harness compares generated output to the Git index, so intended unstaged
artifact changes fail its drift check. Inspect and include generated output
with source changes; do not discard intended changes just to pass the harness.
Add smoke/fixture coverage for changed parsing and module behavior. Update
README and testing documentation with parameter or operational changes.

## Known gaps

No credential-reader binary or organization-specific support configuration is
provided. Managed-Mac tests are required for enrollment recovery, no-user
execution, missing Jamf framework and API failure paths.
