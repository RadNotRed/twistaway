import cors from "cors";
import express, {
  type NextFunction,
  type Request,
  type Response,
} from "express";
import helmet from "helmet";
import { randomBytes, randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import type { EncryptedPayload } from "@motoplanner/shared";
import { loadConfig, type ApiConfig } from "./config.js";
import { type AppDatabase, openDatabase } from "./db.js";
import {
  hashPassword,
  hashToken,
  randomToken,
  sealJsonWithKey,
  unwrapAuditKey,
  verifyPassword,
  wrapAuditKey,
} from "./security.js";
import {
  loginSchema,
  profileSecretSchema,
  registerSchema,
  routeSchema,
} from "./validation.js";

interface AuthedRequest extends Request {
  auth?: {
    userId: string;
    tokenHash: string;
    auditKey: Buffer | null;
  };
}

interface CreateAppOptions {
  db?: AppDatabase;
  config?: ApiConfig;
}

interface RoutePreferences {
  twisty: number;
  scenic: number;
  avoidHighways: boolean;
  avoidMainRoads: boolean;
  pureBackroads: boolean;
  autoScenicDetour: boolean;
  targetHighways: boolean;
  targetStraightRoads: boolean;
}

interface RoutePoint {
  lat: number;
  lon: number;
}

interface OsrmRoute {
  distance: number;
  duration: number;
  geometry?: {
    coordinates?: Array<[number, number]>;
  };
  legs?: Array<{
    steps?: Array<{
      distance?: number;
      duration?: number;
      name?: string;
      ref?: string;
      intersections?: Array<{
        classes?: string[];
      }>;
    }>;
  }>;
}

interface OsrmResponse {
  code: string;
  routes?: OsrmRoute[];
  waypoints?: unknown[];
  motoplanner?: {
    preferences: RoutePreferences;
    notes: string[];
  };
}

interface ValhallaManeuver {
  instruction?: string;
  length?: number;
  time?: number;
  begin_shape_index?: number;
  end_shape_index?: number;
  street_names?: string[];
  verbal_pre_transition_instruction?: string;
}

interface ValhallaResponse {
  trip?: {
    legs?: Array<{
      shape?: string;
      maneuvers?: ValhallaManeuver[];
    }>;
    summary?: {
      length?: number;
      time?: number;
      has_highway?: boolean;
      has_toll?: boolean;
      has_ferry?: boolean;
    };
    status_message?: string;
  };
}

const searchCache = new Map<string, { expiresAt: number; payload: unknown }>();
const searchInFlight = new Map<string, Promise<SearchPayload>>();
const searchCacheTtlMs = 5 * 60 * 1000;

interface SearchResult {
  name: string;
  latitude: number;
  longitude: number;
  type: string | null;
  distanceMeters: number | null;
}

interface SearchPayload {
  searchMode: string;
  results: SearchResult[];
}

function nowIso(): string {
  return new Date().toISOString();
}

function expiresInDays(days: number): string {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
}

function getIp(req: Request): string {
  const forwarded = req.header("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || req.socket.remoteAddress || "unknown";
}

function boolQuery(value: unknown): boolean {
  return value === "true" || value === "1" || value === true;
}

function numberQuery(value: unknown, fallback: number): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(0, Math.min(1, parsed));
}

function routePreferencesFromQuery(query: Request["query"]): RoutePreferences {
  const pureBackroads = boolQuery(query.pureBackroads);
  const avoidHighways = pureBackroads || boolQuery(query.avoidHighways);
  const avoidMainRoads = pureBackroads || boolQuery(query.avoidMainRoads);
  const targetHighways =
    !avoidHighways && !avoidMainRoads && boolQuery(query.targetHighways);
  return {
    twisty: numberQuery(query.twisty, 0.5),
    scenic: numberQuery(query.scenic, 0.5),
    avoidHighways,
    avoidMainRoads: !targetHighways && avoidMainRoads,
    pureBackroads: !targetHighways && pureBackroads,
    autoScenicDetour: pureBackroads || boolQuery(query.autoScenicDetour),
    targetHighways,
    targetStraightRoads: !pureBackroads && boolQuery(query.targetStraightRoads),
  };
}

function parseShapingPoints(value: unknown): RoutePoint[] {
  if (typeof value !== "string" || value.trim() === "") {
    return [];
  }

  return value
    .split(";")
    .slice(0, 8)
    .map((pair) => {
      const [lat, lon] = pair.split(",").map((part) => Number(part.trim()));
      return { lat, lon };
    })
    .filter(
      (point) =>
        Number.isFinite(point.lat) &&
        Number.isFinite(point.lon) &&
        Math.abs(point.lat) <= 90 &&
        Math.abs(point.lon) <= 180,
    );
}

function effectiveShapingPoints(
  origin: RoutePoint,
  destination: RoutePoint,
  requested: RoutePoint[],
  preferences: RoutePreferences,
  notes: string[],
): RoutePoint[] {
  const scenicPressure =
    preferences.scenic >= 0.85 && preferences.autoScenicDetour;
  if (!preferences.pureBackroads && !scenicPressure) {
    return requested;
  }
  if (requested.length > 0) {
    if (preferences.pureBackroads) {
      notes.push(
        "Pure backroads active: following rider shaping points with strict backroad weights.",
      );
    }
    return requested;
  }

  const automatic = automaticScenicCorridorPoints(
    origin,
    destination,
    preferences,
  );
  if (automatic.length === 0) {
    if (preferences.pureBackroads) {
      notes.push(
        "Pure backroads active: provider weights and scoring will strongly avoid main-road corridors.",
      );
    }
    return requested;
  }

  notes.push(
    `Auto scenic corridor added ${automatic.length} ${automatic.length === 1 ? "waypoint" : "waypoints"} to build a less direct scenic arc.`,
  );

  return [...requested, ...automatic].slice(0, 8);
}

function automaticScenicCorridorPoints(
  origin: RoutePoint,
  destination: RoutePoint,
  preferences: RoutePreferences,
): RoutePoint[] {
  const directDistanceMeters = haversineMeters(
    origin.lat,
    origin.lon,
    destination.lat,
    destination.lon,
  );
  if (directDistanceMeters < 8000) {
    return [];
  }

  const directBearing = bearing(
    [origin.lon, origin.lat],
    [destination.lon, destination.lat],
  );
  const offsetDistanceMeters = Math.min(
    35000,
    Math.max(
      2500,
      directDistanceMeters *
        (0.16 +
          preferences.scenic * 0.1 +
          (preferences.pureBackroads ? 0.06 : 0)),
    ),
  );
  const waypointFractions = preferences.pureBackroads
    ? [0.25, 0.5, 0.75]
    : [0.34, 0.67];
  const offsetBearing = scenicOffsetBearing(
    origin,
    destination,
    directBearing,
    offsetDistanceMeters,
  );

  return waypointFractions
    .map((fraction) => {
      const centerlinePoint = destinationPoint(
        origin,
        directDistanceMeters * fraction,
        directBearing,
      );
      return destinationPoint(
        centerlinePoint,
        offsetDistanceMeters,
        offsetBearing,
      );
    })
    .filter((point) => Math.abs(point.lat) <= 85)
    .filter(
      (point) =>
        haversineMeters(origin.lat, origin.lon, point.lat, point.lon) > 3500,
    )
    .filter(
      (point) =>
        haversineMeters(
          destination.lat,
          destination.lon,
          point.lat,
          point.lon,
        ) > 3500,
    );
}

function scenicOffsetBearing(
  origin: RoutePoint,
  destination: RoutePoint,
  directBearing: number,
  offsetDistanceMeters: number,
): number {
  const leftBearing = (directBearing - 90 + 360) % 360;
  const rightBearing = (directBearing + 90) % 360;
  const midpoint = destinationPoint(
    origin,
    haversineMeters(origin.lat, origin.lon, destination.lat, destination.lon) /
      2,
    directBearing,
  );
  const leftPoint = destinationPoint(
    midpoint,
    offsetDistanceMeters,
    leftBearing,
  );
  const rightPoint = destinationPoint(
    midpoint,
    offsetDistanceMeters,
    rightBearing,
  );
  const preferNorth =
    (origin.lat + destination.lat) / 2 >= 0 &&
    Math.abs(destination.lon - origin.lon) >=
      Math.abs(destination.lat - origin.lat);

  if (preferNorth) {
    return leftPoint.lat >= rightPoint.lat ? leftBearing : rightBearing;
  }
  return leftPoint.lat <= rightPoint.lat ? leftBearing : rightBearing;
}

function optionalNumberQuery(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function haversineMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const radius = 6371000;
  const dLat = degreesToRadians(lat2 - lat1);
  const dLon = degreesToRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(degreesToRadians(lat1)) *
      Math.cos(degreesToRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  return radius * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function routeClasses(route: OsrmRoute): string[] {
  return (route.legs ?? []).flatMap((leg) =>
    (leg.steps ?? []).flatMap((step) =>
      (step.intersections ?? []).flatMap(
        (intersection) => intersection.classes ?? [],
      ),
    ),
  );
}

function routeTurnDensity(route: OsrmRoute): number {
  const stepCount = (route.legs ?? []).reduce(
    (total, leg) => total + (leg.steps?.length ?? 0),
    0,
  );
  return stepCount / Math.max(route.distance / 1609.344, 1);
}

function routeCurvature(route: OsrmRoute): number {
  const points = route.geometry?.coordinates ?? [];
  if (points.length < 3) {
    return 0;
  }

  let totalChange = 0;
  for (let index = 2; index < points.length; index += 1) {
    const previous = bearing(points[index - 2], points[index - 1]);
    const next = bearing(points[index - 1], points[index]);
    let delta = Math.abs(next - previous);
    if (delta > 180) {
      delta = 360 - delta;
    }
    totalChange += delta;
  }

  return totalChange / Math.max(route.distance / 1609.344, 1);
}

function bearing(from: [number, number], to: [number, number]): number {
  const lng1 = degreesToRadians(from[0]);
  const lng2 = degreesToRadians(to[0]);
  const lat1 = degreesToRadians(from[1]);
  const lat2 = degreesToRadians(to[1]);
  const y = Math.sin(lng2 - lng1) * Math.cos(lat2);
  const x =
    Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(lng2 - lng1);
  return (radiansToDegrees(Math.atan2(y, x)) + 360) % 360;
}

function degreesToRadians(value: number): number {
  return (value * Math.PI) / 180;
}

function radiansToDegrees(value: number): number {
  return (value * 180) / Math.PI;
}

function destinationPoint(
  start: RoutePoint,
  distanceMeters: number,
  bearingDegrees: number,
): RoutePoint {
  const earthRadiusMeters = 6371000;
  const angularDistance = distanceMeters / earthRadiusMeters;
  const bearingRadians = degreesToRadians(bearingDegrees);
  const lat1 = degreesToRadians(start.lat);
  const lon1 = degreesToRadians(start.lon);
  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(angularDistance) +
      Math.cos(lat1) * Math.sin(angularDistance) * Math.cos(bearingRadians),
  );
  const lon2 =
    lon1 +
    Math.atan2(
      Math.sin(bearingRadians) * Math.sin(angularDistance) * Math.cos(lat1),
      Math.cos(angularDistance) - Math.sin(lat1) * Math.sin(lat2),
    );
  return {
    lat: radiansToDegrees(lat2),
    lon: ((((radiansToDegrees(lon2) + 180) % 360) + 360) % 360) - 180,
  };
}

async function fetchJsonWithTimeout<T>(
  url: URL,
  headers: Record<string, string>,
  timeoutMs: number,
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const upstream = await fetch(url, {
      headers,
      signal: controller.signal,
    });

    if (!upstream.ok) {
      throw new Error(`location provider failed (${upstream.status})`);
    }

    return (await upstream.json()) as T;
  } finally {
    clearTimeout(timeout);
  }
}

function photonDisplayName(properties: Record<string, unknown>): string {
  const name = typeof properties.name === "string" ? properties.name : null;
  const houseNumber =
    typeof properties.housenumber === "string" ? properties.housenumber : null;
  const street =
    typeof properties.street === "string" ? properties.street : null;
  const city = typeof properties.city === "string" ? properties.city : null;
  const state = typeof properties.state === "string" ? properties.state : null;
  const country =
    typeof properties.country === "string" ? properties.country : null;
  const addressLine = [houseNumber, street].filter(Boolean).join(" ");
  const parts = [name ?? addressLine, city, state, country].filter(
    (part, index, values): part is string =>
      Boolean(part) && values.indexOf(part) === index,
  );
  return parts.length > 0 ? parts.join(", ") : "Unknown place";
}

function highwayRatio(route: OsrmRoute): number {
  const steps = (route.legs ?? []).flatMap((leg) => leg.steps ?? []);
  const total = steps.reduce((sum, step) => sum + (step.distance ?? 0), 0);
  if (total <= 0) {
    return 0;
  }

  const classes = routeClasses(route);
  const classHasMotorway = classes.includes("motorway");
  const highwayDistance = steps.reduce((sum, step) => {
    const text = `${step.name ?? ""} ${step.ref ?? ""}`.toLowerCase();
    const looksLikeHighway =
      classHasMotorway ||
      /\b(i-|interstate|us-|u\.s\.|highway|hwy|freeway|expressway|parkway)\b/.test(
        text,
      );
    return sum + (looksLikeHighway ? (step.distance ?? 0) : 0);
  }, 0);
  return highwayDistance / total;
}

function mainRoadRatio(route: OsrmRoute): number {
  const steps = (route.legs ?? []).flatMap((leg) => leg.steps ?? []);
  const total = steps.reduce((sum, step) => sum + (step.distance ?? 0), 0);
  if (total <= 0) {
    return 0;
  }

  const mainRoadDistance = steps.reduce((sum, step) => {
    const text = `${step.name ?? ""} ${step.ref ?? ""}`.toLowerCase();
    const looksLikeMainRoad =
      /\b(i-|interstate|us-|u\.s\.|highway|hwy|freeway|expressway|parkway|turnpike|state route|route|sr-|ny-|nj-|pa-|ca-|fl-)\b/.test(
        text,
      ) || /\b[a-z]{1,3}-\d{1,4}\b/.test(text);
    return sum + (looksLikeMainRoad ? (step.distance ?? 0) : 0);
  }, 0);
  return mainRoadDistance / total;
}

function scoreRoute(
  route: OsrmRoute,
  fastestDistance: number,
  prefs: RoutePreferences,
): number {
  const distancePenalty =
    (route.distance - fastestDistance) / Math.max(fastestDistance, 1);
  const highway = highwayRatio(route);
  const mainRoad = mainRoadRatio(route);
  const turns = routeTurnDensity(route);
  const curvature = routeCurvature(route);
  const straightness = 1 / Math.max(turns + curvature / 60, 0.25);

  const distanceWeight = prefs.pureBackroads
    ? 1.5
    : prefs.autoScenicDetour && (prefs.scenic > 0.55 || prefs.avoidMainRoads)
      ? 4
      : 8;
  let score = -distancePenalty * distanceWeight;
  score += prefs.twisty * (turns * 0.8 + curvature * 0.05);
  score +=
    prefs.scenic *
    ((1 - highway) * 2 + (1 - mainRoad) * 2 + Math.min(curvature / 80, 2));
  score += prefs.avoidHighways ? -highway * 12 : 0;
  score += prefs.avoidMainRoads ? -mainRoad * 14 - highway * 8 : 0;
  score += prefs.pureBackroads
    ? -mainRoad * 22 - highway * 20 + turns * 0.5 + Math.min(curvature / 90, 2)
    : 0;
  score += prefs.targetHighways ? highway * 8 : 0;
  score += prefs.targetStraightRoads ? straightness * 2 - turns * 0.6 : 0;
  return score;
}

function selectPreferredRoute(
  payload: OsrmResponse,
  prefs: RoutePreferences,
  notes: string[],
): OsrmResponse {
  const routes = payload.routes ?? [];
  if (routes.length <= 1) {
    notes.push("Only one route was returned by the routing provider.");
    return payload;
  }

  const fastestDistance = Math.min(...routes.map((route) => route.distance));
  const scored = routes
    .map((route, index) => ({
      route,
      index,
      score: scoreRoute(route, fastestDistance, prefs),
    }))
    .sort((a, b) => b.score - a.score);

  const selected = scored[0];
  notes.push(
    `Scored ${routes.length} route alternatives using current ride preferences.`,
  );
  if (selected.index !== 0) {
    notes.push(
      `Selected alternative ${selected.index + 1} over the provider default.`,
    );
  }

  return {
    ...payload,
    routes: [
      selected.route,
      ...routes.filter((_, index) => index !== selected.index),
    ],
  };
}

async function routeWithValhalla(
  originLat: number,
  originLng: number,
  destinationLat: number,
  destinationLng: number,
  shapingPoints: RoutePoint[],
  preferences: RoutePreferences,
  notes: string[],
): Promise<OsrmResponse> {
  const useHighways = preferences.pureBackroads
    ? 0
    : preferences.avoidHighways || preferences.avoidMainRoads
      ? 0.01
      : preferences.targetHighways
        ? 1
        : preferences.targetStraightRoads
          ? 0.85
          : Math.max(
              0.2,
              0.62 - preferences.scenic * 0.3 - preferences.twisty * 0.2,
            );
  const useRoads = preferences.pureBackroads
    ? 0.08
    : preferences.avoidMainRoads
      ? 0.25
      : preferences.targetStraightRoads
        ? 0.85
        : Math.max(
            0.2,
            0.75 - preferences.twisty * 0.22 - preferences.scenic * 0.08,
          );
  const shortest = preferences.pureBackroads
    ? false
    : preferences.targetStraightRoads
      ? true
      : undefined;

  const body = {
    locations: [
      { lat: originLat, lon: originLng },
      ...shapingPoints.map((point) => ({
        lat: point.lat,
        lon: point.lon,
        type: "via",
      })),
      { lat: destinationLat, lon: destinationLng },
    ],
    costing: "auto",
    costing_options: {
      auto: {
        use_highways: Number(useHighways.toFixed(2)),
        use_roads: Number(useRoads.toFixed(2)),
        use_tolls: 0,
        ...(shortest === undefined ? {} : { shortest }),
      },
    },
    directions_options: {
      units: "miles",
    },
  };

  const upstream = await fetch("https://valhalla1.openstreetmap.de/route", {
    method: "POST",
    headers: {
      "User-Agent": "MotoPlanner/0.1 (development contact: motoplanner.local)",
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!upstream.ok) {
    throw new Error(`Valhalla failed (${upstream.status})`);
  }

  const payload = (await upstream.json()) as ValhallaResponse;
  if (!payload.trip?.legs?.length) {
    throw new Error(
      payload.trip?.status_message ?? "Valhalla returned no route",
    );
  }

  notes.push(
    `Highway ${body.costing_options.auto.use_highways}, road ${body.costing_options.auto.use_roads}.`,
  );
  if (preferences.avoidHighways) {
    notes.push("Avoid highways active.");
  }
  if (preferences.avoidMainRoads) {
    notes.push(
      "Backroads active: heavily reducing highways and major arterials.",
    );
  }
  if (preferences.pureBackroads) {
    notes.push(
      "Pure backroads active: using the strictest available provider weights and scoring.",
    );
  }
  if (preferences.autoScenicDetour) {
    notes.push(
      "Auto scenic detour active: slower scenic alternatives can win.",
    );
  }
  if (shapingPoints.length > 0) {
    notes.push(
      `Routing through ${shapingPoints.length} route shaping ${shapingPoints.length === 1 ? "point" : "points"}.`,
    );
  }
  if (preferences.targetHighways) {
    notes.push("Target highways active.");
  }
  if (preferences.targetStraightRoads) {
    notes.push("Straight roads favored.");
  }

  return valhallaToOsrm(payload);
}

function valhallaToOsrm(payload: ValhallaResponse): OsrmResponse {
  const leg = payload.trip!.legs![0];
  const points = decodeValhallaShape(leg.shape ?? "");
  const maneuvers = leg.maneuvers ?? [];
  const steps = maneuvers.map((maneuver) => {
    const start = maneuver.begin_shape_index ?? 0;
    const end = Math.max(start, maneuver.end_shape_index ?? start);
    const segment = points.slice(start, end + 1);
    const fallbackSegment =
      segment.length >= 2
        ? segment
        : points.slice(
            Math.max(0, start - 1),
            Math.min(points.length, start + 2),
          );
    return {
      intersections: [],
      driving_side: "right",
      geometry: {
        coordinates: fallbackSegment.map((point) => [point[1], point[0]]),
        type: "LineString",
      },
      maneuver: {
        location:
          fallbackSegment.length > 0
            ? [fallbackSegment[0][1], fallbackSegment[0][0]]
            : [0, 0],
        type: "continue",
      },
      name: maneuver.street_names?.[0] ?? "",
      mode: "driving",
      duration: maneuver.time ?? 0,
      distance: (maneuver.length ?? 0) * 1609.344,
      instruction:
        maneuver.verbal_pre_transition_instruction ??
        maneuver.instruction ??
        "Continue",
    };
  });

  const summary = payload.trip?.summary;
  return {
    code: "Ok",
    routes: [
      {
        legs: [
          {
            steps,
          },
        ],
        geometry: {
          coordinates: points.map((point) => [point[1], point[0]]),
        },
        duration:
          summary?.time ?? steps.reduce((sum, step) => sum + step.duration, 0),
        distance: (summary?.length ?? 0) * 1609.344,
      },
    ],
    waypoints: [],
  };
}

function decodeValhallaShape(shape: string): Array<[number, number]> {
  const coordinates: Array<[number, number]> = [];
  let index = 0;
  let lat = 0;
  let lng = 0;

  while (index < shape.length) {
    const latResult = decodePolylineValue(shape, index);
    index = latResult.nextIndex;
    const lngResult = decodePolylineValue(shape, index);
    index = lngResult.nextIndex;
    lat += latResult.delta;
    lng += lngResult.delta;
    coordinates.push([lat / 1e6, lng / 1e6]);
  }

  return coordinates;
}

function decodePolylineValue(
  value: string,
  startIndex: number,
): { delta: number; nextIndex: number } {
  let result = 0;
  let shift = 0;
  let index = startIndex;
  let byte = 0;

  do {
    byte = value.charCodeAt(index) - 63;
    index += 1;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20 && index < value.length);

  return {
    delta: result & 1 ? ~(result >> 1) : result >> 1,
    nextIndex: index,
  };
}

async function routeWithOsrm(
  originLat: number,
  originLng: number,
  destinationLat: number,
  destinationLng: number,
  shapingPoints: RoutePoint[],
  preferences: RoutePreferences,
  notes: string[],
): Promise<OsrmResponse> {
  const routePoints = [
    { lat: originLat, lon: originLng },
    ...shapingPoints,
    { lat: destinationLat, lon: destinationLng },
  ];
  const coordinates = routePoints
    .map((point) => `${point.lon},${point.lat}`)
    .join(";");
  const url = new URL(
    `https://router.project-osrm.org/route/v1/driving/${coordinates}`,
  );
  url.searchParams.set("overview", "full");
  url.searchParams.set("geometries", "geojson");
  url.searchParams.set("steps", "true");
  url.searchParams.set("alternatives", "true");
  if (preferences.avoidHighways) {
    url.searchParams.set("exclude", "motorway");
    notes.push("Asked OSRM fallback to exclude motorway-class roads.");
  }
  if (preferences.avoidMainRoads) {
    notes.push(
      "OSRM fallback cannot forbid all main roads, so alternatives are scored against major-road names.",
    );
  }
  if (shapingPoints.length > 0) {
    notes.push(
      `OSRM fallback routing through ${shapingPoints.length} rider shaping ${shapingPoints.length === 1 ? "point" : "points"}.`,
    );
  }

  let upstream = await fetch(url, {
    headers: {
      "User-Agent": "MotoPlanner/0.1 (development contact: motoplanner.local)",
      Accept: "application/json",
    },
  });

  if (!upstream.ok && preferences.avoidHighways) {
    notes.push(
      "OSRM motorway exclusion was not accepted, so scoring fallback was used.",
    );
    url.searchParams.delete("exclude");
    upstream = await fetch(url, {
      headers: {
        "User-Agent":
          "MotoPlanner/0.1 (development contact: motoplanner.local)",
        Accept: "application/json",
      },
    });
  }

  if (!upstream.ok) {
    throw new Error(`OSRM failed (${upstream.status})`);
  }

  const payload = (await upstream.json()) as OsrmResponse;
  return selectPreferredRoute(payload, preferences, notes);
}

export function createApp(options: CreateAppOptions = {}) {
  const config = options.config ?? loadConfig();
  const db = options.db ?? openDatabase(config.databasePath);
  const app = express();

  app.use(helmet());
  app.use(cors({ origin: true, credentials: true }));
  app.use(express.json({ limit: "1mb" }));

  function audit(
    req: AuthedRequest,
    eventType: string,
    extra: Record<string, unknown> = {},
  ) {
    if (!req.auth?.auditKey) {
      return;
    }

    const encrypted = sealJsonWithKey(
      {
        ip: getIp(req),
        userAgent: req.header("user-agent") ?? null,
        path: req.path,
        method: req.method,
        ...extra,
      },
      req.auth.auditKey,
    );

    db.prepare(
      `
      INSERT INTO audit_logs (id, user_id, event_type, encrypted_payload, created_at)
      VALUES (?, ?, ?, ?, ?)
    `,
    ).run(
      randomUUID(),
      req.auth.userId,
      eventType,
      JSON.stringify(encrypted),
      nowIso(),
    );
  }

  function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
    const header = req.header("authorization");
    const token = header?.startsWith("Bearer ")
      ? header.slice("Bearer ".length)
      : null;
    if (!token) {
      res.status(401).json({ error: "missing bearer token" });
      return;
    }

    const tokenHash = hashToken(token);
    const session = db
      .prepare(
        `
      SELECT user_id, audit_key_envelope, expires_at
      FROM sessions
      WHERE token_hash = ?
    `,
      )
      .get(tokenHash) as
      | {
          user_id: string;
          audit_key_envelope: string | null;
          expires_at: string;
        }
      | undefined;

    if (!session || new Date(session.expires_at).getTime() <= Date.now()) {
      res.status(401).json({ error: "invalid or expired session" });
      return;
    }

    req.auth = {
      userId: session.user_id,
      tokenHash,
      auditKey: unwrapAuditKey(session.audit_key_envelope, config.serverSecret),
    };
    next();
  }

  app.get("/health", (_req, res) => {
    res.json({ ok: true, service: "motoplanner-api" });
  });

  app.get("/integrations/search", async (req, res, next) => {
    try {
      const q = String(req.query.q ?? "").trim();
      if (q.length < 3) {
        res.json({ results: [] });
        return;
      }

      const centerLat = optionalNumberQuery(req.query.centerLat);
      const centerLng = optionalNumberQuery(req.query.centerLng);
      const north = optionalNumberQuery(req.query.north);
      const south = optionalNumberQuery(req.query.south);
      const east = optionalNumberQuery(req.query.east);
      const west = optionalNumberQuery(req.query.west);
      const hasBounds = [north, south, east, west].every(
        (value) => value !== null,
      );
      const hasCenter = centerLat !== null && centerLng !== null;
      const cacheKey = JSON.stringify({
        q: q.toLowerCase(),
        centerLat: centerLat?.toFixed(2),
        centerLng: centerLng?.toFixed(2),
        north: north?.toFixed(2),
        south: south?.toFixed(2),
        east: east?.toFixed(2),
        west: west?.toFixed(2),
      });
      const cached = searchCache.get(cacheKey);
      if (cached && cached.expiresAt > Date.now()) {
        res.setHeader("X-MotoPlanner-Search-Cache", "hit");
        res.json(cached.payload);
        return;
      }

      const pending = searchInFlight.get(cacheKey);
      if (pending) {
        res.setHeader("X-MotoPlanner-Search-Cache", "pending");
        res.json(await pending);
        return;
      }

      async function searchPhoton() {
        const url = new URL("https://photon.komoot.io/api/");
        url.searchParams.set("q", q);
        url.searchParams.set("limit", "12");
        url.searchParams.set("lang", "en");
        if (hasCenter) {
          url.searchParams.set("lat", String(centerLat));
          url.searchParams.set("lon", String(centerLng));
        }

        const payload = await fetchJsonWithTimeout<{
          features?: Array<{
            geometry?: { coordinates?: unknown };
            properties?: Record<string, unknown>;
          }>;
        }>(
          url,
          {
            "User-Agent":
              "MotoPlanner/0.1 (development contact: motoplanner.local)",
            Accept: "application/json",
          },
          1500,
        );

        return (payload.features ?? []).map((feature) => {
          const coordinates = feature.geometry?.coordinates;
          const longitude = Array.isArray(coordinates)
            ? Number(coordinates[0])
            : Number.NaN;
          const latitude = Array.isArray(coordinates)
            ? Number(coordinates[1])
            : Number.NaN;
          const properties = feature.properties ?? {};
          return {
            name: photonDisplayName(properties),
            latitude,
            longitude,
            type:
              typeof properties.osm_value === "string"
                ? properties.osm_value
                : null,
          };
        });
      }

      async function searchNominatim({ bounded }: { bounded: boolean }) {
        const url = new URL("https://nominatim.openstreetmap.org/search");
        url.searchParams.set("q", q);
        url.searchParams.set("format", "jsonv2");
        url.searchParams.set("addressdetails", "1");
        url.searchParams.set("limit", bounded ? "8" : "10");
        if (hasBounds) {
          url.searchParams.set("viewbox", `${west},${north},${east},${south}`);
        }
        if (bounded && hasBounds) {
          url.searchParams.set("bounded", "1");
        }
        if (!q.includes(",")) {
          url.searchParams.set("countrycodes", "us");
        }

        return await fetchJsonWithTimeout<Array<Record<string, unknown>>>(
          url,
          {
            "User-Agent":
              "MotoPlanner/0.1 (development contact: motoplanner.local)",
            Accept: "application/json",
          },
          bounded ? 2200 : 2800,
        );
      }

      async function resolveSearch(): Promise<SearchPayload> {
        let raw: Array<{
          name: string;
          latitude: number;
          longitude: number;
          type: string | null;
        }> = [];
        let searchMode = "photon";

        try {
          raw = await searchPhoton();
        } catch {
          raw = [];
        }

        if (raw.length === 0 && hasBounds) {
          const nominatim = await searchNominatim({ bounded: true });
          raw = nominatim.map((item) => ({
            name: String(item.display_name ?? "Unknown place"),
            latitude: Number(item.lat),
            longitude: Number(item.lon),
            type: typeof item.type === "string" ? item.type : null,
          }));
          searchMode = raw.length > 0 ? "local-bounds" : "regional-fallback";
        }

        if (raw.length === 0) {
          const nominatim = await searchNominatim({ bounded: false });
          raw = nominatim.map((item) => ({
            name: String(item.display_name ?? "Unknown place"),
            latitude: Number(item.lat),
            longitude: Number(item.lon),
            type: typeof item.type === "string" ? item.type : null,
          }));
          searchMode = searchMode === "photon" ? "nominatim" : searchMode;
        }

        const mapped = raw
          .map((item) => {
            const distanceMeters =
              hasCenter &&
              Number.isFinite(item.latitude) &&
              Number.isFinite(item.longitude)
                ? haversineMeters(
                    centerLat!,
                    centerLng!,
                    item.latitude,
                    item.longitude,
                  )
                : null;
            return {
              ...item,
              distanceMeters,
            };
          })
          .filter(
            (item) =>
              Number.isFinite(item.latitude) && Number.isFinite(item.longitude),
          );

        if (hasCenter || hasBounds) {
          mapped.sort((a, b) => searchRank(a) - searchRank(b));
        }

        return {
          searchMode,
          results: mapped.slice(0, 6),
        };
      }

      function pointOutsideBounds(
        latitude: number,
        longitude: number,
      ): boolean {
        return (
          hasBounds &&
          (latitude > north! ||
            latitude < south! ||
            longitude > east! ||
            longitude < west!)
        );
      }

      function searchRank(item: SearchResult): number {
        const normalizedQuery = q.toLowerCase();
        const primaryName = item.name.split(",")[0]?.trim().toLowerCase() ?? "";
        const outsidePenalty = pointOutsideBounds(item.latitude, item.longitude)
          ? 100000000
          : 0;
        const distanceScore = item.distanceMeters ?? Number.MAX_SAFE_INTEGER;
        const relevanceBonus =
          primaryName === normalizedQuery
            ? 75000
            : primaryName.startsWith(normalizedQuery)
              ? 10000
              : primaryName.includes(normalizedQuery)
                ? 4000
                : 0;
        return outsidePenalty + distanceScore - relevanceBonus;
      }

      const request = resolveSearch();
      searchInFlight.set(cacheKey, request);
      let payload: SearchPayload;
      try {
        payload = await request;
      } finally {
        searchInFlight.delete(cacheKey);
      }
      searchCache.set(cacheKey, {
        expiresAt: Date.now() + searchCacheTtlMs,
        payload,
      });
      res.setHeader("X-MotoPlanner-Search-Cache", "miss");
      res.json(payload);
    } catch (error) {
      next(error);
    }
  });

  app.get("/integrations/route", async (req, res, next) => {
    try {
      const originLat = Number(req.query.originLat);
      const originLng = Number(req.query.originLng);
      const destinationLat = Number(req.query.destinationLat);
      const destinationLng = Number(req.query.destinationLng);

      if (
        ![originLat, originLng, destinationLat, destinationLng].every(
          Number.isFinite,
        )
      ) {
        res.status(400).json({
          error:
            "originLat, originLng, destinationLat, and destinationLng are required",
        });
        return;
      }

      const preferences = routePreferencesFromQuery(req.query);
      const plannerNotes: string[] = [];
      const origin = { lat: originLat, lon: originLng };
      const destination = { lat: destinationLat, lon: destinationLng };
      const requestedShapingPoints = parseShapingPoints(
        req.query.shapingPoints,
      );
      const shapingPoints = effectiveShapingPoints(
        origin,
        destination,
        requestedShapingPoints,
        preferences,
        plannerNotes,
      );
      const automaticShapingApplied =
        shapingPoints.length > requestedShapingPoints.length;
      let selected: OsrmResponse;
      try {
        selected = await routeWithValhalla(
          originLat,
          originLng,
          destinationLat,
          destinationLng,
          shapingPoints,
          preferences,
          plannerNotes,
        );
        if (automaticShapingApplied) {
          try {
            const guardNotes: string[] = [];
            const guarded = await routeWithValhalla(
              originLat,
              originLng,
              destinationLat,
              destinationLng,
              requestedShapingPoints,
              preferences,
              guardNotes,
            );
            const selectedRoute = selected.routes?.[0];
            const guardedRoute = guarded.routes?.[0];
            if (
              selectedRoute &&
              guardedRoute &&
              (selectedRoute.distance > guardedRoute.distance * 1.42 ||
                selectedRoute.duration > guardedRoute.duration * 1.55)
            ) {
              plannerNotes.push(
                "Scenic corridor guard skipped the automatic scenic arc because it made the ride too inefficient.",
              );
              selected = guarded;
            }
          } catch {
            plannerNotes.push(
              "Scenic corridor guard could not compare a simpler route, so the scenic route was kept.",
            );
          }
        }
      } catch (error) {
        plannerNotes.push(
          `Valhalla preference routing unavailable: ${error instanceof Error ? error.message : "unknown error"}.`,
        );
        selected = await routeWithOsrm(
          originLat,
          originLng,
          destinationLat,
          destinationLng,
          shapingPoints,
          preferences,
          plannerNotes,
        );
      }

      res.json({
        ...selected,
        motoplanner: {
          preferences,
          notes: plannerNotes,
        },
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/auth/register", async (req, res, next) => {
    try {
      const body = registerSchema.parse(req.body);
      const existing = db
        .prepare(
          `
        SELECT id FROM users WHERE username = ? OR email = ?
      `,
        )
        .get(body.username, body.email);

      if (existing) {
        res.status(409).json({ error: "username or email already exists" });
        return;
      }

      const userId = randomUUID();
      const token = randomToken();
      const auditEnvelope = body.auditKey
        ? wrapAuditKey(body.auditKey, config.serverSecret)
        : null;
      const createdAt = nowIso();

      db.prepare(
        `
        INSERT INTO users (id, username, email, password_hash, kdf_salt, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `,
      ).run(
        userId,
        body.username,
        body.email.toLowerCase(),
        await hashPassword(body.password),
        randomBytes(32).toString("base64"),
        createdAt,
      );

      const user = db
        .prepare("SELECT kdf_salt FROM users WHERE id = ?")
        .get(userId) as { kdf_salt: string };
      db.prepare(
        `
        INSERT INTO sessions (token_hash, user_id, audit_key_envelope, expires_at, created_at)
        VALUES (?, ?, ?, ?, ?)
      `,
      ).run(
        hashToken(token),
        userId,
        auditEnvelope ? JSON.stringify(auditEnvelope) : null,
        expiresInDays(config.sessionDays),
        createdAt,
      );

      res.status(201).json({
        userId,
        username: body.username,
        email: body.email.toLowerCase(),
        token,
        kdfSalt: user.kdf_salt,
        auditKeyAttached: Boolean(auditEnvelope),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/auth/login", async (req, res, next) => {
    try {
      const body = loginSchema.parse(req.body);
      const user = db
        .prepare(
          `
        SELECT id, username, email, password_hash, kdf_salt
        FROM users
        WHERE username = ? OR email = ?
      `,
        )
        .get(body.identifier, body.identifier.toLowerCase()) as
        | {
            id: string;
            username: string;
            email: string;
            password_hash: string;
            kdf_salt: string;
          }
        | undefined;

      if (!user || !(await verifyPassword(user.password_hash, body.password))) {
        res.status(401).json({ error: "invalid credentials" });
        return;
      }

      const token = randomToken();
      const auditEnvelope = body.auditKey
        ? wrapAuditKey(body.auditKey, config.serverSecret)
        : null;
      db.prepare(
        `
        INSERT INTO sessions (token_hash, user_id, audit_key_envelope, expires_at, created_at)
        VALUES (?, ?, ?, ?, ?)
      `,
      ).run(
        hashToken(token),
        user.id,
        auditEnvelope ? JSON.stringify(auditEnvelope) : null,
        expiresInDays(config.sessionDays),
        nowIso(),
      );

      res.json({
        userId: user.id,
        username: user.username,
        email: user.email,
        token,
        kdfSalt: user.kdf_salt,
        auditKeyAttached: Boolean(auditEnvelope),
      });
    } catch (error) {
      next(error);
    }
  });

  app.post("/auth/logout", requireAuth, (req: AuthedRequest, res) => {
    audit(req, "logout");
    db.prepare("DELETE FROM sessions WHERE token_hash = ?").run(
      req.auth!.tokenHash,
    );
    res.status(204).send();
  });

  app.get("/routes", requireAuth, (req: AuthedRequest, res) => {
    audit(req, "routes.list");
    const rows = db
      .prepare(
        `
      SELECT id, name, encrypted_payload, preferences_json, created_at, updated_at
      FROM routes
      WHERE user_id = ?
      ORDER BY updated_at DESC
    `,
      )
      .all(req.auth!.userId) as Array<{
      id: string;
      name: string;
      encrypted_payload: string;
      preferences_json: string;
      created_at: string;
      updated_at: string;
    }>;

    res.json({
      routes: rows.map((row) => ({
        id: row.id,
        name: row.name,
        encryptedPayload: JSON.parse(row.encrypted_payload) as EncryptedPayload,
        preferences: JSON.parse(row.preferences_json),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      })),
    });
  });

  app.post("/routes", requireAuth, (req: AuthedRequest, res, next) => {
    try {
      const body = routeSchema.parse(req.body);
      const id = randomUUID();
      const timestamp = nowIso();

      db.prepare(
        `
        INSERT INTO routes (id, user_id, name, encrypted_payload, preferences_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `,
      ).run(
        id,
        req.auth!.userId,
        body.name,
        JSON.stringify(body.encryptedPayload),
        JSON.stringify(body.preferences),
        timestamp,
        timestamp,
      );

      audit(req, "routes.create", { routeId: id, routeName: body.name });
      res.status(201).json({ id, createdAt: timestamp, updatedAt: timestamp });
    } catch (error) {
      next(error);
    }
  });

  app.put(
    "/profile/home-address",
    requireAuth,
    (req: AuthedRequest, res, next) => {
      try {
        const body = profileSecretSchema.parse(req.body);
        const timestamp = nowIso();
        db.prepare(
          `
        INSERT INTO profile_secrets (user_id, kind, encrypted_payload, updated_at)
        VALUES (?, 'home_address', ?, ?)
        ON CONFLICT(user_id, kind) DO UPDATE SET
          encrypted_payload = excluded.encrypted_payload,
          updated_at = excluded.updated_at
      `,
        ).run(
          req.auth!.userId,
          JSON.stringify(body.encryptedPayload),
          timestamp,
        );

        audit(req, "profile.home_address.update");
        res.json({ updatedAt: timestamp });
      } catch (error) {
        next(error);
      }
    },
  );

  app.get("/profile/home-address", requireAuth, (req: AuthedRequest, res) => {
    audit(req, "profile.home_address.read");
    const row = db
      .prepare(
        `
      SELECT encrypted_payload, updated_at
      FROM profile_secrets
      WHERE user_id = ? AND kind = 'home_address'
    `,
      )
      .get(req.auth!.userId) as
      | { encrypted_payload: string; updated_at: string }
      | undefined;

    if (!row) {
      res.status(404).json({ error: "home address not set" });
      return;
    }

    res.json({
      encryptedPayload: JSON.parse(row.encrypted_payload) as EncryptedPayload,
      updatedAt: row.updated_at,
    });
  });

  app.use(
    (error: unknown, _req: Request, res: Response, _next: NextFunction) => {
      if (error && typeof error === "object" && "issues" in error) {
        res.status(400).json({
          error: "validation failed",
          issues: (error as { issues: unknown }).issues,
        });
        return;
      }

      console.error(error);
      res.status(500).json({ error: "internal server error" });
    },
  );

  return app;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const config = loadConfig();
  createApp({ config }).listen(config.port, () => {
    console.log(`MotoPlanner API listening on http://localhost:${config.port}`);
  });
}
