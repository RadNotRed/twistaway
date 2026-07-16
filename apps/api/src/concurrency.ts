export class ConcurrencyLimitError extends Error {}

export class ConcurrencyGate {
  private active = 0;
  private readonly waiting: Array<() => void> = [];

  constructor(
    private readonly maximumConcurrent: number,
    private readonly maximumWaiting: number,
  ) {
    if (maximumConcurrent < 1 || maximumWaiting < 0) {
      throw new Error("concurrency limits must be valid");
    }
  }

  async run<T>(task: () => Promise<T>): Promise<T> {
    if (this.active < this.maximumConcurrent) {
      this.active += 1;
    } else {
      if (this.waiting.length >= this.maximumWaiting) {
        throw new ConcurrencyLimitError("upstream capacity is temporarily exhausted");
      }
      await new Promise<void>((resolve) => this.waiting.push(resolve));
    }

    try {
      return await task();
    } finally {
      const next = this.waiting.shift();
      if (next) {
        next();
      } else {
        this.active -= 1;
      }
    }
  }
}
