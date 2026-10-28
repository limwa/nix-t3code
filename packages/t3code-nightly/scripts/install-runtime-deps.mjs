// Installs only the runtime dependencies of the server and desktop bundles.
//
// Upstream's release build (scripts/build-desktop-artifact.ts) inlines every
// dependency into the bundles except for a small set of packages that Node has
// to load from disk, and then installs just those with `pnpm install --prod`.
// That install needs the network, so instead we reuse the workspace's
// node_modules and copy the dependency closure of those same packages, keeping
// pnpm's isolated layout intact.
//
// Usage: node install-runtime-deps.mjs <workspace root> <destination root>

import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [workspaceRoot, destinationRoot] = process.argv.slice(2).map((p) => path.resolve(p));
if (!workspaceRoot || !destinationRoot) {
  console.error("usage: install-runtime-deps.mjs <workspace root> <destination root>");
  process.exit(1);
}

const importUpstream = (file) =>
  import(pathToFileURL(path.join(workspaceRoot, "scripts/lib", file)).href);

const { isRuntimeExternalCliDependency } = await importUpstream("cli-external-packages.ts");
const { isDesktopRuntimeExternalDependency } = await importUpstream(
  "desktop-external-packages.ts",
);

const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8"));

const workspaces = [
  { directory: "apps/server", isRuntimeDependency: isRuntimeExternalCliDependency },
  { directory: "apps/desktop", isRuntimeDependency: isDesktopRuntimeExternalDependency },
];

// The store directory of a package, e.g. `node_modules/.pnpm/<name>@<version>`.
const storeRoot = fs.realpathSync(path.join(workspaceRoot, "node_modules/.pnpm"));
const storeEntryOf = (packageDirectory) => {
  const relative = path.relative(storeRoot, packageDirectory);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${packageDirectory} is not inside ${storeRoot}`);
  }
  return relative.split(path.sep)[0];
};

// Peers that packages only declare for their type definitions and never load,
// such as electron-webauthn's peer dependency on TypeScript (~30 MB).
const typeOnlyPeers = new Set(["typescript"]);

const storeEntries = new Set();
const visited = new Set();
const roots = new Map();

// Follows dependencies the way Node resolves them in pnpm's layout: each
// package's dependencies are symlinked next to it in the enclosing
// node_modules directory.
const visit = (nodeModulesDirectory, name, optional) => {
  const link = path.join(nodeModulesDirectory, name);
  if (!fs.existsSync(link)) {
    if (optional) return undefined;
    throw new Error(`Missing required dependency ${name} in ${nodeModulesDirectory}`);
  }

  const packageDirectory = fs.realpathSync(link);
  if (visited.has(packageDirectory)) return packageDirectory;
  visited.add(packageDirectory);
  storeEntries.add(storeEntryOf(packageDirectory));

  const manifest = readJson(path.join(packageDirectory, "package.json"));
  const siblings = path.join(packageDirectory, ...name.split("/").map(() => ".."));
  const optionalPeers = new Set(
    Object.entries(manifest.peerDependenciesMeta ?? {})
      .filter(([, meta]) => meta?.optional)
      .map(([peer]) => peer),
  );

  for (const dependency of Object.keys(manifest.dependencies ?? {})) {
    visit(siblings, dependency, false);
  }
  for (const dependency of Object.keys(manifest.optionalDependencies ?? {})) {
    visit(siblings, dependency, true);
  }
  for (const dependency of Object.keys(manifest.peerDependencies ?? {})) {
    if (typeOnlyPeers.has(dependency)) continue;
    visit(siblings, dependency, optionalPeers.has(dependency));
  }

  return packageDirectory;
};

for (const { directory, isRuntimeDependency } of workspaces) {
  const manifest = readJson(path.join(workspaceRoot, directory, "package.json"));
  for (const name of Object.keys(manifest.dependencies ?? {})) {
    if (!isRuntimeDependency(name)) continue;
    const packageDirectory = visit(path.join(workspaceRoot, directory, "node_modules"), name, false);
    if (roots.has(name) && roots.get(name) !== packageDirectory) {
      throw new Error(`${name} resolves to different packages across workspaces`);
    }
    roots.set(name, packageDirectory);
  }
}

const destinationNodeModules = path.join(destinationRoot, "node_modules");
const destinationStore = path.join(destinationNodeModules, ".pnpm");
fs.mkdirSync(destinationStore, { recursive: true });

for (const entry of [...storeEntries].sort()) {
  fs.cpSync(path.join(storeRoot, entry), path.join(destinationStore, entry), {
    recursive: true,
    verbatimSymlinks: true,
  });
}

// Both bundles resolve their externals by walking up to this directory.
for (const [name, packageDirectory] of [...roots].sort(([a], [b]) => a.localeCompare(b))) {
  const link = path.join(destinationNodeModules, name);
  const target = path.join(destinationStore, path.relative(storeRoot, packageDirectory));
  fs.mkdirSync(path.dirname(link), { recursive: true });
  fs.symlinkSync(path.relative(path.dirname(link), target), link);
}

console.log(
  `Installed ${roots.size} runtime dependencies (${storeEntries.size} packages): ${[...roots.keys()].sort().join(", ")}`,
);
