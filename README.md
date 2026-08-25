---
title: ReEnroll
description: A standalone Jamf Pro workflow for repairing and renewing Mac enrollment.
---

![Latest release](https://img.shields.io/github/v/release/AndrewMBarnett/ReEnroll)
![Release downloads](https://img.shields.io/github/downloads/AndrewMBarnett/ReEnroll/latest/total)
![Supported macOS](https://img.shields.io/badge/macOS-12.0%2B-success)

![Open issues](https://img.shields.io/github/issues-raw/AndrewMBarnett/ReEnroll)
![Closed issues](https://img.shields.io/github/issues-closed-raw/AndrewMBarnett/ReEnroll)
![Open pull requests](https://img.shields.io/github/issues-pr-raw/AndrewMBarnett/ReEnroll)
![Closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/AndrewMBarnett/ReEnroll)

Macadmins Slack channel: [#reenroll](https://macadmins.slack.com/archives/C07RWK4QETB)

ReEnroll automates repairing or renewing a Mac's Jamf Pro enrollment. It can
redeploy the Jamf framework, renew profiles, send an enrollment invitation,
validate inventory and policy status, verify LAPS, update site assignment, and
remove explicitly targeted local accounts.

![ReEnroll deployment workflow](Extras/Images/ReEnrollDeployFrameworkCheckIn.png)

## Features

- Redeploy the Jamf framework silently or with a swiftDialog progress window.
- Re-enroll through a Jamf Pro enrollment invitation or profile renewal.
- Validate policy, inventory, and device-signature status after enrollment.
- Validate and rotate the Jamf-managed local administrator password.
- Preserve or update Jamf Pro site assignment.
- Remove explicitly targeted local accounts while preserving exempt accounts.
- Send Teams or Slack result notifications.

## Prerequisites

ReEnroll supports macOS 12 and later. Jamf API client credentials require Jamf
Pro 10.49 or later. The inventory client tries the current `v3` API first and
falls back to `v2` or deprecated `v1` for older on-premises compatibility.

## Jamf Pro Deployment

Do not upload `ReEnroll.sh` by itself because the source tree is modular.
Generate the standalone Jamf Script object payload with:

```bash
python3 scripts/build_jamf_artifact.py
```

Upload `dist/ReEnroll-jamf.zsh` to Jamf Pro. Jamf custom parameters are:

- `$4`: legacy API client ID; ignored unless
  `REENROLL_ALLOW_PARAMETER_CREDENTIALS=true`.
- `$5`: legacy API client secret; ignored unless the same temporary
  compatibility switch is enabled.
- `$6`: Jamf-managed LAPS administrator username.
- `$7`: enrollment invitation ID.
- `$8`: display the swiftDialog progress UI (`true` or `false`; default
  `false`).
- `$9`: optional absolute path to the dedicated signed API credential reader.

Upload the eight scripts in `Extras/Extension Attributes/` as Jamf Pro
Extension Attributes when their inventory values are needed. Do not upload
files from `lib/` or `ReEnroll.sh` directly; they are build inputs for the
standalone artifact.

Use a recurring or enrollment policy when `$8` is `false`. Use Self Service or
a login-triggered policy when displaying the progress UI. The fallback
AppleScript dialog runs in the active console user's bootstrap and UID context
and skips safely when no eligible GUI user exists.

Use Jamf's per-script operating-system requirement to prevent execution below
macOS 12. Test recurring check-in and Self Service policies, including
login-window execution and a missing local Jamf binary.

## Credentials

Ordinary Jamf script parameters expose secrets as process arguments. The
supported default is a System-keychain pair with service `ReEnroll` and
accounts `JamfApiClientID` and `JamfApiClientSecret`, read through
`REENROLL_CREDENTIAL_READER`.

The reader must be an absolute-path, root-owned, signed executable that is not
group/world writable. It receives account and service arguments and prints the
secret. Direct use of `/usr/bin/security` requires the explicit legacy switch
`REENROLL_ALLOW_SECURITY_CLI_CREDENTIAL_READER=true`.

Grant the API client only these required privileges:

- Read Computer Inventory Collection
- Read Computer Check-In
- Update Computers
- Read Computers
- Read Sites
- Flush MDM Commands
- Flush Policy Logs
- Update Computer Inventory Collection
- View Local Admin Password
- Send Computer Remote Command to Install Package
- Send Local Admin Password Command

## Enrollment Considerations

Create the enrollment invitation in Jamf Pro and place only its invitation ID
in `$7`. For profile renewal on macOS 14 or later, ensure the Mac is assigned to
the correct Automated Device Enrollment group in Apple Business Manager or
Apple School Manager.

ReEnroll cannot recover a PreStage administrator account when no Jamf-managed
local administrator is configured. Do not use the same username for a
user-initiated-enrollment administrator and a PreStage administrator; Jamf may
be unable to return the LAPS password.

See Jamf's
[Local Administrator Password Solution documentation](https://learn.jamf.com/en-US/bundle/technical-paper-laps-current/page/Local_Administrator_Password_Solution.html)
for supported LAPS behavior and requirements.
