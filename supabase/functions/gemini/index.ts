// Supabase Edge Function entrypoint. Logic lives in handler.ts (unit-tested in handler_test.ts).
import { createHandler } from "./handler.ts";

Deno.serve(createHandler({ fetch, env: (name) => Deno.env.get(name) }));
