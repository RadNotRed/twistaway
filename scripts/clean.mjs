import { rm } from "node:fs/promises";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const paths = [
  "artifacts",
  "build",
  "site",
  "apps/api/dist",
  "apps/site/dist",
  "packages/shared/dist",
  "apps/mobile/build",
];

if (process.argv.includes("--all")) {
  paths.push(
    "node_modules",
    "apps/api/node_modules",
    "apps/site/node_modules",
    "packages/shared/node_modules",
    ".venv-docs",
    "apps/mobile/.dart_tool",
    "apps/mobile/android/.gradle",
    "apps/mobile/windows",
  );
}

for (const relativePath of paths) {
  const path = join(root, relativePath);
  await rm(path, { recursive: true, force: true });
  console.log(`✓ Removed ${relativePath}`);
}
