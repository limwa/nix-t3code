#!/usr/bin/env nix-shell
#! nix-shell -p python3 nix-update -i python3

import os
import shutil
import subprocess
import sys

class Updater:
    def __init__(self, nix_update_path: str, stdbuf_path: str) -> None:
        self.nix_update_path = nix_update_path
        self.stdbuf_path = stdbuf_path

    def update_attr(self, attr: str) -> bool:
        print(f"{attr}: updating")
        print()

        subenv = os.environ.copy()
        subenv["TERM"] = "dumb"
        subenv["PYTHONUNBUFFERED"] = "1"

        cmd = [self.nix_update_path, "--use-update-script", "--commit", "--flake", attr]

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
        print(f"{attr}: update {"successful" if success else "failed"}")
        print()

        return success


def find_executable(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise Exception(f"Could not find {name} executable")

    return path

def main() -> int:

    nix_update_path = find_executable("nix-update")
    stdbuf_path = find_executable("stdbuf")

    updater = Updater(nix_update_path, stdbuf_path)

    ATTRS = [
        "t3code",
        "t3code-nightly"
    ]

    all_success = True
    for attr in ATTRS:
        success = updater.update_attr(attr)
        all_success = all_success and success

    return 0 if all_success else 1


if __name__ == "__main__":
    sys.exit(main())
