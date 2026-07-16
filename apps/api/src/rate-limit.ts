import type { NextFunction, Request, RequestHandler, Response } from "express";

export interface RateLimitPolicy {
  maximum: number;
  windowMs: number;
}

interface Bucket {
  lastSeenAt: number;
  tokens: number;
}

export class MemoryTokenBucket {
  private readonly buckets = new Map<string, Bucket>();
  private operations = 0;

  constructor(
    private readonly policy: RateLimitPolicy,
    private readonly maximumKeys = 50_000,
  ) {
    if (
      !Number.isFinite(policy.maximum) ||
      policy.maximum < 1 ||
      !Number.isFinite(policy.windowMs) ||
      policy.windowMs < 1 ||
      maximumKeys < 1
    ) {
      throw new Error("rate-limit policy must use positive limits");
    }
  }

  consume(key: string): {
    allowed: boolean;
    limit: number;
    remaining: number;
    retryAfterSeconds: number;
  } {
    const now = Date.now();
    const refillPerMs = this.policy.maximum / this.policy.windowMs;
    const existing = this.buckets.get(key);
    const bucket = existing ?? {
      lastSeenAt: now,
      tokens: this.policy.maximum,
    };
    bucket.tokens = Math.min(
      this.policy.maximum,
      bucket.tokens + (now - bucket.lastSeenAt) * refillPerMs,
    );
    bucket.lastSeenAt = now;

    const allowed = bucket.tokens >= 1;
    if (allowed) {
      bucket.tokens -= 1;
    }
    this.buckets.delete(key);
    this.buckets.set(key, bucket);
    this.maintain(now);

    return {
      allowed,
      limit: this.policy.maximum,
      remaining: Math.max(0, Math.floor(bucket.tokens)),
      retryAfterSeconds: allowed
        ? 0
        : Math.max(1, Math.ceil((1 - bucket.tokens) / refillPerMs / 1000)),
    };
  }

  private maintain(now: number): void {
    this.operations += 1;
    if (this.operations % 1_000 === 0) {
      for (const [key, bucket] of this.buckets) {
        if (now - bucket.lastSeenAt >= this.policy.windowMs) {
          this.buckets.delete(key);
        }
      }
    }

    while (this.buckets.size > this.maximumKeys) {
      const oldestKey = this.buckets.keys().next().value;
      if (oldestKey === undefined) {
        break;
      }
      this.buckets.delete(oldestKey);
    }
  }
}

export function rateLimit(
  limiter: MemoryTokenBucket,
  key: (req: Request) => string,
  skip: (req: Request) => boolean = () => false,
): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    if (req.method === "OPTIONS" || skip(req)) {
      next();
      return;
    }
    const result = limiter.consume(key(req));
    res.setHeader("RateLimit-Limit", result.limit);
    res.setHeader("RateLimit-Remaining", result.remaining);
    if (result.allowed) {
      next();
      return;
    }

    res.setHeader("Retry-After", result.retryAfterSeconds);
    res.setHeader("Cache-Control", "no-store");
    res.status(429).json({ error: "too many requests; try again later" });
  };
}
