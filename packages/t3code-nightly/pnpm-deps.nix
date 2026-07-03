{
  pnpm,
  fetchPnpmDeps,
  t3code-meta,
  t3code-source,
  t3code-pnpm-workspaces,
}:

fetchPnpmDeps {
  inherit pnpm;
  inherit (t3code-meta)
    pname
    version
    ;

  src = t3code-source;
  pnpmWorkspaces = t3code-pnpm-workspaces;

  fetcherVersion = 4;
  hash = "sha256-ySy4xElA3kskFkiP1BsAkbSpt7rpK6VuoO0ZmSbTq0Y=";
}
