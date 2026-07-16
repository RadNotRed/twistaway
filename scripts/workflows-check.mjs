import { resolve } from "node:path";

const root = resolve(import.meta.dir, "..");
const image = "rhysd/actionlint:1.7.12";
const command = [
  "docker",
  "run",
  "--rm",
  "--volume",
  `${root}:/repo`,
  "--workdir",
  "/repo",
  image,
];

console.log(`\n› ${command.join(" ")}`);
const processHandle = Bun.spawn(command, {
  stdin: "inherit",
  stdout: "inherit",
  stderr: "inherit",
});
process.exit(await processHandle.exited);
