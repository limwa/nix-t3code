# BEGIN nix-t3code meta
# LAST SYNC: 1be7652e6e96aff0192d84259f96927df2259675
# DIFF: COMMIT=1be7652e6e96aff0192d84259f96927df2259675; SYNC="$(gh api repos/NixOS/nixpkgs/commits/master --jq '.sha')"; echo $SYNC; delta <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$COMMIT/pkgs/by-name/t3/t3code/unwrapped.nix") <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$SYNC/pkgs/by-name/t3/t3code/unwrapped.nix")
# END nix-t3code meta
{
  cctools,
  copyDesktopItems,
  electron_44,
  fetchFromGitHub,
  installShellFiles,
  lib,
  libicns,
  libsecret,
  makeBinaryWrapper,
  makeDesktopItem,
  nix-update-script,
  node-gyp,
  nodejs,
  pkg-config,
  python3,
  spdx-license-list-data,
  stdenv,
  testers,
  writeDarwinBundle,
  xcbuild,
  fetchPnpmDeps,
  pnpm_11,
  pnpmConfigHook,
  pnpmBuildHook,
  cacert,
}:

stdenv.mkDerivation (
  finalAttrs:
  let
    appName = "T3 Code (Alpha)";
    electron = electron_44;
    pnpm = pnpm_11;
    desktopIcon =
      if stdenv.hostPlatform.isDarwin then
        "assets/prod/black-macos-1024.png"
      else
        "assets/prod/black-universal-1024.png";

  in
  {
    pname = "t3code-unwrapped";
    version = "0.1.4";

    strictDeps = true;
    __structuredAttrs = true;

    src = fetchFromGitHub {
      owner = "pingdotgg";
      repo = "t3code";
      tag = "v${finalAttrs.version}";
      hash = "sha256-5Lqu6ITP8w0D3+TK5bXA7HWD0lFcbglzBCEuapo8qE8=";
    };

    patches = [ ./patches/desktop-resources-path.patch ];

    postPatch = ''
      substituteInPlace apps/web/vite.config.ts \
        --replace-fail 'const host = explicitHost || "localhost";' \
                       'const host = explicitHost || "127.0.0.1";'

      mkdir -p .generated/third-party-licenses/spdx/v3.28.0
      cp ${spdx-license-list-data.json}/json/details/*.json \
        .generated/third-party-licenses/spdx/v3.28.0
    '';

    nativeBuildInputs = [
      installShellFiles
      makeBinaryWrapper
      node-gyp
      nodejs
      python3
      pnpmConfigHook
      pnpmBuildHook
      pnpm
      cacert
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      copyDesktopItems
      pkg-config
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      cctools.libtool
      libicns
      writeDarwinBundle
      xcbuild
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libsecret ];

    pnpmWorkspaces = [
      # `...` suffix is used to also include other workspace packages that are
      # directly or indirectly depended on by the listed packages, such as
      # `@t3tools/contracts` and `@t3tools/shared`.
      "@t3tools/monorepo"
      "t3..."
      "@t3tools/desktop..."
      "@t3tools/scripts..."
    ];

    prePnpmInstall = ''
      pnpm config set fetchRetries 8
      pnpm config set networkConcurrency 3
      pnpm config set fetchWarnTimeoutMs 600000
      pnpm config set fetchMinSpeedKiBps 0
    '';

    pnpmDeps = fetchPnpmDeps {
      inherit pnpm;
      inherit (finalAttrs)
        pname
        version
        src
        pnpmWorkspaces
        prePnpmInstall
        ;

      fetcherVersion = 4;
      hash = "sha256-vBr3PN+qbbWOdrXPHs+35rM6fkdaNvBKzJo4MGvVImA=";
    };

    preBuild = ''
      # pnpm 11 otherwise detects the package version updates below as
      # dependency drift and runs another install, including lifecycle scripts.
      export pnpm_config_verify_deps_before_run=false

      node scripts/update-release-package-versions.ts ${finalAttrs.version}

      export npm_config_nodedir=${nodejs}
      export npm_config_build_from_source=true
      export ELECTRON_SKIP_BINARY_DOWNLOAD=1
      # Exclude the `@t3tools/monorepo` workspace from the pending rebuild since
      # `vp config` needs git
      pnpm rebuild --pending "''${pnpmInstallFlags[@]}" --filter '!@t3tools/monorepo'

      # Enable T3 Connect like official release builds. The example file only
      # holds public identifiers, and the build reads `.env` to bake them in.
      cp .env.example .env
    '';

    pnpmBuildScript = "build:desktop";

    postBuild = ''
      pnpm vp cache clean
    '';

    # Many dependencies vendors many prebuilt native artifacts for non-host
    # platforms, and some of those binaries are statically linked. Let fixup
    # handle wrappers, shebangs, and stripping, but skip patchelf on the
    # vendored tree.
    dontPatchELF = true;
    # The tmpdir audit hook also shells out to patchelf while scanning every
    # vendored ELF for leaked build paths. That produces spurious warnings on
    # some dependencies' static foreign-platform binaries.
    noAuditTmpdir = true;

    installPhase = ''
      runHook preInstall

      desktopWrapperArgs=()

      mkdir --parents "$out"/libexec/t3code/apps/desktop "$out"/libexec/t3code/apps/server
      # The bundles inline everything except a few packages that have to be
      # loaded from disk, so only ship those and their dependencies.
      node ${./scripts/install-runtime-deps.mjs} . "$out"/libexec/t3code
      chmod --recursive u+w "$out"/libexec/t3code/node_modules
      cp --recursive --no-preserve=mode apps/server/dist "$out"/libexec/t3code/apps/server
      cp --recursive --no-preserve=mode \
        apps/desktop/{package.json,dist-electron} \
        "$out"/libexec/t3code/apps/desktop

      # Electron runs on the repository root, which is laid out like upstream's
      # app.asar, so give it the runtime fields of the package.json that
      # upstream stages there (scripts/build-desktop-artifact.ts).
      node -e '
        const fs = require("node:fs");
        const [destination, version] = process.argv.slice(1);
        const { productName } = JSON.parse(fs.readFileSync("apps/desktop/package.json", "utf8"));
        const manifest = {
          name: "t3code",
          version,
          productName,
          private: true,
          main: "apps/desktop/dist-electron/boot.cjs",
        };
        fs.writeFileSync(destination, JSON.stringify(manifest, null, 2) + "\n");
      ' "$out"/libexec/t3code/package.json ${finalAttrs.version}

      # Same exclusions as upstream's release build: nothing reads source maps
      # or type declarations at runtime, and ConPTY is only used on Windows.
      find "$out"/libexec/t3code \( -name '*.map' -o -name '*.d.cts' \) -delete
      rm --recursive --force "$out"/libexec/t3code/node_modules/.pnpm/node-pty@*/node_modules/node-pty/third_party/conpty

      mkdir --parents "$out"/libexec/t3code/apps/desktop/prod-resources
      install --mode=444 ${desktopIcon} \
        "$out"/libexec/t3code/apps/desktop/prod-resources/icon.png
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      install -Dm755 \
        native/browser-secret/build/${stdenv.hostPlatform.node.arch}/t3-browser-secret \
        "$out"/libexec/t3code-resources/browser-secret/t3-browser-secret

      # Run in Electron's packaged mode. The shared Electron's resources
      # directory is its own, so point the app at ours instead.
      desktopWrapperArgs+=(
        --set ELECTRON_FORCE_IS_PACKAGED true
        --set T3CODE_DESKTOP_RESOURCES_PATH "$out"/libexec/t3code-resources
        --set T3CODE_DISABLE_AUTO_UPDATE 1
        --set-default T3CODE_DESKTOP_LAUNCHER_PATH "$out"/bin/t3code-desktop
      )
    ''
    + ''

      find "$out"/libexec/t3code -xtype l -delete

      makeWrapper ${lib.getExe nodejs} "$out"/bin/t3 \
        --add-flags "$out"/libexec/t3code/apps/server/dist/bin.mjs

      makeWrapper ${lib.getExe electron} "$out"/bin/t3code-desktop \
        --add-flags "$out"/libexec/t3code \
        --inherit-argv0 \
        "''${desktopWrapperArgs[@]}"
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      # node-pty tries to chmod this helper at runtime, but the Nix store is
      # immutable by then.
      find "$out"/libexec/t3code \
        -path '*/node-pty/prebuilds/darwin-*/spawn-helper' \
        -exec chmod 755 {} +

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
        "$out"/share/icons/hicolor/{1024x1024,scalable}/apps
      install --mode=444 ${desktopIcon} \
        "$out"/share/icons/hicolor/1024x1024/apps/t3code.png
      install --mode=444 assets/prod/logo.svg \
        "$out"/share/icons/hicolor/scalable/apps/t3code.svg

      runHook postInstall
    '';

    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      for shell in bash fish zsh; do
        installShellCompletion --cmd t3 --"$shell" <("$out/bin/t3" --completions "$shell")
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
        attrPath = "t3code.unwrapped";
        extraArgs = [
          "--flake"
          "--use-github-releases"
          "--version=stable"
          "--version-regex=v(\\d+\\.\\d+\\.\\d+)"
        ];
      };

      tests = lib.optionalAttrs stdenv.hostPlatform.isLinux {
        desktop = testers.runNixOSTest (import ./tests/desktop.nix { t3code = finalAttrs.finalPackage; });
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
