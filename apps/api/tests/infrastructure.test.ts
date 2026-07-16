import { describe, expect, it } from "vitest";
import { ExpiringLruCache } from "../src/cache.js";
import { ConcurrencyGate, ConcurrencyLimitError } from "../src/concurrency.js";

describe("API resource bounds", () => {
  it("evicts cached responses to stay within the memory budget", () => {
    const cache = new ExpiringLruCache<string>(10, 60_000, 3);
    cache.set("first", "one", 60_000, 2);
    cache.set("second", "two", 60_000, 2);

    expect(cache.get("first")).toBeUndefined();
    expect(cache.get("second")).toBe("two");
  });

  it("rejects excess provider work when the queue is full", async () => {
    const gate = new ConcurrencyGate(1, 0);
    let release!: () => void;
    const blocked = gate.run(
      () =>
        new Promise<void>((resolve) => {
          release = resolve;
        }),
    );

    await expect(gate.run(async () => undefined)).rejects.toBeInstanceOf(
      ConcurrencyLimitError,
    );
    release();
    await blocked;
  });
});
