import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { tmdbGet } from "@/lib/tmdb.server";
import { freshImdb, imdbCacheKey, parseOmdb, validCachedImdb, type ImdbRating } from "@/lib/imdbRatings";
import type { Json } from "@/integrations/external/types";

// Official IMDb ratings for TMDB titles, served from the shared cache and
// resolved (TMDB external id -> OMDb) only for missing or stale titles.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};
const Body = z.object({
  cacheOnly: z.boolean().optional(),
  items: z.array(z.object({
    type: z.enum(["movie", "tv"]), id: z.number().int().positive().max(999999999),
    season: z.number().int().min(0).max(999).optional(),
    episode: z.number().int().min(1).max(9999).optional(),
  }).refine(i => (i.season === undefined && i.episode === undefined) ||
    (i.type === "tv" && i.season !== undefined && i.episode !== undefined))).min(1).max(40),
});
// OMDb free keys are daily-limited: after a limit/auth error stop calling
// it from this worker for a while instead of burning the remaining quota.
let omdbPausedUntil = 0;
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

async function resolve(type: "movie" | "tv", id: number, omdbKey: string, season?: number, episode?: number): Promise<ImdbRating | null> {
  const path = season !== undefined && episode !== undefined
    ? `tv/${id}/season/${season}/episode/${episode}/external_ids` : `${type}/${id}/external_ids`;
  const ids = await tmdbGet(path);
  if (ids == null) return null;
  const imdb = typeof ids.imdb_id === "string" && /^tt\d{5,10}$/.test(ids.imdb_id) ? ids.imdb_id : null;
  if (!imdb) return { imdb_id: null, rating: null, votes: null };
  const res = await fetch(`https://www.omdbapi.com/?i=${imdb}&apikey=${encodeURIComponent(omdbKey)}`);
  if (!res.ok) { if (res.status === 401 || res.status === 429) omdbPausedUntil = Date.now() + 3600000; return null; }
  const body = await res.json();
  if (body && (body as { Response?: string }).Response === "False" && /limit|key/i.test(String((body as { Error?: string }).Error ?? ""))) {
    omdbPausedUntil = Date.now() + 3600000;
    return null;
  }
  return parseOmdb(imdb, body);
}

export const Route = createFileRoute("/api/public/imdb-ratings")({
  server: {
    handlers: {
      OPTIONS: async () => new Response(null, { status: 204, headers: corsHeaders }),
      POST: async ({ request }) => {
        try {
          const parsed = Body.safeParse(await request.json().catch(() => null));
          if (!parsed.success) return json({ error: "Richiesta non valida" }, 400);
            const items = [...new Map(parsed.data.items.map((i) => [imdbCacheKey(i.type, i.id, i.season, i.episode), i])).entries()];
          const { supabaseAdmin } = await import("@/integrations/external/admin.server");
          const results: Record<string, ImdbRating> = {};
          const stale: Record<string, ImdbRating> = {};
          try {
            const { data } = await supabaseAdmin.from("tmdb_metadata_cache")
              .select("key,payload,updated_at").in("key", items.map(([k]) => k));
            for (const r of data ?? []) {
              if (!validCachedImdb(r.payload)) continue;
              if (freshImdb(r.updated_at)) results[r.key] = r.payload;
              else stale[r.key] = r.payload;
            }
          } catch { /* Optional cache table. */ }

          const omdbKey = (process.env["OMDB_API_KEY"] ?? "").trim();
          const missing = items.filter(([k]) => !(k in results));
          const fresh: { key: string; payload: Json; updated_at: string }[] = [];
          // Sorting asks cache-only: shared values (even stale) and no external calls.
          if (parsed.data.cacheOnly) Object.assign(results, Object.fromEntries(Object.entries(stale).filter(([k]) => !(k in results))));
          if (omdbKey && !parsed.data.cacheOnly && Date.now() >= omdbPausedUntil) {
            for (let i = 0; i < missing.length; i += 6) {
              await Promise.all(missing.slice(i, i + 6).map(async ([key, it]) => {
                if (Date.now() < omdbPausedUntil) return;
                try {
                  const r = await resolve(it.type, it.id, omdbKey, it.season, it.episode);
                  if (!r) return;
                  results[key] = r;
                  fresh.push({ key, payload: r as unknown as Json, updated_at: new Date().toISOString() });
                } catch (e) { console.error("imdb rating lookup failed", e); }
              }));
            }
          }
          // A failed refresh keeps the previous shared value instead of "unknown".
          for (const [k, v] of Object.entries(stale)) if (!(k in results)) results[k] = v;
          if (fresh.length) {
            const { verifyBearerUser } = await import("@/lib/requireUser.server");
            if (await verifyBearerUser(request)) {
              const { error } = await supabaseAdmin.from("tmdb_metadata_cache").upsert(fresh);
              if (error) console.error("imdb cache write failed", error);
            }
          }
          return json({
            results: items.map(([key, it]) => ({ ...it, ...(results[key] ?? { imdb_id: null, rating: null, votes: null }), known: key in results })),
          });
        } catch (err) {
          console.error("imdb ratings failure", err);
          return json({ error: "Errore interno" }, 500);
        }
      },
    },
  },
});
