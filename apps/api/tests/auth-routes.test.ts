import { DatabaseSync } from "node:sqlite";
import request from "supertest";
import { describe, expect, it } from "vitest";
import { createApp } from "../src/server.js";
import { migrate } from "../src/db.js";

function testApp() {
  const db = new DatabaseSync(":memory:");
  migrate(db);
  return createApp({
    db,
    config: {
      databasePath: ":memory:",
      port: 0,
      serverSecret: "test-secret",
      sessionDays: 1
    }
  });
}

const encryptedPayload = {
  version: 1,
  algorithm: "AES-256-GCM",
  nonce: "dGVzdC1ub25jZS0xMg",
  ciphertext: "Y2lwaGVydGV4dA",
  tag: "MTIzNDU2Nzg5MDEyMzQ1Ng",
  keyDerivation: "argon2id-hkdf-sha256"
} as const;

describe("auth and encrypted route storage", () => {
  it("registers, logs in, and stores only encrypted route payloads", async () => {
    const app = testApp();

    const registered = await request(app)
      .post("/auth/register")
      .send({
        username: "rider",
        email: "rider@example.com",
        password: "correct horse battery staple"
      })
      .expect(201);

    expect(registered.body.token).toEqual(expect.any(String));
    expect(registered.body.kdfSalt).toEqual(expect.any(String));

    const loggedIn = await request(app)
      .post("/auth/login")
      .send({
        identifier: "rider@example.com",
        password: "correct horse battery staple"
      })
      .expect(200);

    const token = loggedIn.body.token;
    await request(app)
      .post("/routes")
      .set("Authorization", `Bearer ${token}`)
      .send({
        name: "Blue Ridge morning",
        encryptedPayload,
        preferences: {
          twisty: 0.9,
          scenic: 0.8,
          avoidHighways: true
        }
      })
      .expect(201);

    const routes = await request(app)
      .get("/routes")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);

    expect(routes.body.routes).toHaveLength(1);
    expect(routes.body.routes[0].encryptedPayload.ciphertext).toBe(encryptedPayload.ciphertext);
  });
});
