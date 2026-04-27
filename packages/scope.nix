{
  lib,
  newScope,
}:
lib.makeScope newScope (self: {
  mkT3Code = self.callPackage ./mk-t3code-package/default.nix {};

  t3code = self.callPackage ./t3code/default.nix {};
  t3code-nightly = self.callPackage ./t3code-nightly/default.nix {};
})
