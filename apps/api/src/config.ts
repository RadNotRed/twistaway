import { randomBytes } from "node:crypto";

export interface ApiConfig {
  databasePath: string;
  port: number;
  serverSecret: string;
  sessionDays: number;
  corsOrigins?: string[];
  trustProxy?: boolean;
}

export function loadConfig(): ApiConfig {
  const serverSecret =
    process.env.APP_ENCRYPTION_SECRET ??
    "dev-only-change-me-" + randomBytes(16).toString("hex");

  return {
    databasePath: process.env.DB_PATH ?? "twistaway.sqlite",
    port: Number(process.env.PORT ?? 4180),
    serverSecret,
    sessionDays: Number(process.env.SESSION_DAYS ?? 30),
    corsOrigins: (process.env.CORS_ORIGINS ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
    trustProxy: ["1", "true", "yes"].includes(
      (process.env.TRUST_PROXY ?? "").toLowerCase(),
    ),
  };
}
