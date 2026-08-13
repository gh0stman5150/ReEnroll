#!/usr/bin/env python3
"""Build the standalone ReEnroll script uploaded to a Jamf Pro Script object."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ReEnroll.sh"
OUTPUT = ROOT / "dist" / "ReEnroll-jamf.zsh"
MODULES = (
    "dialog.zsh",
    "jamf_api.zsh",
    "launchd.zsh",
    "webhooks.zsh",
    "laps.zsh",
    "enrollment.zsh",
)


def module_text(name: str) -> str:
    lines = (ROOT / "lib" / name).read_text(encoding="utf-8").splitlines()
    if len(lines) >= 2 and "_MODULE_LOADED" in lines[0] and "_MODULE_LOADED" in lines[1]:
        lines = lines[2:]
    return f"# BEGIN INLINED MODULE: {name}\n" + "\n".join(lines).rstrip() + f"\n# END INLINED MODULE: {name}"


def build() -> str:
    result = SOURCE.read_text(encoding="utf-8")
    for name in MODULES:
        marker = f'sourceModule "{name}"'
        if result.count(marker) != 1:
            raise RuntimeError(f"Expected exactly one module marker for {name}")
        result = result.replace(marker, module_text(name), 1)

    if 'sourceModule "' in result:
        raise RuntimeError("Unresolved ReEnroll module marker remains")
    header = "# GENERATED FILE: run scripts/build_jamf_artifact.py; do not edit directly.\n"
    return result.replace("#!/bin/zsh --no-rcs\n", "#!/bin/zsh --no-rcs\n" + header, 1)


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(build(), encoding="utf-8", newline="\n")
    print(OUTPUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
