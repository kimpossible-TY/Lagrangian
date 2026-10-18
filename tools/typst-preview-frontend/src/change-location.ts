export type ChangeLocation = [number, number, number];

export { ChangeLocationQueue } from "../../flow-reader/web/change-location.js";

export function parseChangeLocation(payload: string): ChangeLocation | undefined {
  const location = payload.trim().split(/\s+/).map(Number);
  if (
    location.length !== 3 ||
    !location.every(Number.isFinite) ||
    !Number.isSafeInteger(location[0]) ||
    location[0] < 1 ||
    location[1] < 0 ||
    location[2] < 0
  )
    return undefined;
  return location as ChangeLocation;
}
