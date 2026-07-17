import { existsSync } from "node:fs";
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

function findAdb() {
  const sdkRoot = process.env.ANDROID_SDK_ROOT || process.env.ANDROID_HOME;
  const sdkAdb = sdkRoot ? join(sdkRoot, "platform-tools", "adb") : undefined;
  const defaultAdb = join(
    process.env.HOME || "",
    "Android",
    "Sdk",
    "platform-tools",
    "adb",
  );

  return (
    process.env.ADB_BIN ||
    Bun.which("adb") ||
    (sdkAdb && existsSync(sdkAdb) ? sdkAdb : undefined) ||
    (existsSync(defaultAdb) ? defaultAdb : undefined)
  );
}

function connectedAndroidDevice() {
  const adb = findAdb();
  if (!adb) {
    console.error(
      "adb was not found. Install Android SDK Platform-Tools or set ANDROID_SDK_ROOT.",
    );
    process.exit(1);
  }

  const result = Bun.spawnSync([adb, "devices", "-l"], {
    cwd: root,
    env: process.env,
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    console.error(result.stderr.toString().trim() || "adb could not list devices.");
    process.exit(result.exitCode || 1);
  }

  const devices = result.stdout
    .toString()
    .split(/\r?\n/)
    .slice(1)
    .map((line) => line.trim().split(/\s+/, 2))
    .filter(([serial]) => serial && !serial.startsWith("emulator-"));
  const readyDevices = devices.filter(([, state]) => state === "device");

  if (readyDevices.length === 0) {
    const unauthorized = devices.find(([, state]) => state === "unauthorized");
    const offline = devices.find(([, state]) => state === "offline");
    if (unauthorized) {
      console.error(
        `Android device ${unauthorized[0]} is unauthorized. Unlock it, accept the USB debugging prompt, then retry.`,
      );
    } else if (offline) {
      console.error(
        `Android device ${offline[0]} is offline. Reconnect its USB cable, then retry.`,
      );
    } else {
      console.error(
        "No USB Android device was found. Connect one with USB debugging enabled, unlock it, and accept the debugging prompt.",
      );
    }
    process.exit(1);
  }

  const requestedSerial = process.env.ANDROID_SERIAL;
  if (requestedSerial) {
    const requestedDevice = readyDevices.find(([serial]) => serial === requestedSerial);
    if (!requestedDevice) {
      console.error(
        `ANDROID_SERIAL=${requestedSerial} is not a connected, authorized USB device.`,
      );
      process.exit(1);
    }
    return requestedDevice[0];
  }

  if (readyDevices.length > 1) {
    console.error(
      `More than one USB Android device is connected (${readyDevices.map(([serial]) => serial).join(", ")}). Set ANDROID_SERIAL to choose one.`,
    );
    process.exit(1);
  }

  return readyDevices[0][0];
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
  case "android-device": {
    const serial = connectedAndroidDevice();
    console.log(`Using USB Android device ${serial}.`);
    await run([flutter, "run", "-d", serial, ...extraArguments], {
      cwd: mobile,
    });
    break;
  }
  case "mobile":
    await run([flutter, "run", ...extraArguments], { cwd: mobile });
    break;
  default:
    console.error(
      "Usage: bun scripts/flutter-dev.mjs <web|android|android-device|mobile> [flutter arguments]",
    );
    process.exit(1);
}
