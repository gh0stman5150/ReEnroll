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

Contributor guidance: [AGENTS.md](AGENTS.md) is authoritative for this
repository's Jamf compatibility, safety and validation requirements.

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
Extension Attributes when their inventory values are needed. Each reports the
value stored in `ReEnroll.plist` in full; Device ReEnroll Last Run drops only
the trailing `+0000` time zone offset so Jamf reads it as a date. Do not upload
files from `lib/` or `ReEnroll.sh` directly; they are build inputs for the
standalone artifact.

Use a recurring or enrollment policy when `$8` is `false`. Use Self Service or
a login-triggered policy when displaying the progress UI. The fallback
AppleScript dialog runs in the active console user's bootstrap and UID context
and skips safely when no eligible GUI user exists.

Use Jamf's per-script operating-system requirement to prevent execution below
macOS 12. Test recurring check-in and Self Service policies, including
login-window execution and a missing local Jamf binary.

## Source configuration and testing

Before building, review the configuration section in `ReEnroll.sh`, including
`targeted_users`, `exempt_users`, account-cleanup and enrollment switches,
organization identifiers, site assignment, `adminGrantMaxSeconds` and
support-contact placeholders. These are source settings, not extra Jamf
parameters. Rebuild after changes. Webhooks are disabled by default; do not
commit private webhook URLs.

Run `zsh scripts/check.sh`. See [testing and dry-run limits](docs/testing.md)
for the full checks and endpoint validation. Runtime output is in
`/Library/Application Support/ReEnroll/ReEnroll.log`.

## Runtime behavior

- **Temporary admin rights.** When the profiles-renew flow must make a
  non-admin console user an administrator, ReEnroll first records the grant
  (`ReEnrollPromotedUser`, `ReEnrollPromotedPID` and `ReEnrollPromotedAt` in
  `ReEnroll.plist`) and arms an admin guard LaunchDaemon,
  `<organizationReverseDomain>.reenroll-admin-guard`
  (`/Library/LaunchDaemons/<label>.plist` running
  `/Library/Application Support/ReEnroll/ReEnrollAdminGuard.zsh`). If the
  guard cannot be armed, the user is not promoted. The exit handler demotes
  the user and removes the guard. If the run is killed, times out or the Mac
  restarts first, the guard demotes the recorded user within a minute of the
  run ending, at the next boot, or after `adminGrantMaxSeconds` (default
  3600), then removes itself. Each run also revokes a stale grant at startup,
  whatever `renewProfiles` is set to. Accounts that were already
  administrators are never recorded and never demoted. Guard activity is
  logged with `[ADMIN GUARD]` in `ReEnroll.log`.
- **Login window.** ReEnroll checks for Finder and Dock up to ten times, two
  seconds apart. When `$8` is `false`, a run with nobody logged in at the
  desktop continues at once, and a run whose desktop never appears logs a
  warning and continues. Only a run that shows the progress dialog (`$8`
  `true`) exits when no desktop appears.
- **Enrollment receipt.** `DeviceEnrolledStatus`, reported by the Device
  ReEnroll Status extension attribute, is set to `Enrolled Device` only when
  the run has evidence of enrollment: Jamf Pro accepted the framework
  redeploy (HTTP 2xx), `jamf enroll` accepted the invitation, the console user
  accepted the enrollment renewal, or the Jamf policy check-in or LAPS
  credentials were verified. The accepted-command cases record it before the
  enrollment submits inventory, so smart groups that exclude re-enrolled Macs
  still apply to the policies that enrollment triggers. A run that fails
  before any of these leaves the earlier value unchanged; a declined or failed
  profile renewal still records `Not Enrolled`. Dry runs do not change it.
- **Enrollment invitation.** ReEnroll checks for the Jamf binary before it
  deletes the LAPS account. A failed `jamf enroll` is logged as an error and
  is not recorded as the ReEnroll method, and the LAPS password is not
  rotated.
- **LAPS account deletion.** The account named by `$6` is deleted before an
  enrollment invitation or profile renewal only when it exists, has a UID of
  500 or above, is not the console user and is not in `exempt_users`. A
  refused or failed deletion is logged as an error. Its home folder is left
  in place.
- **LAPS verification.** The LAPS credentials are checked at once, so a valid
  account adds no wait. After a failed check ReEnroll sends the enrollment
  invitation (at most once per run) and re-checks after 60 seconds, at most
  two checks per verification. After rotating the password it waits 60
  seconds for Jamf Pro to escrow it before verifying.
- **Account cleanup.** An account in `targeted_users` is deleted only when its
  UID is above 500, it is not the console user or in `exempt_users`, and
  `dseditgroup` reports that it is not an administrator; an account whose
  membership cannot be read is kept. Its home folder is removed only when it
  is a real directory (not a symlink) directly under `/Users`, other than
  `Shared`, owned by that account; otherwise the folder is left in place and
  the reason is logged. The LAPS account is demoted first only when it passes
  the same account checks.
- **Inventory username.** `jamf recon` (directly and in the recon
  LaunchDaemon) receives `-endUsername` only when the console account has a
  `NetworkUser` (Jamf Connect or mobile account). For local accounts the
  argument is omitted, leaving the computer record's User and Location
  username unchanged.
- **Policy check-in.** ReEnroll reads `/var/log/jamf.log` every 2 seconds,
  up to 120 times, to confirm the policy check-in. Each read covers only the
  bytes added since the previous one, so a large log is not scanned again.
- **Check-in termination.** After the policy check, ReEnroll stops only
  `jamf` processes running an enrollment (`enroll` or `enrollmentComplete`).
  It leaves the `jamf` process running this policy and unrelated `jamf` runs
  alone.
- **Site restore.** The site recorded before redeployment is the one sent
  back to Jamf Pro. If the inventory lookup fails, ReEnroll stops without
  changing the site or the recorded value.
- **Webhooks.** Values in Slack and Teams payloads are JSON-escaped; Slack
  mrkdwn fields also escape `&`, `<` and `>`.

## Troubleshooting

For failures, verify the uploaded artifact, credential reader, credential pair
and policy parameters. Use this repository's issue tracker for defects and
the internal endpoint support process for production incidents. The Slack
link is a community channel; internal ownership is not specified here.

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
