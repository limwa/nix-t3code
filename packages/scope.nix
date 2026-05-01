{
  lib,
  newScope,
}:
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

  t3code = self.callPackage ./t3code/default.nix { };
  t3code-nightly = self.callPackage ./t3code-nightly/default.nix { };
})
