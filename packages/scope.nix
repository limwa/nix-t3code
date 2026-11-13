{
  lib,
  newScope,
  nix-update,
  nixVersions,
}:

let
  defaultOptions = {
    enableAzureDevOps = false;
    enableBitbucket = false;
    enableClaude = false;
    enableCodex = false;
    enableCursor = false;
    enableCursorCli = false;
    enableGitHub = false;
    enableGit = false;
    enableGitLab = false;
    enableJujutsu = false;
    enableOpencode = false;
  };
in

lib.makeScope newScope (self: {
  lib = lib.extend (
    final: prev: {
      maintainers = prev.maintainers // {
        limwa = {
          name = "André Lima";
          github = "limwa";
          githubId = 13498603;
          email = "me@limwa.pt";
        };
      };
    }
  );

  # The update scripts run nix-update inside `nix develop`, and nix-update's
  # wrapper puts its own `nix` first on PATH. Pin it to 2.34: on 2.35,
  # `nix flake metadata` reports a store path that does not exist for a dirty
  # tree (https://github.com/Mic92/nix-update/issues/687).
  # `nix-update` is passed to itself so that `passthru.nix-update-script` uses
  # the pinned build as well.
  nix-update = nix-update.override {
    nix = nixVersions.nix_2_34;
    nix-update = self.nix-update;
  };
  nix-update-script = self.nix-update.nix-update-script;

  t3code = self.callPackage ./t3code/default.nix defaultOptions;
  t3code-nightly = self.callPackage ./t3code-nightly/default.nix defaultOptions;
})
