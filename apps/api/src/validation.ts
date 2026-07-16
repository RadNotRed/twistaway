import { z } from "zod";

export const encryptedPayloadSchema = z.object({
  version: z.literal(1),
  algorithm: z.literal("AES-256-GCM"),
  nonce: z.string().min(12),
  ciphertext: z.string().min(1),
  tag: z.string().min(16),
  aad: z.string().optional(),
  keyDerivation: z.literal("argon2id-hkdf-sha256"),
});

export const registerSchema = z.object({
  username: z
    .string()
    .min(3)
    .max(40)
    .regex(/^[a-zA-Z0-9_.-]+$/),
  email: z.email(),
  password: z.string().min(12).max(512),
  auditKey: z.string().optional(),
});

export const loginSchema = z.object({
  identifier: z.string().min(3),
  password: z.string().min(12).max(512),
  auditKey: z.string().optional(),
});

export const routeSchema = z.object({
  name: z.string().min(1).max(120),
  encryptedPayload: encryptedPayloadSchema,
  preferences: z.record(z.string(), z.union([z.boolean(), z.number().min(0).max(1)])),
});

export const profileSecretSchema = z.object({
  encryptedPayload: encryptedPayloadSchema,
});
