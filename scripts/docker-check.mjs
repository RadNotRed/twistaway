const secret = "local-compose-validation-only";
const env = {
  ...process.env,
  APP_ENCRYPTION_SECRET: secret,
  CLOUDFLARE_TUNNEL_TOKEN: "validation-placeholder",
};

async function run(command, options = {}) {
  console.log(`\n› ${command.join(" ")}`);
  const processHandle = Bun.spawn(command, {
    env,
    stdin: "inherit",
    stdout: options.capture ? "pipe" : "inherit",
    stderr: options.capture ? "pipe" : "inherit",
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    processHandle.exited,
    options.capture ? new Response(processHandle.stdout).text() : "",
    options.capture ? new Response(processHandle.stderr).text() : "",
  ]);
  if (exitCode !== 0 && !options.allowFailure) {
    if (stdout) console.error(stdout);
    if (stderr) console.error(stderr);
    process.exit(exitCode);
  }
  return { exitCode, stdout: stdout.trim(), stderr: stderr.trim() };
}

for (const command of [
  ["docker", "compose", "--profile", "tunnel", "config", "--quiet"],
  ["docker", "build", "--tag", "twistaway-api:check", "."],
]) {
  await run(command);
}

const containerName = `twistaway-api-check-${process.pid}`;

try {
  await run([
    "docker",
    "run",
    "--detach",
    "--name",
    containerName,
    "--read-only",
    "--tmpfs",
    "/tmp:size=64m,mode=1777",
    "--cap-drop",
    "ALL",
    "--security-opt",
    "no-new-privileges:true",
    "--env",
    `APP_ENCRYPTION_SECRET=${secret}`,
    "twistaway-api:check",
  ]);

  let healthy = false;
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const result = await run(
      ["docker", "inspect", "--format", "{{.State.Health.Status}}", containerName],
      { capture: true, allowFailure: true },
    );
    if (result.stdout === "healthy") {
      healthy = true;
      break;
    }
    if (result.stdout === "unhealthy" || result.exitCode !== 0) break;
    await Bun.sleep(1000);
  }

  if (!healthy) {
    await run(["docker", "logs", containerName], { allowFailure: true });
    console.error("\n✗ API container did not become healthy.");
    process.exitCode = 1;
  } else {
    console.log("\n✓ Compose, image build, and container health are valid.");
  }
} finally {
  await run(["docker", "rm", "--force", containerName], {
    capture: true,
    allowFailure: true,
  });
}
