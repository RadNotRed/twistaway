import { cp, mkdir, readdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const mobile = join(root, "apps", "mobile");
const artifacts = join(root, "artifacts");
const flutter = process.env.FLUTTER_BIN || "flutter";
const apiBaseUrl = process.env.TWISTAWAY_API_BASE_URL || "https://api.twistaway.app";
const target = process.argv[2];
const requestedMode = process.argv[3] || process.env.FLUTTER_BUILD_MODE || "release";
const validModes = new Set(["debug", "profile", "release"]);

if (!validModes.has(requestedMode)) {
  fail(`Unknown Flutter build mode: ${requestedMode}`);
}

async function run(args) {
  const command = [flutter, ...args];
  console.log(`\n› ${command.join(" ")}`);
  const processHandle = Bun.spawn(command, {
    cwd: mobile,
    env: process.env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await processHandle.exited;
  if (exitCode !== 0) {
    fail(`${command.join(" ")} exited with code ${exitCode}`, exitCode);
  }
}

function defineArgument() {
  return `--dart-define=TWISTAWAY_API_BASE_URL=${apiBaseUrl}`;
}

async function prepare() {
  await mkdir(artifacts, { recursive: true });
  await run(["pub", "get"]);
}

async function buildAndroid(mode = requestedMode) {
  await prepare();
  await run(["build", "apk", `--${mode}`, "--no-pub", defineArgument()]);
  const source = join(
    mobile,
    "build",
    "app",
    "outputs",
    "flutter-apk",
    `app-${mode}.apk`,
  );
  const destination = join(artifacts, `twistaway-${mode}.apk`);
  await copyRequired(source, destination);
  console.log(`\n✓ Android artifact: ${destination}`);
}

async function buildWeb() {
  await prepare();
  await run([
    "build",
    "web",
    "--release",
    "--no-pub",
    "--no-wasm-dry-run",
    defineArgument(),
  ]);
  const destination = join(artifacts, "web");
  await rm(destination, { recursive: true, force: true });
  await cp(join(mobile, "build", "web"), destination, { recursive: true });
  console.log(`\n✓ Web artifact: ${destination}`);
}

async function buildIos() {
  if (process.platform !== "darwin") {
    fail("iOS builds require macOS with Xcode and CocoaPods installed.");
  }
  await prepare();
  await run(["build", "ipa", "--release", "--no-pub", defineArgument()]);
  const ipaDirectory = join(mobile, "build", "ios", "ipa");
  const ipaName = (await readdir(ipaDirectory)).find((name) => name.endsWith(".ipa"));
  if (!ipaName) {
    fail(`Flutter did not create an IPA in ${ipaDirectory}`);
  }
  const destination = join(artifacts, "twistaway-release.ipa");
  await copyRequired(join(ipaDirectory, ipaName), destination);
  console.log(`\n✓ iOS artifact: ${destination}`);
}

async function copyRequired(source, destination) {
  if (!existsSync(source)) {
    fail(`Expected build output was not found: ${source}`);
  }
  await cp(source, destination);
}

function fail(message, exitCode = 1) {
  console.error(`\n✗ ${message}`);
  process.exit(exitCode);
}

switch (target) {
  case "android":
    await buildAndroid();
    break;
  case "web":
    await buildWeb();
    break;
  case "ios":
    await buildIos();
    break;
  case "all":
    await rm(artifacts, { recursive: true, force: true });
    await buildAndroid("release");
    await buildWeb();
    if (process.platform === "darwin") {
      await buildIos();
    } else {
      console.log("\n• Skipping iOS: IPA builds require macOS and Xcode.");
    }
    break;
  default:
    fail(
      "Usage: bun scripts/flutter-build.mjs <android|web|ios|all> [debug|profile|release]",
    );
}
