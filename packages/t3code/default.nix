# BEGIN nix-t3code meta
# LAST SYNC: 1be7652e6e96aff0192d84259f96927df2259675
# DIFF: COMMIT=1be7652e6e96aff0192d84259f96927df2259675; SYNC="$(gh api repos/NixOS/nixpkgs/commits/master --jq '.sha')"; echo $SYNC; delta <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$COMMIT/pkgs/by-name/t3/t3code/package.nix") <(curl -fsSL "https://raw.githubusercontent.com/NixOS/nixpkgs/$SYNC/pkgs/by-name/t3/t3code/package.nix")
# END nix-t3code meta
{
  lib,
  stdenv,
  callPackage,
  symlinkJoin,
  makeBinaryWrapper,
  enableAzureDevOps ? false,
  azure-cli,
  azure-cli-extensions,
  enableBitbucket ? false,
  bitbucket-cli,
  enableClaude ? false,
  claude-code,
  enableCodex ? true,
  codex,
  enableCursor ? false,
  code-cursor,
  enableCursorCli ? false,
  cursor-cli,
  enableGitHub ? true,
  gh,
  enableGit ? true,
  git,
  enableGitLab ? false,
  glab,
  enableJujutsu ? false,
  jujutsu,
  enableOpencode ? false,
  opencode,
  enableCloudflared ? true,
  cloudflared,
  desktop-file-utils,
  xdg-utils,
  enableResourceMonitor ? true,
  t3code-unwrapped ? callPackage ./unwrapped.nix { },
  t3code-resource-monitor ? callPackage ./resource-monitor.nix { inherit t3code-unwrapped; },
}:

let
  runtimePackages =
    lib.optionals enableAzureDevOps [
      (azure-cli.withExtensions [ azure-cli-extensions.azure-devops ])
    ]
    ++ lib.optionals enableBitbucket [ bitbucket-cli ]
    ++ lib.optionals enableClaude [ claude-code ]
    ++ lib.optionals enableCodex [ codex ]
    ++ lib.optionals enableCursor [ code-cursor ]
    ++ lib.optionals enableCursorCli [ cursor-cli ]
    ++ lib.optionals enableGitHub [ gh ]
    ++ lib.optionals enableGit [ git ]
    ++ lib.optionals enableGitLab [ glab ]
    ++ lib.optionals enableJujutsu [ jujutsu ]
    ++ lib.optionals enableOpencode [ opencode ]
    ++ lib.optionals enableCloudflared [ cloudflared ];

  # The resource monitor sidecar is a separate Rust binary that upstream only
  # builds in its electron-builder pipeline, not in `build:desktop`. The server
  # checks this variable before any bundled location, and the desktop app's
  # server child inherits it.
  wrapperArgs =
    lib.optionals (runtimePackages != [ ]) [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath runtimePackages)
    ]
    ++ lib.optionals enableResourceMonitor [
      "--set-default"
      "T3CODE_RESOURCE_MONITOR_PATH"
      (lib.getExe t3code-resource-monitor)
    ]
    # t3code:// links should go through this wrapper and its PATH additions
    # rather than the unwrapped launcher. This takes priority over the
    # unwrapped wrapper's default since it runs first.
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      "--set"
      "T3CODE_DESKTOP_LAUNCHER_PATH"
      "${placeholder "out"}/bin/t3code-desktop"
    ];

  # Electron shells out to these to register the t3code:// scheme handler
  # (xdg-mime) and refresh the desktop database (update-desktop-database).
  # Only the desktop launcher needs them.
  desktopRuntimePackages = lib.optionals stdenv.hostPlatform.isLinux [
    desktop-file-utils
    xdg-utils
  ];

  desktopWrapperArgs = lib.optionals (desktopRuntimePackages != [ ]) [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath desktopRuntimePackages)
  ];

in
symlinkJoin {
  pname = "t3code";
  inherit (t3code-unwrapped) version;
  __structuredAttrs = true;
  strictDeps = true;

  paths = [ t3code-unwrapped ];

  nativeBuildInputs = [ makeBinaryWrapper ];

  postBuild = lib.optionalString (wrapperArgs != [ ]) ''
    for program in "$out/bin"/*; do
      extraArgs=()
      if [ "$(basename "$program")" = t3code-desktop ]; then
        extraArgs+=(${lib.escapeShellArgs desktopWrapperArgs})
      fi
      wrapProgram "$program" ${lib.escapeShellArgs wrapperArgs} "''${extraArgs[@]}"
    done
  '';

  passthru = {
    unwrapped = t3code-unwrapped;
    resourceMonitor = t3code-resource-monitor;
  }
  // t3code-unwrapped.passthru;

  meta = {
    # Manually inherit so that pos works
    inherit (t3code-unwrapped.meta)
      description
      homepage
      downloadPage
      changelog
      license
      maintainers
      mainProgram
      platforms
      ;
  };
}
