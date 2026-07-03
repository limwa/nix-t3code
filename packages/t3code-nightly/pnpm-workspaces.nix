{
  lib,
  runCommand,
  writableTmpDirAsHomeHook,
  pnpm,
  yq-go,
  t3code-meta,
  t3code-source,
}:

# IFD to determine the pnpm workspaces present in the project
lib.importJSON (
  runCommand "${t3code-meta.pname}-pnpm-workspaces"
    {
      __structuredAttrs = true;
      strictDeps = true;

      nativeBuildInputs = [
        writableTmpDirAsHomeHook
        pnpm
        yq-go
      ];
    }
    ''
      touch packages
      PACKAGES_FILE="$(realpath packages)"

      cd "${t3code-source}"
      pnpm --config.managePackageManagerVersions=false -cw exec realpath package.json >> "$PACKAGES_FILE"
      pnpm --config.managePackageManagerVersions=false -cr exec realpath package.json >> "$PACKAGES_FILE"

      mapfile -t paths < "$PACKAGES_FILE"
      yq eval-all -I0 '[.name]' "''${paths[@]}" > "$out"
    ''
)
