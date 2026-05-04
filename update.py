#!/usr/bin/env nix-shell
#! nix-shell -p python3 nix-update -i python3

import os
import shutil
import subprocess
import sys
from typing import Optional, Sequence

class Updater:
    def __init__(self, nix_update_path: str) -> None:
        self.nix_update_path = nix_update_path

    def get_worktree_head(self) -> str:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def is_worktree_clean(self) -> bool:
        tracked_clean = (
            subprocess.run(
                ["git", "diff", "--quiet"],
                check=False,
            ).returncode
            == 0
        )
        staged_clean = (
            subprocess.run(
                ["git", "diff", "--cached", "--quiet"],
                check=False,
            ).returncode
            == 0
        )
        return tracked_clean and staged_clean

    def update_flake_lock(self) -> tuple[bool, Optional[str]]:
        print("flake.lock: updating")
        print()

        if not self.is_worktree_clean():
            print("flake.lock: update failed")
            print("git worktree must be clean before running flake lock update")
            print()
            return False, None

        head_before = self.get_worktree_head()
        success = (
            subprocess.run(
                ["nix", "flake", "update", "--commit-lock-file"],
                check=False,
            ).returncode
            == 0
        )
        head_after = self.get_worktree_head()
        reset_target = head_before if head_after != head_before else None

        print()
        print(f"flake.lock: update {'successful' if success else 'failed'}")
        if success and reset_target is None:
            print("flake.lock: already up to date")
        print()

        return success, reset_target

    def revert_flake_lock_update(self, reset_target: str) -> bool:
        print("flake.lock: reverting update because a package build failed")
        print()

        success = (
            subprocess.run(
                ["git", "reset", "--hard", reset_target],
                check=False,
            ).returncode
            == 0
        )

        print()
        print(f"flake.lock: revert {'successful' if success else 'failed'}")
        print()

        return success

    def build_attr(self, attr: str) -> bool:
        print(f"{attr}: building")
        print()

        success = (
            subprocess.run(
                ["nix", "build", "--no-link", f".#{attr}"],
                check=False,
            ).returncode
            == 0
        )

        print()
        print(f"{attr}: build {'successful' if success else 'failed'}")
        print()

        return success

    def ensure_attrs_build(self, attrs: Sequence[str]) -> bool:
        for attr in attrs:
            if not self.build_attr(attr):
                return False
        return True

    def update_attr(self, attr: str) -> bool:
        print(f"{attr}: updating")
        print()

        subenv = os.environ.copy()
        subenv["TERM"] = "dumb"
        subenv["PYTHONUNBUFFERED"] = "1"

        cmd = [self.nix_update_path, "--use-update-script", "--commit", "--build", "--flake", attr]

        with subprocess.Popen(
            cmd,
            env=subenv,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
        ) as process:
            if process.stdout is not None:
                for line in process.stdout:
                    print(f"| {line}", end='', file=sys.stderr)

            success = process.wait() == 0

        print()
        print(f"{attr}: update {'successful' if success else 'failed'}")
        print()

        return success


def find_executable(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise Exception(f"Could not find {name} executable")

    return path

def main() -> int:

    nix_update_path = find_executable("nix-update")

    updater = Updater(nix_update_path)

    ATTRS = [
        "t3code",
        "t3code-nightly"
    ]

    flake_updated, flake_reset_target = updater.update_flake_lock()
    if not flake_updated:
        return 1

    if not updater.ensure_attrs_build(ATTRS):
        if flake_reset_target is not None:
            if not updater.revert_flake_lock_update(flake_reset_target):
                return 1
        return 1

    all_success = True
    for attr in ATTRS:
        success = updater.update_attr(attr)
        all_success = all_success and success

    return 0 if all_success else 1


if __name__ == "__main__":
    sys.exit(main())
