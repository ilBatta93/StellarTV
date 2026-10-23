import { describe, expect, it } from "vitest";
import { freshImdb, imdbCacheKey, parseOmdb } from "./imdbRatings";

describe("imdb ratings", () => {
  it("parses the official IMDb rating", () => {
    expect(parseOmdb("tt0903747", { imdbRating: "9.5", imdbVotes: "2,301,000" })).toEqual({ imdb_id: "tt0903747", rating: 9.5, votes: 2301000 });
  });
  it("treats missing ratings as unknown", () => {
    expect(parseOmdb("tt1", { imdbRating: "N/A" }).rating).toBeNull();
  });
  it("keeps cached ratings for 30 days", () => {
    const now = Date.parse("2026-10-23T00:00:00Z");
    expect(freshImdb("2026-09-24T01:00:00Z", now)).toBe(true);
    expect(freshImdb("2026-09-22T00:00:00Z", now)).toBe(false);
  });
  it("separates movies and series", () => {
    expect(imdbCacheKey("movie", 5)).not.toBe(imdbCacheKey("tv", 5));
  });
  it("isolates the episode rating from the series and every other episode", () => {
    expect(imdbCacheKey("tv", 1396, 1, 2)).toBe("v1:imdb:tv/1396/season/1/episode/2");
    expect(imdbCacheKey("tv", 1396, 1, 2)).not.toBe(imdbCacheKey("tv", 1396));
    expect(imdbCacheKey("tv", 1396, 1, 2)).not.toBe(imdbCacheKey("tv", 1396, 2, 2));
    expect(imdbCacheKey("tv", 1396, 1, 2)).not.toBe(imdbCacheKey("tv", 1396, 1, 3));
  });
});
