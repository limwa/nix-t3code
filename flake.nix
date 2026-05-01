{
  description = "A basic flake for development with Nix and NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:limwa/nix-flake-utils";

    # Needed for shell.nix
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      ...
    }:
    utils.lib.mkFlakeWith
      {
        forEachSystem = system: {
          outputs = utils.lib.forSystem self system;

          pkgs = import nixpkgs {
            inherit system;
          };
        };
      }
      {
        formatter = { pkgs, ... }: pkgs.nixfmt-tree;

        packages = { pkgs, ... }: pkgs.callPackage ./packages/scope.nix { };
      };
}
