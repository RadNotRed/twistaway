import { DatabaseSync } from "node:sqlite";
import request from "supertest";
import { afterEach, describe, expect, it, vi } from "vitest";
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
  afterEach(() => {
    vi.restoreAllMocks();
  });

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

  it("routes through rider shaping points with backroad preferences", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          trip: {
            legs: [
              {
                shape: "",
                maneuvers: []
              }
            ],
            summary: {
              length: 12,
              time: 1800
            }
          }
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      )
    );
    const app = testApp();

    const response = await request(app)
      .get("/integrations/route")
      .query({
        originLat: 40.80,
        originLng: -73.72,
        destinationLat: 40.90,
        destinationLng: -73.35,
        shapingPoints: "40.820000,-73.650000;40.880000,-73.500000",
        scenic: 0.9,
        twisty: 0.8,
        avoidHighways: "1",
        avoidMainRoads: "1",
        autoScenicDetour: "1"
      })
      .expect(200);

    const requestBody = JSON.parse(fetchMock.mock.calls[0][1]?.body as string);
    expect(requestBody.locations).toEqual([
      { lat: 40.8, lon: -73.72 },
      { lat: 40.82, lon: -73.65, type: "via" },
      { lat: 40.88, lon: -73.5, type: "via" },
      { lat: 40.9, lon: -73.35 }
    ]);
    expect(requestBody.costing_options.auto.use_highways).toBe(0.01);
    expect(requestBody.costing_options.auto.use_roads).toBe(0.25);
    expect(response.body.motoplanner.preferences.avoidMainRoads).toBe(true);
    expect(response.body.motoplanner.notes).toContain("Routing through 2 rider shaping points.");
  });
});
