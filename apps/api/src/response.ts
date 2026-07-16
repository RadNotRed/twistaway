import { createHash } from "node:crypto";
import { promisify } from "node:util";
import { brotliCompress, constants, gzip } from "node:zlib";
import type { Request, Response } from "express";

const brotli = promisify(brotliCompress);
const gzipAsync = promisify(gzip);

export async function sendOptimizedJson(
  req: Request,
  res: Response,
  value: unknown,
  maxAgeSeconds: number,
): Promise<void> {
  const body = Buffer.from(JSON.stringify(value));
  const etag = `W/"${createHash("sha256").update(body).digest("base64url")}"`;

  res.setHeader("Cache-Control", `private, max-age=${maxAgeSeconds}`);
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("ETag", etag);
  res.vary("Accept-Encoding");

  const validators = req.header("if-none-match")?.split(/\s*,\s*/);
  if (validators?.includes(etag) || validators?.includes("*")) {
    res.status(304).end();
    return;
  }

  let encoded = body;
  if (body.length >= 1_024) {
    const accepted = req.acceptsEncodings("br", "gzip");
    if (accepted === "br") {
      encoded = await brotli(body, {
        params: {
          [constants.BROTLI_PARAM_QUALITY]: 4,
        },
      });
      res.setHeader("Content-Encoding", "br");
    } else if (accepted === "gzip") {
      encoded = await gzipAsync(body, { level: 6 });
      res.setHeader("Content-Encoding", "gzip");
    }
  }

  res.setHeader("Content-Length", encoded.length);
  res.end(encoded);
}
