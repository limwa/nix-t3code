# nix-t3code

`nix-t3code` packages [T3 Code](https://t3.codes) as a Nix flake.

The code in this repository was cherry-picked from [this Nixpkgs PR](https://github.com/NixOS/nixpkgs/pull/510466).

## Packages

- `t3code`: alpha releases
- `t3code-nightly`: alpha prereleases

## Installation

### Quick Install

This is the recommended path for most users:

```
nix profile install github:limwa/nix-t3code#t3code
```

This repository updates every 12 hours, so `nix profile` is a good fit even
though it is not ideal for strict reproducibility.

To pin a specific commit:

```
nix profile install github:limwa/nix-t3code/<commit>#t3code
```

To update the installed package:

```
nix profile upgrade t3code
```

### Flake Input

Add this repository to your flake inputs:

```nix
inputs = {
  # ...
  nix-t3code.url = "github:limwa/nix-t3code";
};
```

Then use it from your NixOS configuration:

```nix
{ inputs, ... }:
{
  environment.systemPackages = [ inputs.nix-t3code.packages.${pkgs.stdenv.hostPlatform.system}.t3code ];
}
```

This is the more reproducible option, since the package version is pinned by
your flake lock file. The tradeoff is that updating the package requires a
system rebuild.

## Auto-updates

This repository is mostly unattended.

- A scheduled action updates the flake inputs and individual packages every 12 hours.
- `flake.lock` is updated only if every package still builds after the update.
- Each package is updated only if it still builds after the update.
- Manual intervention is required when an update is blocked by a build failure.
