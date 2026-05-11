#!/usr/bin/env nix-shell
#! nix-shell -p python3 nix-update nix -i python3

from abc import ABC, abstractmethod
import argparse
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
import json
import os
import shutil
import subprocess
import sys


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


def exec_json(cmd: Sequence[str], env: Mapping[str, str] | None = None) -> object:
    return json.loads(exec_stdout(cmd, env=env))

def assert_is[Out](expected_type: type[Out], value: object) -> Out:
    if not isinstance(value, expected_type):
        raise Exception(f"Expected value of type {expected_type}, got {type(value)}")

    return value

def get_current_system() -> str:
    return assert_is(
        str,
        exec_json(
            [NIX_EXECUTABLE, "eval", "--json", "--expr", "builtins.currentSystem", "--impure"]
        )
    )


def get_available_attrs() -> list[str]:
    system = get_current_system()
    attrs = assert_is(
        list,
        exec_json(
            [
                NIX_EXECUTABLE,
                "eval",
                "--json",
                ".#packages",
                "--apply",
                f'(s: builtins.attrNames (s."{system}" or {{}}))',
            ]
        ),
    )

    return list(assert_is(str, attr) for attr in attrs)


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

    def commit(self) -> str:
        self.__assert_is_clean()
        self.checkpoint = self.get_head()
        return self.checkpoint

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

        return exec(
            [NIX_UPDATE_EXECUTABLE, "--use-update-script", "--commit", "--flake", attr],
            env=subenv,
        )

    def test_package(self, attr: str) -> bool:
        return exec([NIX_EXECUTABLE, "build", "--no-link", f".#{attr}"])


class UpdateStep(ABC):
    def __init__(self, step_id: str) -> None:
        self.step_id = step_id

    @abstractmethod
    def run_update_phase(self, updater: Updater) -> bool:
        raise NotImplementedError

    @abstractmethod
    def run_check_phase(self, updater: Updater) -> str | None:
        raise NotImplementedError


class FlakeLockUpdateStep(UpdateStep):
    def __init__(self, attrs: Sequence[str]) -> None:
        super().__init__("flake.lock")
        self.attrs = tuple(attrs)

    def run_update_phase(self, updater: Updater) -> bool:
        return updater.update_flake_lock()

    def run_check_phase(self, updater: Updater) -> str | None:
        if not exec([NIX_EXECUTABLE, "flake", "check"]):
            return "flake check failed after update"

        return None


class PackageUpdateStep(UpdateStep):
    def __init__(self, attr: str) -> None:
        super().__init__(f"packages/{attr}")
        self.attr = attr

    def run_update_phase(self, updater: Updater) -> bool:
        return updater.update_package(self.attr)

    def run_check_phase(self, updater: Updater) -> str | None:
        if not updater.test_package(self.attr):
            return "failed to build after update"

        return None


@dataclass
class UpdateOrchestrator:
    updater: Updater
    worktree: GitWorktree
    skipped_update_steps: set[str] = field(default_factory=set)
    skipped_check_steps: set[str] = field(default_factory=set)
    steps: list[UpdateStep] = field(default_factory=list)

    def register_step(self, step: UpdateStep) -> None:
        self.steps.append(step)

    def run(self) -> int:
        step_results = {
            step.step_id: self.__run_step(step)
            for step in self.steps
        }

        print()
        print("Summary:")
        for step in self.steps:
            status = "good" if step_results[step.step_id] else "bad"
            print(f"  - {step.step_id}: {status}")

        overall_success = all(step_results.values())
        return 0 if overall_success else 1

    def __run_step(self, step: UpdateStep) -> bool:
        print(f"{step.step_id}: updating...")

        self.worktree.commit()
        has_update_changes = False

        if step.step_id in self.skipped_update_steps:
            print(f"{step.step_id}: update phase skipped")
        else:
            if not step.run_update_phase(self.updater):
                print(f"{step.step_id}: failed to update")
                self.worktree.revert()
                return False

            if not self.worktree.has_uncommitted_changes():
                print(f"{step.step_id}: already up to date")
                return True

            has_update_changes = True
            print(f"{step.step_id}: updated")

        if step.step_id in self.skipped_check_steps:
            print(f"{step.step_id}: check phase skipped")
        else:
            print(f"{step.step_id}: checking...")
            check_error = step.run_check_phase(self.updater)
            if check_error is not None:
                print(f"{step.step_id}: {check_error}")
                self.worktree.revert()
                return False

        if has_update_changes:
            self.worktree.commit()

        return True


def parse_args(step_ids: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Update flake inputs and package definitions in sequence."
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available package attrs and exit.",
    )
    parser.add_argument(
        "--skip-update",
        action="append",
        choices=step_ids,
        default=[],
        metavar="STEP_ID",
        help="Skip the update phase for a step. May be passed multiple times.",
    )
    parser.add_argument(
        "--skip-check",
        action="append",
        choices=step_ids,
        default=[],
        metavar="STEP_ID",
        help="Skip the check phase for a step. May be passed multiple times.",
    )
    return parser.parse_args()


def main() -> int:
    attrs = get_available_attrs()

    steps: list[UpdateStep] = [
        FlakeLockUpdateStep(attrs),
        *(PackageUpdateStep(attr) for attr in attrs),
    ]

    args = parse_args([step.step_id for step in steps])

    if args.list:
        for step in steps:
            print(step.step_id)
        return 0

    orchestrator = UpdateOrchestrator(
        updater=Updater(),
        worktree=GitWorktree(os.getcwd()),
        skipped_update_steps=set(args.skip_update),
        skipped_check_steps=set(args.skip_check),
    )
    for step in steps:
        orchestrator.register_step(step)

    return orchestrator.run()


if __name__ == "__main__":
    sys.exit(main())
