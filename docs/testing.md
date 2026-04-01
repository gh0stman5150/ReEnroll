# Testing

`ReEnroll` now supports a lightweight dry-run mode for local verification work.

## Dry Run

Set `DRY_RUN=1` or `DRY_RUN=true` before running the script to simulate Jamf API mutations, local account changes, LaunchDaemon creation, enrollment prompts, and webhook delivery.

Example:

```zsh
DRY_RUN=1 zsh ./ReEnroll.sh
```

Dry-run mode is intended for safe workflow exercise and log inspection. It does not replace a real Jamf-managed validation run.

## Repo Checks

Run the local verification harness from the repo root:

```zsh
./scripts/check.sh
```

That script performs:

- `zsh -n` syntax checks for `ReEnroll.sh` and every file in `lib/`
- a small smoke test in `tests/module_smoke.zsh`
- fixture-backed parsing checks using files in `tests/fixtures/`
