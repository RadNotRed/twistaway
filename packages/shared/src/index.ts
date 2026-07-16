export type RoutePreferenceKey =
  | "twisty"
  | "scenic"
  | "avoidHighways"
  | "targetHighways"
  | "targetStraightRoads"
  | "avoidGravel"
  | "avoidTolls"
  | "fuelStops"
  | "restStops"
  | "weatherAware"
  | "trafficAware"
  | "policeReports";

export type RoutePreferences = Record<RoutePreferenceKey, number | boolean>;

export interface EncryptedPayload {
  version: 1;
  algorithm: "AES-256-GCM";
  nonce: string;
  ciphertext: string;
  tag: string;
  aad?: string;
  keyDerivation: "argon2id-hkdf-sha256";
}

export interface PlannedRouteSummary {
  id: string;
  name: string;
  createdAt: string;
  distanceMeters?: number;
  estimatedSeconds?: number;
  preferences: Partial<RoutePreferences>;
}

export const defaultRoutePreferences: RoutePreferences = {
  twisty: 0.75,
  scenic: 0.7,
  avoidHighways: true,
  targetHighways: false,
  targetStraightRoads: false,
  avoidGravel: true,
  avoidTolls: true,
  fuelStops: true,
  restStops: true,
  weatherAware: true,
  trafficAware: true,
  policeReports: false,
};
