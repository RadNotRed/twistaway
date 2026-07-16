import express from "express";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { sendOptimizedJson } from "../src/response.js";

describe("optimized JSON responses", () => {
  it("compresses large payloads and supports conditional requests", async () => {
    const app = express();
    app.get("/payload", async (req, res) => {
      await sendOptimizedJson(req, res, { value: "x".repeat(8_000) }, 60);
    });

    const compressed = await request(app)
      .get("/payload")
      .set("Accept-Encoding", "br")
      .expect(200);
    expect(compressed.headers["content-encoding"]).toBe("br");
    expect(compressed.headers.etag).toEqual(expect.any(String));
    expect(compressed.headers["cache-control"]).toBe("private, max-age=60");

    await request(app)
      .get("/payload")
      .set("If-None-Match", compressed.headers.etag)
      .expect(304);
  });
});
