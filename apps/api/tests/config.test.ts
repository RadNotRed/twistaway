import { afterEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";

describe("production configuration", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("requires an encryption secret", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("APP_ENCRYPTION_SECRET", "");
    vi.stubEnv("CORS_ORIGINS", "https://twistaway.app");

    expect(() => loadConfig()).toThrow("APP_ENCRYPTION_SECRET is required");
  });

  it("requires explicit production browser origins", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("APP_ENCRYPTION_SECRET", "a".repeat(32));
    vi.stubEnv("CORS_ORIGINS", "");

    expect(() => loadConfig()).toThrow("CORS_ORIGINS must list");
  });

  it("loads a valid hardened production configuration", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("APP_ENCRYPTION_SECRET", "a".repeat(32));
    vi.stubEnv("CORS_ORIGINS", "https://twistaway.app");
    vi.stubEnv("TRUST_PROXY", "true");

    expect(loadConfig()).toMatchObject({
      environment: "production",
      corsOrigins: ["https://twistaway.app"],
      trustProxy: true,
      bodyLimitBytes: 524_288,
      auditRetentionDays: 90,
    });
  });
});
