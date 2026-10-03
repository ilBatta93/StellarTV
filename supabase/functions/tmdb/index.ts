const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

const ALLOWED_PATHS = [
  /^trending\/(movie|tv|all)\/(day|week)$/,
  /^discover\/(movie|tv)$/,
  /^search\/(multi|movie|tv|person)$/,
  /^(movie|tv)\/\d+$/,
  /^(movie|tv)\/\d+\/(recommendations|similar|credits)$/,
  /^person\/\d+$/,
  /^person\/\d+\/(combined_credits|movie_credits|tv_credits)$/,
  /^discover\/(movie|tv)\/with_cast$/,
  /^discover\/(movie|tv)\/with_crew$/,
];

const ALLOWED_PARAMS = [
  "page",
  "query",
  "with_watch_providers",
  "watch_region",
  "watch_monetization_types",
  "sort_by",
  "language",
  "region",
  "with_cast",
  "with_crew",
  "with_genres",
  "with_origin_country",
  "with_keywords",
];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("TMDB_API_KEY");
    if (!apiKey) return json({ error: "TMDB non configurato" }, 503);

    const url = new URL(req.url);
    const path = (url.searchParams.get("path") ?? "").replace(/^\/+/, "");
    if (!ALLOWED_PATHS.some((re) => re.test(path))) {
      return json({ error: "Percorso non consentito" }, 400);
    }

    const target = new URL(`https://api.themoviedb.org/3/${path}`);
    for (const key of ALLOWED_PARAMS) {
      const value = url.searchParams.get(key);
      if (value) target.searchParams.set(key, value.slice(0, 200));
    }
    if (!target.searchParams.has("language")) {
      target.searchParams.set("language", "it-IT");
    }

    const isBearer = apiKey.startsWith("eyJ");
    if (!isBearer) target.searchParams.set("api_key", apiKey);

    const res = await fetch(target, {
      headers: isBearer ? { Authorization: `Bearer ${apiKey}` } : {},
    });
    if (!res.ok) return json({ error: "Errore TMDB" }, res.status === 404 ? 404 : 502);

    return json(await res.json());
  } catch (_err) {
    return json({ error: "Errore interno" }, 500);
  }
});
