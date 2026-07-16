import { rm } from "node:fs/promises";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const paths = [
  "artifacts",
  "site",
  "apps/api/dist",
  "apps/web/dist",
  "packages/shared/dist",
  "apps/mobile/build",
].map((path) => join(root, path));

for (const path of paths) {
  await rm(path, { recursive: true, force: true });
  console.log(`✓ Removed ${path}`);
}
