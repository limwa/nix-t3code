{
  lib,
  newScope,
}:
lib.makeScope newScope (self: {
  t3code = self.callPackage ./t3code/default.nix {};
  t3code-nightly = self.callPackage ./t3code-nightly/default.nix {};
})
