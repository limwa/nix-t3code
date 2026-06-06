{
  lib,
  cctools,
  copyDesktopItems,
  electron_40,
  fetchFromGitHub,
  installShellFiles,
  jq,
  libicns,
  makeBinaryWrapper,
  makeDesktopItem,
  nix-update-script,
  node-gyp,
  nodejs,
  python3,
  stdenv,
  writableTmpDirAsHomeHook,
  writeDarwinBundle,
  xcbuild,
  fetchPnpmDeps,
  pnpm_10,
  pnpmConfigHook,
  cacert,
}:

stdenv.mkDerivation (
  finalAttrs:
  let
    appName = "T3 Code (Nightly Alpha)";
    electron = electron_40;
    pnpm = pnpm_10;

    desktopIcon =
      if stdenv.hostPlatform.isDarwin then
        "assets/prod/black-macos-1024.png"
      else
        "assets/prod/black-universal-1024.png";
  in
  {
    pname = "t3code-nightly";
    version = "0.0.25-nightly.20260606.480";

    strictDeps = true;
    __structuredAttrs = true;

    src = fetchFromGitHub {
      owner = "pingdotgg";
      repo = "t3code";
      tag = "v${finalAttrs.version}";
      hash = "sha256-f7+AMiVwRdkMrYI9ag2HnkRr1Km0pfHvv1FtlZTy8SY=";
    };

    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
      node-gyp
      nodejs
      python3
      writableTmpDirAsHomeHook
      jq
      pnpmConfigHook
      pnpm
      cacert
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cctools.libtool
      libicns
      writeDarwinBundle
      xcbuild
    ];

    pnpmWorkspaces = [
      "t3..."
      "@t3tools/desktop..."
      "@t3tools/web..."
    ];

    pnpmDeps = fetchPnpmDeps {
      inherit pnpm;
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        ;

      fetcherVersion = 3;
      hash = "sha256-gS+YE292sgqBgZfQdfKu0Z0Z+fEjgh5rk9QG/iwN2gk=";
    };

    env.RELEASE_VERSION = finalAttrs.version;
    env.ELECTRON_SKIP_BINARY_DOWNLOAD = true;

    postPatch = ''
      substituteInPlace apps/web/vite.config.ts \
        --replace-fail 'const host = process.env.HOST?.trim() || "localhost";' \
                      'const host = process.env.HOST?.trim() || "127.0.0.1";'

      for packageFile in $(find . -name 'package.json'); do
        if jq -e '.version' "$packageFile" > /dev/null; then
          jq --arg release_version "$RELEASE_VERSION" \
            '.version = $release_version' "$packageFile" > "$packageFile.tmp"
          mv "$packageFile.tmp" "$packageFile"
        fi
      done
    '';

    preConfigure = ''
      export pnpmWorkspaces="''${pnpmWorkspaces[@]}"
    '';

    buildPhase = ''
      runHook preBuild

      export npm_config_nodedir=${nodejs}
      pnpm rebuild --pending "''${pnpmInstallFlags[@]}"

      pnpm vp run \
        --filter t3 \
        --filter @t3tools/desktop \
        --filter @t3tools/web \
        build

      pnpm vp cache clean

      runHook postBuild
    '';

    # Bun vendors many prebuilt native artifacts for non-host platforms, and
    # some of those binaries are statically linked. Let fixup handle wrappers,
    # shebangs, and stripping, but skip patchelf on the vendored tree.
    dontPatchELF = true;
    # The tmpdir audit hook also shells out to patchelf while scanning every
    # vendored ELF for leaked build paths. That produces spurious warnings on
    # Bun's static foreign-platform binaries.
    noAuditTmpdir = true;

    installPhase = ''
      runHook preInstall

      mkdir --parents "$out"/libexec/t3code/apps/desktop "$out"/libexec/t3code/apps/server
      cp --recursive --no-preserve=mode node_modules "$out"/libexec/t3code
      cp --recursive --no-preserve=mode apps/server/{node_modules,dist} "$out"/libexec/t3code/apps/server
      cp --recursive --no-preserve=mode apps/desktop/{node_modules,dist-electron} "$out"/libexec/t3code/apps/desktop

      mkdir --parents "$out"/libexec/t3code/apps/desktop/prod-resources
      install --mode=444 ${desktopIcon} \
        "$out"/libexec/t3code/apps/desktop/prod-resources/icon.png

      find "$out"/libexec/t3code -xtype l -delete

      makeWrapper ${lib.getExe nodejs} "$out"/bin/t3code \
        --add-flags "$out"/libexec/t3code/apps/server/dist/bin.mjs

      makeWrapper ${lib.getExe electron} "$out"/bin/t3code-desktop \
        --add-flags "$out"/libexec/t3code/apps/desktop/dist-electron/main.cjs \
        --inherit-argv0
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      mkdir --parents "$out/Applications/${appName}.app/Contents/"{MacOS,Resources}
      png2icns \
        "$out/Applications/${appName}.app/Contents/Resources/t3code.icns" \
        ${desktopIcon}

      # writeDarwinBundle is a shebangless bash script; run it explicitly via
      # stdenv.shell to avoid Darwin's intermittent ENOEXEC fallback issues.
      ${stdenv.shell} ${lib.getExe writeDarwinBundle} \
        "$out" "${appName}" t3code-desktop t3code
    ''
    + ''
      mkdir --parents \
        "$out"/share/icons/hicolor/scalable/apps
      install --mode=444 ${desktopIcon} \
        "$out"/share/icons/t3code.png
      install --mode=444 assets/prod/logo.svg \
        "$out"/share/icons/hicolor/scalable/apps/t3code.svg

      runHook postInstall
    '';

    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      for shell in bash fish zsh; do
        installShellCompletion --cmd t3code --"$shell" <("$out/bin/t3code" --completions "$shell")
      done
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "t3code";
        desktopName = appName;
        comment = "Minimal web GUI for coding agents";
        exec = "t3code-desktop %U";
        terminal = false;
        icon = "t3code";
        startupWMClass = "t3code";
        categories = [ "Development" ];
      })
    ];

    passthru = {
      updateScript = nix-update-script {
        extraArgs = [
          "--flake"
          "--use-github-releases"
          "--version=unstable"
        ];
      };
    };

    meta = {
      description = "Minimal web GUI for coding agents";
      homepage = "https://t3.codes";
      downloadPage = "https://t3.codes/download";
      changelog = "https://github.com/pingdotgg/t3code/releases/tag/${finalAttrs.src.tag}";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [
        limwa
      ];
      mainProgram = "t3code-desktop";
      inherit (nodejs.meta) platforms;
    };
  }
)
