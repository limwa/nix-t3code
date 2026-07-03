{
  lib,
  newScope,
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

  t3code = self.callPackage ./t3code/default.nix defaultOptions;
  t3code-nightly = (self.callPackage ./t3code-nightly/scope.nix defaultOptions).t3code;
})
