export class ExpiringLruCache<T> {
  private readonly entries = new Map<
    string,
    { expiresAt: number; value: T; weight: number }
  >();
  private totalWeight = 0;

  constructor(
    private readonly maximumEntries: number,
    private readonly timeToLiveMs: number,
    private readonly maximumWeight = Number.POSITIVE_INFINITY,
  ) {
    if (maximumEntries < 1 || timeToLiveMs < 1 || maximumWeight < 1) {
      throw new Error("cache limits and TTL must be positive");
    }
  }

  get(key: string): T | undefined {
    const entry = this.entries.get(key);
    if (!entry) {
      return undefined;
    }

    this.remove(key);
    if (entry.expiresAt <= Date.now()) {
      return undefined;
    }

    this.entries.set(key, entry);
    this.totalWeight += entry.weight;
    return entry.value;
  }

  set(key: string, value: T, timeToLiveMs = this.timeToLiveMs, weight = 1): void {
    if (!Number.isFinite(weight) || weight < 0 || weight > this.maximumWeight) {
      return;
    }
    this.removeExpired();
    this.remove(key);
    while (
      this.entries.size >= this.maximumEntries ||
      this.totalWeight + weight > this.maximumWeight
    ) {
      const oldestKey = this.entries.keys().next().value;
      if (oldestKey === undefined) {
        break;
      }
      this.remove(oldestKey);
    }

    this.entries.set(key, {
      expiresAt: Date.now() + Math.max(1, timeToLiveMs),
      value,
      weight,
    });
    this.totalWeight += weight;
  }

  delete(key: string): void {
    this.remove(key);
  }

  private removeExpired(): void {
    const now = Date.now();
    for (const [key, entry] of this.entries) {
      if (entry.expiresAt <= now) {
        this.remove(key);
      }
    }
  }

  private remove(key: string): void {
    const entry = this.entries.get(key);
    if (entry) {
      this.totalWeight -= entry.weight;
      this.entries.delete(key);
    }
  }
}
