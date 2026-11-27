# BEGIN nix-t3code meta
# LAST SYNC: 1be7652e6e96aff0192d84259f96927df2259675
# DIFF: COMMIT=1be7652e6e96aff0192d84259f96927df2259675; SYNC="$(gh api repos/NixOS/nixpkgs/commits/master --jq '.sha')"; echo $SYNC; delta <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$COMMIT/pkgs/by-name/t3/t3code/resource-monitor.nix") <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$SYNC/pkgs/by-name/t3/t3code/resource-monitor.nix")
# END nix-t3code meta
{
  lib,
  stdenv,
  darwin,
  rustPlatform,
  t3code-unwrapped,
}:

rustPlatform.buildRustPackage {
  pname = "t3code-resource-monitor";
  inherit (t3code-unwrapped) version src;

  sourceRoot = "${t3code-unwrapped.src.name}/native/resource-monitor";

  cargoHash = "sha256-QartZALjE2BxgfKcV3CJjtG6oSNE/Vcbz2ESx1UrRbk=";

  # A test runs BSD `ps` and `date -u -r SECONDS` by bare name. The build PATH
  # has no `ps`, and its GNU `date` reads `-r` as a file. Expose only those two,
  # since phases share one shell and other BSD tools would shadow GNU ones.
  preCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p "$TMPDIR/bsd-bin"
    ln -s ${lib.getExe' darwin.ps "ps"} ${lib.getExe' darwin.shell_cmds "date"} "$TMPDIR/bsd-bin"
    export PATH="$TMPDIR/bsd-bin:$PATH"
  '';

  meta = {
    description = "Native resource diagnostics sidecar for T3 Code";
    inherit (t3code-unwrapped.meta)
      homepage
      changelog
      license
      maintainers
      platforms
      ;
    mainProgram = "t3-resource-monitor";
  };
}
