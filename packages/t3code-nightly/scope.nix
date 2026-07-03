{
  lib,
  newScope,
  pnpm_10_29_2,

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
}:

lib.makeScope newScope (self: {
  pnpm = pnpm_10_29_2;

  t3code-meta = import ./meta.nix;

  t3code-source = self.callPackage ./source.nix { };

  t3code-pnpm-workspaces = self.callPackage ./pnpm-workspaces.nix { };
  t3code-pnpm-deps = self.callPackage ./pnpm-deps.nix { };

  t3code-env = self.callPackage ./env.nix { };

  t3code = self.callPackage ./default.nix { };
})
