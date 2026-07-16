import { z } from "zod";

function decodedLength(value: string): number {
  try {
    return Buffer.from(value, "base64url").length;
  } catch {
    return -1;
  }
}

const base64Url = z.string().regex(/^[A-Za-z0-9_-]+$/);
const auditKey = z
  .string()
  .regex(/^[A-Za-z0-9+/]{43}=$/, "invalid audit key")
  .refine((value) => Buffer.from(value, "base64").length === 32, "invalid audit key");

export const encryptedPayloadSchema = z
  .object({
    version: z.literal(1),
    algorithm: z.literal("AES-256-GCM"),
    nonce: base64Url.refine((value) => decodedLength(value) === 12, "invalid nonce"),
    ciphertext: base64Url.max(900_000),
    tag: base64Url.refine((value) => decodedLength(value) === 16, "invalid tag"),
    aad: base64Url.max(512).optional(),
    keyDerivation: z.literal("argon2id-hkdf-sha256"),
  })
  .strict();

export const registerSchema = z
  .object({
    username: z
      .string()
      .min(3)
      .max(40)
      .regex(/^[a-zA-Z0-9_.-]+$/),
    email: z
      .email()
      .max(320)
      .transform((value) => value.trim().toLowerCase()),
    password: z.string().min(12).max(512),
    auditKey: auditKey.optional(),
  })
  .strict();

export const loginSchema = z
  .object({
    identifier: z.string().trim().min(3).max(320),
    password: z.string().min(12).max(512),
    auditKey: auditKey.optional(),
  })
  .strict();

export const routeSchema = z
  .object({
    name: z.string().trim().min(1).max(120),
    encryptedPayload: encryptedPayloadSchema,
    preferences: z.record(z.string(), z.union([z.boolean(), z.number().min(0).max(1)])),
  })
  .strict()
  .refine((value) => Object.keys(value.preferences).length <= 32, {
    message: "too many preferences",
    path: ["preferences"],
  });

export const profileSecretSchema = z
  .object({
    encryptedPayload: encryptedPayloadSchema,
  })
  .strict();
