// Gemini proxy for the Sheep iOS app.
//
// POST /functions/v1/gemini
// Gateway verify_jwt stays on (rejects malformed JWTs). The function itself
// returns 401 unless the quota RPC accepts the caller's user JWT.
// body: { model?, systemInstruction, contents, generationConfig }
// → Gemini's generateContent JSON, with Gemini's status code passed through so the
//   app can fall back to its hardcoded copy on any non-2xx.
//
// Pure handler (no globals) so it can be unit-tested with a fake fetch/env.

// Flash-family only. 2.x is retired for new users; gemini-flash-latest currently resolves to 3.8.
export const ALLOWED_MODELS = new Set<string>([
  "gemini-flash-latest",
  "gemini-flash-lite-latest",
  "gemini-3.8-flash",
  "gemini-3.7-flash",
  "gemini-3.5-flash",
  "gemini-3.5-flash-lite",
]);
export const DEFAULT_MODEL = "gemini-flash-latest";
export const UPSTREAM_TIMEOUT_MS = 15_000;
export const MAX_BODY_BYTES = 256 * 1024;

export interface Deps {
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
  timeoutMs?: number;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS, ...extra },
  });
}

function error(status: number, code: string, message: string): Response {
  return json(status, { error: { code: status, status: code, message } });
}

/** First publishable key from the new `SUPABASE_PUBLISHABLE_KEYS` JSON, else the legacy anon key. */
export function projectApiKey(env: Deps["env"]): string | undefined {
  const keys = env("SUPABASE_PUBLISHABLE_KEYS");
  if (keys) {
    try {
      const parsed = JSON.parse(keys) as Record<string, string>;
      const key = parsed["default"] ?? Object.values(parsed)[0];
      if (key) return key;
    } catch { /* fall through */ }
  }
  return env("SUPABASE_ANON_KEY");
}

type QuotaOk = { allowed: boolean; reason?: string };
type QuotaOutcome =
  | { status: "ok"; quota: QuotaOk }
  | { status: "unauthenticated" }
  | { status: "unavailable" };

function bearerToken(req: Request): string | null {
  const auth = req.headers.get("authorization");
  if (!auth) return null;
  const match = /^Bearer\s+(\S+)/i.exec(auth.trim());
  return match?.[1] ?? null;
}

/** Calls `rpc/consume_gemini_quota` as the caller (their JWT → RLS applies). */
async function consumeQuota(req: Request, deps: Deps): Promise<QuotaOutcome> {
  const auth = req.headers.get("authorization");
  if (!bearerToken(req) || !auth) return { status: "unauthenticated" };
  const base = deps.env("SUPABASE_URL");
  const apikey = projectApiKey(deps.env) ?? req.headers.get("apikey") ?? undefined;
  if (!base || !apikey) return { status: "unavailable" };
  try {
    const res = await deps.fetch(`${base.replace(/\/$/, "")}/rest/v1/rpc/consume_gemini_quota`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey, Authorization: auth },
      body: "{}",
      signal: AbortSignal.timeout(3_000),
    });
    if (res.status === 401 || res.status === 403) {
      console.error("quota rpc failed", res.status, (await res.text()).slice(0, 200));
      return { status: "unauthenticated" };
    }
    if (!res.ok) {
      console.error("quota rpc failed", res.status, (await res.text()).slice(0, 200));
      return { status: "unavailable" };
    }
    return { status: "ok", quota: (await res.json()) as QuotaOk };
  } catch (e) {
    console.error("quota rpc error", String(e));
    return { status: "unavailable" };
  }
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const timeoutMs = deps.timeoutMs ?? UPSTREAM_TIMEOUT_MS;

  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    if (req.method !== "POST") return error(405, "METHOD_NOT_ALLOWED", "POST only");

    const apiKey = deps.env("GEMINI_API_KEY");
    if (!apiKey) return error(503, "UNAVAILABLE", "GEMINI_API_KEY secret is not set");

    const raw = await req.text();
    if (raw.length > MAX_BODY_BYTES) return error(413, "PAYLOAD_TOO_LARGE", "Request body too large");

    let body: Record<string, unknown>;
    try {
      const parsed = JSON.parse(raw);
      if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error("not an object");
      body = parsed as Record<string, unknown>;
    } catch {
      return error(400, "INVALID_ARGUMENT", "Body must be a JSON object");
    }

    const model = typeof body.model === "string" && body.model ? body.model : DEFAULT_MODEL;
    if (!ALLOWED_MODELS.has(model)) return error(400, "INVALID_ARGUMENT", `Model not allowed: ${model}`);
    if (!Array.isArray(body.contents) || body.contents.length === 0) {
      return error(400, "INVALID_ARGUMENT", "contents is required");
    }

    if (!bearerToken(req)) {
      return error(401, "UNAUTHENTICATED", "Sign-in required");
    }

    const outcome = await consumeQuota(req, deps);
    if (outcome.status === "unauthenticated") {
      return error(401, "UNAUTHENTICATED", "Sign-in required");
    }
    if (outcome.status === "unavailable") return error(503, "UNAVAILABLE", "Quota check failed");
    if (!outcome.quota.allowed) {
      return error(429, "RESOURCE_EXHAUSTED", `Rate limit (${outcome.quota.reason ?? "quota"})`);
    }

    // Forward only the fields we expect; drop anything else (tools, safety overrides, …).
    const upstreamBody: Record<string, unknown> = { contents: body.contents };
    if (body.systemInstruction !== undefined) upstreamBody.systemInstruction = body.systemInstruction;
    if (body.generationConfig !== undefined) upstreamBody.generationConfig = body.generationConfig;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const upstream = await deps.fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
          body: JSON.stringify(upstreamBody),
          signal: controller.signal,
        },
      );
      const text = await upstream.text();
      if (!upstream.ok) console.error("gemini upstream", upstream.status, text.slice(0, 300));
      return new Response(text, {
        status: upstream.status,
        headers: { "Content-Type": "application/json", ...CORS },
      });
    } catch (e) {
      if (controller.signal.aborted) return error(504, "DEADLINE_EXCEEDED", "Gemini timed out");
      console.error("gemini fetch error", String(e));
      return error(502, "BAD_GATEWAY", "Gemini unreachable");
    } finally {
      clearTimeout(timer);
    }
  };
}
