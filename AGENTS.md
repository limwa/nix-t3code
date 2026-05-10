# Repository Guidelines

## Project Structure & Module Organization
This repository is a small Nix flake for packaging T3 Code. Top-level flake entry points live in `flake.nix`, `flake.lock`, and `shell.nix`. Package definitions are under `packages/`: `packages/t3code/default.nix` for stable releases, `packages/t3code-nightly/default.nix` for prereleases, and `packages/scope.nix` for shared scope and maintainer metadata. The update automation is implemented in `update.py`. GitHub Actions workflow files live in `.github/workflows/`.

## Build, Test, and Development Commands
- `nix build .#t3code`: build the stable package.
- `nix build .#t3code-nightly`: build the nightly package.
- `nix flake check`: validate flake evaluation and standard checks.
- `nix fmt .`: format Nix files with the configured formatter.
- `nix develop .#updateScript`: enter the shell used for update work.
- `./update.py`: update `flake.lock` and package versions, committing only successful builds.

Run builds from the repository root. For packaging changes, build the affected attr before opening a PR.

## Coding Style & Naming Conventions
Use the existing Nix style: two-space indentation, trailing semicolons, and attribute names in `camelCase` or the established package names (`t3code`, `t3code-nightly`). Keep stable and nightly derivations structurally aligned unless a release channel needs a real divergence. In Python, follow the existing typed, standard-library-only style in `update.py` and keep helper functions small.

## Testing Guidelines
There is no separate unit test suite here; the main verification step is a successful Nix build. After changing `packages/` or `flake.nix`, run `nix build .#t3code` and/or `nix build .#t3code-nightly`. After changing update logic, run `nix flake check` and a dry review of `./update.py` behavior before using it against a clean worktree.

## Commit & Pull Request Guidelines
Follow the commit style already in history: concise, attr-focused summaries such as `t3code: 0.0.22 -> 0.0.23` or `t3code-nightly: 0.0.23-nightly... -> ...`. Keep unrelated changes out of the same commit. PRs should state which attrs changed, note the commands used to verify them, and mention any platform-specific risk. Include screenshots only when changing documentation with visible UI output.
