import { join, resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const mobile = join(root, "apps", "mobile");
const flutter = process.env.FLUTTER_BIN || "flutter";
const target = process.argv[2];
const extraArguments = process.argv.slice(3);

async function run(command, options = {}) {
  console.log(`\n› ${command.join(" ")}`);
  const processHandle = Bun.spawn(command, {
    cwd: options.cwd || root,
    env: process.env,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  });
  const exitCode = await processHandle.exited;
  if (exitCode !== 0) process.exit(exitCode);
}

async function openBrowserWhenReady(url) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    try {
      const response = await fetch(url);
      if (response.ok) {
        const opener =
          process.platform === "win32"
            ? ["cmd", "/c", "start", "", url]
            : process.platform === "darwin"
              ? ["open", url]
              : ["xdg-open", url];
        Bun.spawn(opener, { stdout: "ignore", stderr: "ignore" });
        return;
      }
    } catch {
      // The Flutter development server is still starting.
    }
    await Bun.sleep(500);
  }
}

switch (target) {
  case "web": {
    const host = process.env.FLUTTER_WEB_HOST || "127.0.0.1";
    const port = process.env.FLUTTER_WEB_PORT || "8080";
    const url = `http://${host}:${port}`;
    try {
      const response = await fetch(url);
      if (response.ok) {
        console.error(`A web session is already running at ${url}.`);
        process.exit(1);
      }
    } catch {
      // Expected when the development server is not running yet.
    }
    await run([flutter, "pub", "get"], { cwd: mobile });
    void openBrowserWhenReady(url);
    await run(
      [
        flutter,
        "run",
        "-d",
        "web-server",
        "--web-hostname",
        host,
        "--web-port",
        port,
        ...extraArguments,
      ],
      { cwd: mobile },
    );
    break;
  }
  case "android":
    await run([join(root, "scripts", "launch-android-emulator.sh")]);
    await run([flutter, "run", "-d", "emulator-5554", ...extraArguments], {
      cwd: mobile,
    });
    break;
  case "mobile":
    await run([flutter, "run", ...extraArguments], { cwd: mobile });
    break;
  default:
    console.error(
      "Usage: bun scripts/flutter-dev.mjs <web|android|mobile> [flutter arguments]",
    );
    process.exit(1);
}
