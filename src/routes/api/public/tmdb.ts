import { createFileRoute } from "@tanstack/react-router";
import { cachedMetadata, metadataCacheKey } from "@/lib/tmdbMetadataCache";
import type { Json } from "@/integrations/external/types";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const ALLOWED_PATHS = [
  /^trending\/(movie|tv|all)\/(day|week)$/,
  /^discover\/(movie|tv)$/,
  /^search\/(multi|movie|tv|person)$/,
  /^(movie|tv)\/\d+$/,
  /^tv\/[1-9]\d{0,8}\/season\/\d{1,3}$/,
  /^(movie|tv)\/\d+\/(recommendations|similar|credits|external_ids|release_dates|content_ratings|images|videos|watch\/providers)$/,
  /^person\/\d+$/,
  /^person\/\d+\/(combined_credits|movie_credits|tv_credits)$/,
  /^discover\/(movie|tv)\/with_cast$/,
  /^discover\/(movie|tv)\/with_crew$/,
];

const ALLOWED_PARAMS = [
  "page", "query", "with_watch_providers", "watch_region", "watch_monetization_types",
  "sort_by", "language", "region", "with_cast", "with_crew", "with_genres",
  "with_origin_country", "with_keywords", "include_image_language",
];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export const Route = createFileRoute("/api/public/tmdb")({
  server: {
    handlers: {
      OPTIONS: async () => new Response(null, { status: 200, headers: corsHeaders }),
      GET: async ({ request }) => {
        try {
          const apiKey = (process.env["TMDB_API_KEY"] ?? "").trim();
          if (!apiKey) {
            console.error("[tmdb] TMDB_API_KEY mancante nell'ambiente del server");
            return json({ error: "TMDB non configurato" }, 503);
          }

          const url = new URL(request.url);
          const path = (url.searchParams.get("path") ?? "").replace(/^\/+/, "");
          if (!ALLOWED_PATHS.some((re) => re.test(path))) {
            return json({ error: "Percorso non consentito" }, 400);
          }

          const target = new URL(`https://api.themoviedb.org/3/${path}`);
          for (const key of ALLOWED_PARAMS) {
            const value = url.searchParams.get(key);
            if (value) target.searchParams.set(key, value.slice(0, 200));
          }
          if (!target.searchParams.has("language")) target.searchParams.set("language", "it-IT");

          const isBearer = apiKey.startsWith("eyJ");
          if (!isBearer) target.searchParams.set("api_key", apiKey);

          const cacheParams = new URLSearchParams(target.searchParams);
          cacheParams.delete("api_key");
          const key = metadataCacheKey(path, cacheParams);
          const payload = await cachedMetadata(key, {
            read: async (cacheKey) => {
              const { supabaseAdmin } = await import("@/integrations/external/admin.server");
              const { data, error } = await supabaseAdmin.from("tmdb_metadata_cache")
                .select("payload, updated_at").eq("key", cacheKey).maybeSingle();
              if (error) return null;
              return data;
            },
            fetch: async () => {
              const res = await fetch(target, {
                headers: isBearer ? { Authorization: `Bearer ${apiKey}` } : {},
              });
              if (!res.ok) {
                console.error(`TMDB error [${res.status}]: ${await res.text()}`);
                throw new Response(null, { status: res.status === 404 ? 404 : 502 });
              }
              return await res.json() as Json;
            },
            authorized: async () => {
              const { verifyBearerUser } = await import("@/lib/requireUser.server");
              return !!await verifyBearerUser(request);
            },
            write: async (cacheKey, result) => {
              const { supabaseAdmin } = await import("@/integrations/external/admin.server");
              const { error } = await supabaseAdmin.from("tmdb_metadata_cache")
                .upsert({ key: cacheKey, payload: result, updated_at: new Date().toISOString() });
              if (error) throw error;
            },
          });
          return json(payload);
        } catch (err) {
          if (err instanceof Response) return json({ error: "Errore TMDB" }, err.status);
          console.error("TMDB proxy failure", err);
          return json({ error: "Errore interno" }, 500);
        }
      },
    },
  },
});
