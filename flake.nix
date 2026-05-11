{
  description = "Auto-updating source builds of T3 Code for Linux and MacOS.";

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

        packages =
          { pkgs, ... }:
          {
            inherit (pkgs.callPackage ./packages/scope.nix { })
              t3code
              t3code-nightly
              ;
          };

        checks = utils.lib.invokeAttrs {
          t3code = { outputs, ... }: outputs.packages.t3code;
          t3code-nightly = { outputs, ... }: outputs.packages.t3code-nightly;
        };

        devShells = utils.lib.invokeAttrs {
          default = { outputs, ... }: outputs.devShells.updateScript;

          updateScript =
            { pkgs, ... }:
            pkgs.mkShell {
              name = "update-script-dev-shell";
              packages = with pkgs; [
                python3
              ];
            };
        };
      };
}
