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
      sessionDays: 1,
    },
  });
}

const encryptedPayload = {
  version: 1,
  algorithm: "AES-256-GCM",
  nonce: "dGVzdC1ub25jZS0xMg",
  ciphertext: "Y2lwaGVydGV4dA",
  tag: "MTIzNDU2Nzg5MDEyMzQ1Ng",
  keyDerivation: "argon2id-hkdf-sha256",
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
        password: "correct horse battery staple",
      })
      .expect(201);

    expect(registered.body.token).toEqual(expect.any(String));
    expect(registered.body.kdfSalt).toEqual(expect.any(String));

    const loggedIn = await request(app)
      .post("/auth/login")
      .send({
        identifier: "rider@example.com",
        password: "correct horse battery staple",
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
          avoidHighways: true,
        },
      })
      .expect(201);

    const routes = await request(app)
      .get("/routes")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);

    expect(routes.body.routes).toHaveLength(1);
    expect(routes.body.routes[0].encryptedPayload.ciphertext).toBe(
      encryptedPayload.ciphertext,
    );
  });

  it("routes through rider shaping points with backroad preferences", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          trip: {
            legs: [
              {
                shape: "",
                maneuvers: [],
              },
            ],
            summary: {
              length: 12,
              time: 1800,
            },
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
    const app = testApp();

    const response = await request(app)
      .get("/integrations/route")
      .query({
        originLat: 40.8,
        originLng: -73.72,
        destinationLat: 40.9,
        destinationLng: -73.35,
        shapingPoints: "40.820000,-73.650000;40.880000,-73.500000",
        scenic: 0.9,
        twisty: 0.8,
        avoidHighways: "1",
        avoidMainRoads: "1",
        autoScenicDetour: "1",
      })
      .expect(200);

    const requestBody = JSON.parse(fetchMock.mock.calls[0][1]?.body as string);
    expect(requestBody.locations).toEqual([
      { lat: 40.8, lon: -73.72 },
      { lat: 40.82, lon: -73.65, type: "via" },
      { lat: 40.88, lon: -73.5, type: "via" },
      { lat: 40.9, lon: -73.35 },
    ]);
    expect(requestBody.costing_options.auto.use_highways).toBe(0.01);
    expect(requestBody.costing_options.auto.use_roads).toBe(0.25);
    expect(response.body.twistaway.preferences.avoidMainRoads).toBe(true);
    expect(response.body.twistaway.notes).toContain(
      "Routing through 2 route shaping points.",
    );
    expect(response.headers["x-twistaway-route-cache"]).toBe("miss");

    const cached = await request(app)
      .get("/integrations/route")
      .query({
        originLat: 40.8,
        originLng: -73.72,
        destinationLat: 40.9,
        destinationLng: -73.35,
        shapingPoints: "40.820000,-73.650000;40.880000,-73.500000",
        scenic: 0.9,
        twisty: 0.8,
        avoidHighways: "1",
        avoidMainRoads: "1",
        autoScenicDetour: "1",
      })
      .expect(200);

    expect(cached.headers["x-twistaway-route-cache"]).toBe("hit");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("uses fast place search results before falling back to slower search", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          features: [
            {
              geometry: {
                coordinates: [-73.525, 40.768],
              },
              properties: {
                name: "Hicksville",
                city: "Hicksville",
                state: "New York",
                country: "United States",
                osm_value: "city",
              },
            },
          ],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
    const app = testApp();

    const response = await request(app)
      .get("/integrations/search")
      .query({
        q: "hicksville",
        centerLat: 40.76,
        centerLng: -73.52,
      })
      .expect(200);

    expect(String(fetchMock.mock.calls[0][0])).toContain(
      "https://photon.komoot.io/api/",
    );
    expect(response.body.searchMode).toBe("photon");
    expect(response.body.results[0]).toMatchObject({
      name: "Hicksville, New York, United States",
      latitude: 40.768,
      longitude: -73.525,
      type: "city",
    });
    expect(response.headers["x-twistaway-search-cache"]).toBe("miss");

    const cached = await request(app)
      .get("/integrations/search")
      .query({
        q: "hicksville",
        centerLat: 40.76,
        centerLng: -73.52,
      })
      .expect(200);

    expect(cached.headers["x-twistaway-search-cache"]).toBe("hit");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("adds generic scenic arc waypoints for pure backroads", async () => {
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            trip: {
              legs: [
                {
                  shape: "",
                  maneuvers: [],
                },
              ],
              summary: {
                length: 36,
                time: 3600,
              },
            },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            trip: {
              legs: [
                {
                  shape: "",
                  maneuvers: [],
                },
              ],
              summary: {
                length: 30,
                time: 3000,
              },
            },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );
    const app = testApp();

    const response = await request(app)
      .get("/integrations/route")
      .query({
        originLat: 40.768,
        originLng: -73.525,
        destinationLat: 40.875,
        destinationLng: -73.006,
        scenic: 1,
        twisty: 0.9,
        pureBackroads: "1",
      })
      .expect(200);

    const requestBody = JSON.parse(fetchMock.mock.calls[0][1]?.body as string);
    expect(requestBody.locations).toHaveLength(5);
    expect(requestBody.locations[0]).toEqual({ lat: 40.768, lon: -73.525 });
    expect(requestBody.locations.at(-1)).toEqual({
      lat: 40.875,
      lon: -73.006,
    });
    for (const point of requestBody.locations.slice(1, -1)) {
      expect(point.type).toBe("via");
      expect(point.lat).toBeGreaterThan(40.875);
      expect(point.lon).toBeGreaterThan(-73.525);
      expect(point.lon).toBeLessThan(-73.006);
    }
    expect(requestBody.costing_options.auto.use_highways).toBe(0);
    expect(requestBody.costing_options.auto.use_roads).toBe(0.08);
    expect(requestBody.costing_options.auto.shortest).toBe(false);
    expect(response.body.twistaway.preferences.pureBackroads).toBe(true);
    expect(response.body.twistaway.notes).toContain(
      "Auto scenic corridor added 3 waypoints to build a less direct scenic arc.",
    );
  });

  it("drops automatic scenic waypoints when they are too inefficient", async () => {
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            trip: {
              legs: [{ shape: "", maneuvers: [] }],
              summary: {
                length: 80,
                time: 8000,
              },
            },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            trip: {
              legs: [{ shape: "", maneuvers: [] }],
              summary: {
                length: 34,
                time: 3400,
              },
            },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );
    const app = testApp();

    const response = await request(app)
      .get("/integrations/route")
      .query({
        originLat: 40.768,
        originLng: -73.525,
        destinationLat: 40.875,
        destinationLng: -73.006,
        scenic: 1,
        pureBackroads: "1",
      })
      .expect(200);

    const guardedRequestBody = JSON.parse(fetchMock.mock.calls[1][1]?.body as string);
    expect(guardedRequestBody.locations).toEqual([
      { lat: 40.768, lon: -73.525 },
      { lat: 40.875, lon: -73.006 },
    ]);
    expect(response.body.routes[0].distance).toBeCloseTo(34 * 1609.344);
    expect(response.body.twistaway.notes).toContain(
      "Scenic corridor guard skipped the automatic scenic arc because it made the ride too inefficient.",
    );
  });
});

describe("deployment headers", () => {
  it("allows configured browser origins and rejects unconfigured origins", async () => {
    const app = createApp({
      config: {
        databasePath: ":memory:",
        port: 0,
        serverSecret: "test-secret",
        sessionDays: 1,
        corsOrigins: ["https://twistaway.app"],
        trustProxy: true,
      },
    });

    const allowed = await request(app)
      .get("/health")
      .set("Origin", "https://twistaway.app")
      .expect(200);
    expect(allowed.headers["access-control-allow-origin"]).toBe(
      "https://twistaway.app",
    );

    const rejected = await request(app)
      .get("/health")
      .set("Origin", "https://example.invalid")
      .expect(200);
    expect(rejected.headers["access-control-allow-origin"]).toBeUndefined();
  });
});
