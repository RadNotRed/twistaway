import argon2 from "argon2";
import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { EncryptedPayload } from "@motoplanner/shared";

const AAD = Buffer.from("motoplanner-api-v1");

export async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, {
    type: argon2.argon2id,
    memoryCost: 65536,
    timeCost: 3,
    parallelism: 1
  });
}

export async function verifyPassword(hash: string, password: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, password);
  } catch {
    return false;
  }
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function constantTimeStringEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}

export function randomToken(): string {
  return randomBytes(32).toString("base64url");
}

export function serverKey(secret: string): Buffer {
  return createHash("sha256").update(secret).digest();
}

export function sealJsonWithKey(value: unknown, key: Buffer, aad = AAD): EncryptedPayload {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(aad);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(value), "utf8"),
    cipher.final()
  ]);

  return {
    version: 1,
    algorithm: "AES-256-GCM",
    nonce: nonce.toString("base64url"),
    ciphertext: ciphertext.toString("base64url"),
    tag: cipher.getAuthTag().toString("base64url"),
    aad: aad.toString("base64url"),
    keyDerivation: "argon2id-hkdf-sha256"
  };
}

export function openJsonWithKey<T>(payload: EncryptedPayload, key: Buffer, aad = AAD): T {
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(payload.nonce, "base64url")
  );
  decipher.setAAD(aad);
  decipher.setAuthTag(Buffer.from(payload.tag, "base64url"));

  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(payload.ciphertext, "base64url")),
    decipher.final()
  ]);

  return JSON.parse(plaintext.toString("utf8")) as T;
}

export function wrapAuditKey(auditKeyBase64: string, secret: string): EncryptedPayload {
  const raw = Buffer.from(auditKeyBase64, "base64");
  if (raw.length !== 32) {
    throw new Error("auditKey must be a base64-encoded 32-byte key");
  }

  return sealJsonWithKey({ key: auditKeyBase64 }, serverKey(secret));
}

export function unwrapAuditKey(envelopeJson: string | null | undefined, secret: string): Buffer | null {
  if (!envelopeJson) {
    return null;
  }

  const opened = openJsonWithKey<{ key: string }>(JSON.parse(envelopeJson), serverKey(secret));
  return Buffer.from(opened.key, "base64");
}
