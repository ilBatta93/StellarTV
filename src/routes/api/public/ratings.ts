import { createFileRoute } from "@tanstack/react-router";
import { z } from "zod";
import { sanitizeTitle, extractYear, tmdbGet } from "@/lib/tmdb.server";

// Shared TMDB vote cache: one request resolves many poster ratings, cached
// rows are served instantly and only unknown/stale titles hit TMDB.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const Body = z.object({
  items: z.array(z.object({ title: z.string().min(1).max(200), type: z.enum(["movie", "tv"]) })).max(60),
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const STALE_MS = 30 * 24 * 3600 * 1000;
const keyOf = (type: string, title: string) => `${type}:${sanitizeTitle(title).toLowerCase()}`;

async function lookup(title: string, type: "movie" | "tv") {
  const query = sanitizeTitle(title);
  if (!query) return { rating: 0, tmdbId: null as number | null };
  const year = extractYear(title);
  const params: Record<string, string> = { query, language: "it-IT" };
  if (year) params[type === "movie" ? "year" : "first_air_date_year"] = year;
  let search = await tmdbGet(`search/${type}`, params);
  if (!search?.results?.length && year) search = await tmdbGet(`search/${type}`, { query, language: "it-IT" });
  if (search == null) throw new Error("TMDB non disponibile");
  const hit = search.results?.[0];
  return { rating: Number(hit?.vote_average ?? 0) || 0, tmdbId: (hit?.id as number | undefined) ?? null };
}

export const Route = createFileRoute("/api/public/ratings")({
  server: {
    handlers: {
      OPTIONS: async () => new Response(null, { status: 200, headers: corsHeaders }),
      POST: async ({ request }) => {
        try {
          const parsed = Body.safeParse(await request.json().catch(() => null));
          if (!parsed.success) return json({ error: "Richiesta non valida" }, 400);
          const items = parsed.data.items.map((i) => ({ ...i, key: keyOf(i.type, i.title) }));
          const keys = [...new Set(items.map((i) => i.key))];
          if (!keys.length) return json({ results: [] });

          const { supabaseAdmin } = await import("@/integrations/external/admin.server");
          const { data, error } = await supabaseAdmin.from("tmdb_ratings").select("key,rating,tmdb_id,updated_at").in("key", keys);
          if (error) throw error;
          const ratings: Record<string, number> = {};
          const ids: Record<string, number | null> = {};
          const now = Date.now();
          for (const r of data ?? []) {
            if (now - new Date(r.updated_at).getTime() < STALE_MS) {
              ratings[r.key] = r.rating;
              ids[r.key] = r.tmdb_id;
            }
          }

          const missing = [...new Map(items.filter((i) => !(i.key in ratings)).map((i) => [i.key, i])).values()];
          const fresh: { key: string; rating: number; tmdb_id: number | null; updated_at: string }[] = [];
          for (let i = 0; i < missing.length; i += 6) {
            await Promise.all(
              missing.slice(i, i + 6).map(async (m) => {
                try {
                  const r = await lookup(m.title, m.type);
                  ratings[m.key] = r.rating;
                  ids[m.key] = r.tmdbId;
                  fresh.push({ key: m.key, rating: r.rating, tmdb_id: r.tmdbId, updated_at: new Date().toISOString() });
                } catch (e) {
                  console.error("ratings lookup failed", e);
                }
              }),
            );
          }
          if (fresh.length) {
            const { verifyBearerUser } = await import("@/lib/requireUser.server");
            if (await verifyBearerUser(request)) {
              const { error: upErr } = await supabaseAdmin.from("tmdb_ratings").upsert(fresh);
              if (upErr) console.error("ratings upsert failed", upErr);
            }
          }
          return json({ results: items.map((i) => (i.key in ratings ? ratings[i.key] : null)),
            identities: items.map(i => ({ type: i.type, id: ids[i.key] ?? null })) });
        } catch (err) {
          console.error("ratings failure", err);
          return json({ error: "Errore interno" }, 500);
        }
      },
    },
  },
});
