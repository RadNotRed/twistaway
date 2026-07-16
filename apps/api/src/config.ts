import { randomBytes } from "node:crypto";

export interface ApiConfig {
  databasePath: string;
  port: number;
  serverSecret: string;
  sessionDays: number;
  corsOrigins?: string[];
  trustProxy?: boolean;
  environment?: "development" | "test" | "production";
  bodyLimitBytes?: number;
  globalRateLimit?: { maximum: number; windowMs: number };
  authRateLimit?: { maximum: number; windowMs: number };
  integrationRateLimit?: { maximum: number; windowMs: number };
  sessionCacheTtlMs?: number;
  searchCacheEntries?: number;
  searchCacheTtlMs?: number;
  searchCacheMaxBytes?: number;
  routeCacheEntries?: number;
  routeCacheTtlMs?: number;
  routeCacheMaxBytes?: number;
  upstreamTimeoutMs?: number;
  upstreamConcurrency?: number;
  upstreamQueueSize?: number;
  auditRetentionDays?: number;
}

function integerEnvironment(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const raw = process.env[name];
  const value = raw === undefined ? fallback : Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be an integer from ${minimum} to ${maximum}`);
  }
  return value;
}

function corsOrigins(): string[] {
  return (process.env.CORS_ORIGINS ?? "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean)
    .map((origin) => {
      const parsed = new URL(origin);
      if (
        !["http:", "https:"].includes(parsed.protocol) ||
        parsed.origin !== origin ||
        origin === "*"
      ) {
        throw new Error(`invalid CORS origin: ${origin}`);
      }
      return origin;
    });
}

export function loadConfig(): ApiConfig {
  const environment =
    process.env.NODE_ENV === "production"
      ? "production"
      : process.env.NODE_ENV === "test"
        ? "test"
        : "development";
  const configuredSecret = process.env.APP_ENCRYPTION_SECRET;
  if (environment === "production" && !configuredSecret) {
    throw new Error("APP_ENCRYPTION_SECRET is required in production");
  }
  if (
    environment === "production" &&
    Buffer.byteLength(configuredSecret ?? "", "utf8") < 32
  ) {
    throw new Error("APP_ENCRYPTION_SECRET must be at least 32 bytes in production");
  }
  const serverSecret =
    configuredSecret ?? "dev-only-" + randomBytes(32).toString("base64url");
  const configuredCorsOrigins = corsOrigins();
  if (environment === "production" && configuredCorsOrigins.length === 0) {
    throw new Error("CORS_ORIGINS must list production browser origins");
  }

  return {
    databasePath: process.env.DB_PATH ?? "twistaway.sqlite",
    port: integerEnvironment("PORT", 4180, 1, 65_535),
    serverSecret,
    sessionDays: integerEnvironment("SESSION_DAYS", 30, 1, 365),
    corsOrigins: configuredCorsOrigins,
    trustProxy: ["1", "true", "yes"].includes(
      (process.env.TRUST_PROXY ?? "").toLowerCase(),
    ),
    environment,
    bodyLimitBytes: integerEnvironment(
      "API_BODY_LIMIT_BYTES",
      524_288,
      16_384,
      2_097_152,
    ),
    globalRateLimit: {
      maximum: integerEnvironment("RATE_LIMIT_GLOBAL_MAX", 300, 10, 100_000),
      windowMs: 60_000,
    },
    authRateLimit: {
      maximum: integerEnvironment("RATE_LIMIT_AUTH_MAX", 10, 1, 1_000),
      windowMs: 15 * 60_000,
    },
    integrationRateLimit: {
      maximum: integerEnvironment("RATE_LIMIT_INTEGRATIONS_MAX", 90, 1, 10_000),
      windowMs: 60_000,
    },
    sessionCacheTtlMs: integerEnvironment(
      "SESSION_CACHE_TTL_MS",
      30_000,
      1_000,
      300_000,
    ),
    searchCacheEntries: integerEnvironment("SEARCH_CACHE_ENTRIES", 512, 1, 100_000),
    searchCacheTtlMs: integerEnvironment(
      "SEARCH_CACHE_TTL_MS",
      300_000,
      1_000,
      86_400_000,
    ),
    searchCacheMaxBytes: integerEnvironment(
      "SEARCH_CACHE_MAX_BYTES",
      16 * 1024 * 1024,
      1024 * 1024,
      1024 * 1024 * 1024,
    ),
    routeCacheEntries: integerEnvironment("ROUTE_CACHE_ENTRIES", 256, 1, 100_000),
    routeCacheTtlMs: integerEnvironment(
      "ROUTE_CACHE_TTL_MS",
      600_000,
      1_000,
      86_400_000,
    ),
    routeCacheMaxBytes: integerEnvironment(
      "ROUTE_CACHE_MAX_BYTES",
      64 * 1024 * 1024,
      1024 * 1024,
      2 * 1024 * 1024 * 1024,
    ),
    upstreamTimeoutMs: integerEnvironment("UPSTREAM_TIMEOUT_MS", 8_000, 1_000, 30_000),
    upstreamConcurrency: integerEnvironment("UPSTREAM_CONCURRENCY", 32, 1, 1_000),
    upstreamQueueSize: integerEnvironment("UPSTREAM_QUEUE_SIZE", 64, 0, 10_000),
    auditRetentionDays: integerEnvironment("AUDIT_RETENTION_DAYS", 90, 1, 3_650),
  };
}
