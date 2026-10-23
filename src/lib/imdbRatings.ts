// Shared IMDb rating cache rules (pure, testable).
export const IMDB_TTL_MS = 30 * 86400000;

export type ImdbRating = { imdb_id: string | null; rating: number | null; votes: number | null };

export const imdbCacheKey = (type: "movie" | "tv", id: number, season?: number, episode?: number) =>
  `v1:imdb:${type}/${id}${season !== undefined && episode !== undefined ? `/season/${season}/episode/${episode}` : ""}`;

export function freshImdb(updatedAt: string, now = Date.now()): boolean {
  const age = now - Date.parse(updatedAt);
  return Number.isFinite(age) && age >= 0 && age < IMDB_TTL_MS;
}

/** OMDb answer -> rating; "N/A" and malformed values become null. */
export function parseOmdb(imdbId: string, body: unknown): ImdbRating {
  const b = (body ?? {}) as Record<string, unknown>;
  const r = Number.parseFloat(String(b["imdbRating"] ?? ""));
  const v = Number.parseInt(String(b["imdbVotes"] ?? "").replace(/,/g, ""), 10);
  return {
    imdb_id: imdbId,
    rating: Number.isFinite(r) && r > 0 && r <= 10 ? Math.round(r * 10) / 10 : null,
    votes: Number.isFinite(v) && v >= 0 ? v : null,
  };
}

export function validCachedImdb(payload: unknown): payload is ImdbRating {
  if (!payload || typeof payload !== "object") return false;
  const p = payload as Record<string, unknown>;
  return (p["rating"] === null || typeof p["rating"] === "number") &&
    (p["imdb_id"] === null || typeof p["imdb_id"] === "string");
}
