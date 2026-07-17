import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const virtualEnvironment = join(root, ".venv-docs");
const python =
  process.platform === "win32"
    ? join(virtualEnvironment, "Scripts", "python.exe")
    : join(virtualEnvironment, "bin", "python");
const action = process.argv[2];

async function run(command) {
  console.log(`\n› ${command.join(" ")}`);
  const processHandle = Bun.spawn(command, {
    cwd: root,
    env: process.env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await processHandle.exited;
  if (exitCode !== 0) process.exit(exitCode);
}

async function ensureEnvironment() {
  if (!existsSync(python)) {
    const systemPython =
      process.env.PYTHON || (process.platform === "win32" ? "python" : "python3");
    await run([systemPython, "-m", "venv", virtualEnvironment]);
    await run([
      python,
      "-m",
      "pip",
      "install",
      "--requirement",
      "docs/requirements.txt",
    ]);
  }
}

switch (action) {
  case "install":
    await ensureEnvironment();
    await run([
      python,
      "-m",
      "pip",
      "install",
      "--upgrade",
      "--requirement",
      "docs/requirements.txt",
    ]);
    break;
  case "serve":
    await ensureEnvironment();
    await run([python, "-m", "mkdocs", "serve"]);
    break;
  case "build":
    await ensureEnvironment();
    await run([python, "-m", "mkdocs", "build", "--strict"]);
    break;
  default:
    console.error("Usage: bun scripts/docs.mjs <install|serve|build>");
    process.exit(1);
}
