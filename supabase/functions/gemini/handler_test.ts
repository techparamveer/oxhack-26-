// deno test supabase/functions/gemini/
import { ALLOWED_MODELS, createHandler, type Deps, projectApiKey } from "./handler.ts";

function assertEquals<T>(actual: T, expected: T, msg = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg} expected ${e}, got ${a}`);
}

type Call = { url: string; init: RequestInit };

function setup(opts: {
  env?: Record<string, string>;
  quota?: Response | (() => Promise<Response>);
  upstream?: (init: RequestInit) => Promise<Response>;
  timeoutMs?: number;
} = {}) {
  const calls: Call[] = [];
  const env: Record<string, string> = {
    GEMINI_API_KEY: "test-gemini-key",
    SUPABASE_URL: "https://ref.supabase.co",
    SUPABASE_ANON_KEY: "anon-key",
    ...opts.env,
  };
  const fakeFetch = ((input: string | URL | Request, init: RequestInit = {}): Promise<Response> => {
    const url = String(input);
    calls.push({ url, init });
    if (url.includes("/rest/v1/rpc/consume_gemini_quota")) {
      const q = opts.quota ?? new Response(JSON.stringify({ allowed: true }), { status: 200 });
      return typeof q === "function" ? q() : Promise.resolve(q.clone());
    }
    if (opts.upstream) return opts.upstream(init);
    const ok = { candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }] };
    return Promise.resolve(new Response(JSON.stringify(ok), { status: 200 }));
  }) as typeof fetch;
  const deps: Deps = { fetch: fakeFetch, env: (k) => env[k], timeoutMs: opts.timeoutMs };
  return { handler: createHandler(deps), calls };
}

function req(body: unknown, init: RequestInit = {}) {
  return new Request("https://ref.supabase.co/functions/v1/gemini", {
    method: "POST",
    headers: { Authorization: "Bearer user-jwt", apikey: "sb_publishable_x", "Content-Type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
    ...init,
  });
}

const valid = {
  model: "gemini-flash-latest",
  systemInstruction: { parts: [{ text: "sys" }] },
  contents: [{ role: "user", parts: [{ text: "hi" }] }],
  generationConfig: { responseMimeType: "application/json", temperature: 0.5 },
};

Deno.test("proxies a valid request and passes Gemini JSON through", async () => {
  const { handler, calls } = setup();
  const res = await handler(req(valid));
  assertEquals(res.status, 200);
  assertEquals((await res.json()).candidates[0].content.parts[0].text, '{"ok":true}');
  assertEquals(calls.length, 2);
  // quota is checked as the caller
  const q = calls[0];
  assertEquals(q.url, "https://ref.supabase.co/rest/v1/rpc/consume_gemini_quota");
  const qh = q.init.headers as Record<string, string>;
  assertEquals(qh.Authorization, "Bearer user-jwt");
  assertEquals(qh.apikey, "anon-key");
  // upstream gets the secret key in a header, never in the URL
  const u = calls[1];
  assertEquals(u.url, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent");
  assertEquals((u.init.headers as Record<string, string>)["x-goog-api-key"], "test-gemini-key");
  const sent = JSON.parse(u.init.body as string);
  assertEquals(Object.keys(sent).sort(), ["contents", "generationConfig", "systemInstruction"]);
});

Deno.test("strips unexpected fields and defaults the model", async () => {
  const { handler, calls } = setup();
  const { model: _m, ...noModel } = valid;
  const res = await handler(req({ ...noModel, tools: [{ codeExecution: {} }], safetySettings: [] }));
  assertEquals(res.status, 200);
  assertEquals(calls[1].url.includes("/models/gemini-flash-latest:"), true);
  assertEquals(Object.keys(JSON.parse(calls[1].init.body as string)).sort(), [
    "contents",
    "generationConfig",
    "systemInstruction",
  ]);
});

Deno.test("passes through upstream non-2xx status and body (e.g. 403 API_KEY_SERVICE_BLOCKED)", async () => {
  const body = JSON.stringify({
    error: { code: 403, status: "PERMISSION_DENIED", message: "API_KEY_SERVICE_BLOCKED" },
  });
  const { handler } = setup({ upstream: () => Promise.resolve(new Response(body, { status: 403 })) });
  const res = await handler(req(valid));
  assertEquals(res.status, 403);
  assertEquals(await res.text(), body);
});

Deno.test("rejects models outside the allowlist without calling anything", async () => {
  const { handler, calls } = setup();
  for (const model of ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-flash-preview"]) {
    const res = await handler(req({ ...valid, model }));
    assertEquals(res.status, 400, model);
  }
  assertEquals(calls.length, 0);
  for (const model of [
    "gemini-flash-latest",
    "gemini-flash-lite-latest",
    "gemini-3.8-flash",
    "gemini-3.7-flash",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
  ]) {
    assertEquals(ALLOWED_MODELS.has(model), true, model);
  }
});

Deno.test("rejects bad bodies", async () => {
  const { handler } = setup();
  assertEquals((await handler(req("not json"))).status, 400);
  assertEquals((await handler(req([1, 2]))).status, 400);
  assertEquals((await handler(req({ model: "gemini-flash-latest" }))).status, 400);
  assertEquals((await handler(req("x".repeat(300 * 1024)))).status, 413);
});

Deno.test("method handling: OPTIONS 204, GET 405", async () => {
  const { handler } = setup();
  assertEquals((await handler(new Request("https://x/", { method: "OPTIONS" }))).status, 204);
  assertEquals((await handler(new Request("https://x/", { method: "GET" }))).status, 405);
});

Deno.test("503 when the Gemini secret is missing", async () => {
  const { handler, calls } = setup({ env: { GEMINI_API_KEY: "" } });
  assertEquals((await handler(req(valid))).status, 503);
  assertEquals(calls.length, 0);
});

Deno.test("429 when the per-user quota is exhausted; upstream not called", async () => {
  const { handler, calls } = setup({
    quota: new Response(JSON.stringify({ allowed: false, reason: "minute" }), { status: 200 }),
  });
  const res = await handler(req(valid));
  assertEquals(res.status, 429);
  assertEquals(calls.length, 1);
});

Deno.test("503 (fail closed) when the quota RPC errors", async () => {
  const { handler, calls } = setup({ quota: new Response("{}", { status: 404 }) });
  assertEquals((await handler(req(valid))).status, 503);
  assertEquals(calls.length, 1);
});

Deno.test("401 when Authorization is missing; quota and Gemini never called", async () => {
  const { handler, calls } = setup();
  const res = await handler(req(valid, {
    headers: { apikey: "sb_publishable_x", "Content-Type": "application/json" },
  }));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.status, "UNAUTHENTICATED");
  assertEquals(calls.length, 0);
});

Deno.test("401 when the quota RPC rejects the caller JWT", async () => {
  const { handler, calls } = setup({
    quota: new Response(JSON.stringify({ code: "PGRST301", message: "JWT expired" }), { status: 401 }),
  });
  const res = await handler(req(valid));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error.status, "UNAUTHENTICATED");
  assertEquals(calls.length, 1);
  assertEquals(calls[0].url.includes("/rest/v1/rpc/consume_gemini_quota"), true);
});

Deno.test("503 when the quota RPC returns 500", async () => {
  const { handler, calls } = setup({ quota: new Response("boom", { status: 500 }) });
  const res = await handler(req(valid));
  assertEquals(res.status, 503);
  assertEquals((await res.json()).error.status, "UNAVAILABLE");
  assertEquals(calls.length, 1);
});

Deno.test("504 when Gemini exceeds the upstream timeout", async () => {
  const { handler } = setup({
    timeoutMs: 20,
    upstream: (init) =>
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
      }),
  });
  assertEquals((await handler(req(valid))).status, 504);
});

Deno.test("502 when Gemini is unreachable", async () => {
  const { handler } = setup({ upstream: () => Promise.reject(new TypeError("dns")) });
  assertEquals((await handler(req(valid))).status, 502);
});

Deno.test("projectApiKey prefers the new publishable keys", () => {
  assertEquals(
    projectApiKey((k) =>
      ({ SUPABASE_PUBLISHABLE_KEYS: '{"default":"sb_publishable_1"}', SUPABASE_ANON_KEY: "a" } as Record<
        string,
        string
      >)[k]
    ),
    "sb_publishable_1",
  );
  assertEquals(projectApiKey((k) => ({ SUPABASE_ANON_KEY: "a" } as Record<string, string>)[k]), "a");
  assertEquals(
    projectApiKey((k) =>
      ({ SUPABASE_PUBLISHABLE_KEYS: "garbage", SUPABASE_ANON_KEY: "a" } as Record<string, string>)[k]
    ),
    "a",
  );
});
