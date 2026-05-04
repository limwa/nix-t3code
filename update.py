#!/usr/bin/env nix-shell
#! nix-shell -p python3 nix-update nix -i python3

from collections.abc import Callable, Mapping
import os
import shutil
import subprocess
import sys
from typing import Literal, Sequence


def find_executable(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise Exception(f"Could not find {name} executable")

    return path


GIT_EXECUTABLE = find_executable("git")
NIX_EXECUTABLE = find_executable("nix")
NIX_UPDATE_EXECUTABLE = find_executable("nix-update")

def exec(cmd: Sequence[str], env: Mapping[str, str] | None = None) -> bool:
    result = subprocess.run(cmd, env=env, check=False)
    return result.returncode == 0

def exec_stdout(cmd: Sequence[str], env: Mapping[str, str] | None = None) -> str:
    result = subprocess.run(cmd, env=env, check=True, capture_output=True, text=True)
    return result.stdout.strip()


class GitWorktree:
    def __init__(self, dir: str) -> None:
        self.dir = dir

        self.checkpoint = self.commit()

    def __make_git_cmd(self, args: Sequence[str]) -> list[str]:
        return [GIT_EXECUTABLE, "-C", self.dir] + list(args)

    def get_head(self) -> str:
        return exec_stdout(self.__make_git_cmd(["rev-parse", "HEAD"]))

    def is_clean(self) -> bool:
        is_working_area_clean = exec(self.__make_git_cmd(["diff", "--quiet"]))
        is_staging_area_clean = exec(self.__make_git_cmd(["diff", "--cached", "--quiet"]))

        return is_working_area_clean and is_staging_area_clean

    def __assert_is_clean(self) -> None:
        if not self.is_clean():
            raise Exception("Cannot commit because the worktree is not clean")

    def has_uncommitted_changes(self) -> bool:
        self.__assert_is_clean()
        return self.get_head() != self.checkpoint

    def commit(self) -> None:
        self.__assert_is_clean()
        self.checkpoint = self.get_head()

    def revert(self) -> None:
        if self.checkpoint is None:
            raise Exception("Cannot revert because no checkpoint has been committed")

        if not exec(self.__make_git_cmd(["reset", "--hard", self.checkpoint])):
            raise Exception("Failed to revert to checkpoint")


class Updater:
    def update_flake_lock(self) -> bool:
        return exec([NIX_EXECUTABLE, "flake", "update", "--commit-lock-file"])

    def update_package(self, attr: str) -> bool:
        subenv = os.environ.copy()
        subenv["TERM"] = "dumb"
        subenv["PYTHONUNBUFFERED"] = "1"

        return exec([NIX_UPDATE_EXECUTABLE, "--use-update-script", "--commit", "--flake", attr], env=subenv)

    def test_package(self, attr: str) -> bool:
        is_building = exec([NIX_EXECUTABLE, "build", "--no-link", f".#{attr}"])
        return is_building

type Option[T] = tuple[Literal[True], T] | tuple[Literal[False], None]

def main() -> int:
    ATTRS = [
        "t3code",
        "t3code-nightly"
    ]

    updater = Updater()
    worktree = GitWorktree(os.getcwd())

    def update(target: str, update_phase: Callable[[], bool], check_phase: Callable[[], Option[str]]) -> bool:
        print(f"{target}: updating...")

        worktree.commit()
        if not update_phase():
            print(f"{target}: failed to update")
            worktree.revert()
            return False

        if not worktree.has_uncommitted_changes():
            print(f"{target}: already up to date")
            return True

        print(f"{target}: updated")

        match check_phase():
            case (True, error_message):
                print(f"{target}: {error_message}")
                worktree.revert()
                return False

            case _:
                worktree.commit()
                return True


    def update_flake_lock() -> bool:
        # 1. Update the flake lock file. The changes can only be committed if all packages can be built successfully.

        def update_phase() -> bool:
            return updater.update_flake_lock()

        def check_phase() -> Option[str]:
            for attr in ATTRS:
                if not updater.test_package(attr):
                    return (True, f"failed to build {attr} after update")

            return (False, None)

        return update(
            "flake.lock",
            update_phase=update_phase,
            check_phase=check_phase
        )

    def update_package(attr: str) -> bool:
        # 2. Update the package. The changes can only be committed if the package can be built successfully.

        def update_phase() -> bool:
            return updater.update_package(attr)

        def check_phase() -> Option[str]:
            if not updater.test_package(attr):
                return (True, "failed to build after update")

            return (False, None)

        return update(
            f"packages/{attr}",
            update_phase=update_phase,
            check_phase=check_phase
        )


    is_flake_updated = update_flake_lock()
    is_package_updated = { pkg: update_package(pkg) for pkg in ATTRS }

    print()
    print("Summary:")
    print(f"  - flake.lock: {'good' if is_flake_updated else 'bad'}")
    for attr, is_updated in is_package_updated.items():
        print(f"  - packages/{attr}: {'good' if is_updated else 'bad'}")

    overall_success = is_flake_updated and all(is_package_updated.values())
    return 0 if overall_success else 1


if __name__ == "__main__":
    sys.exit(main())
