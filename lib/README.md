---
title: ReEnroll Modules
description: Build-time zsh modules embedded into the standalone ReEnroll Jamf artifact.
---

This directory separates ReEnroll's dialog, API, launchd, webhook, LAPS, and
enrollment logic for development and testing.

## Inventory

- `dialog.zsh`: swiftDialog setup and progress-window behavior.
- `jamf_api.zsh`: Jamf Pro API requests, authentication, and validation.
- `launchd.zsh`: Deferred launchd workflow generation and management.
- `webhooks.zsh`: Teams and Slack result notifications.
- `laps.zsh`: Jamf-managed local administrator password workflows.
- `enrollment.zsh`: Framework redeployment and enrollment-renewal behavior.

## Jamf Deployment

- Do not upload individual modules to Jamf Pro.
- Run `python3 scripts/build_jamf_artifact.py` and upload
  `dist/ReEnroll-jamf.zsh`.
- The generated artifact embeds every module and is validated to contain no
  remaining `sourceModule` call.

## Parameters And Logging

Modules do not parse Jamf parameters independently. `ReEnroll.sh` owns `$4`
through `$9` and writes runtime output to
`/Library/Application Support/ReEnroll/ReEnroll.log`. There are no deprecated
modules.
