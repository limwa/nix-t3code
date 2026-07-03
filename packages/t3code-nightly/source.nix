{
  t3code-meta,
  fetchFromGitHub,
}:

fetchFromGitHub {
  owner = "pingdotgg";
  repo = "t3code";
  tag = "v${t3code-meta.version}";
  hash = "sha256-QzONYA2VPkkaWJSkdjPRgQvbe0Uezt47NdRxOUoZajQ=";
}
