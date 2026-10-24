# Sheep

Screen-time app with Focus / Rest / Play modes, wrapped Instagram/YouTube, a Gemini coach and on-device memory. OxHack '26 (theme: TIME).

## Run
1. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and paste a Gemini key (optional — without one every call uses offline fallbacks).
2. Open `Sheep.xcodeproj`, pick your Personal Team under Signing, run on an iPhone or the Simulator.
3. Long-press the sheep for the dev menu (fast timers, seed yesterday, run consolidator, reset).

## Backend deploy
Run from the repo root. Needs Supabase CLI ≥ 2.122 (any install method).

```sh
supabase login
supabase link --project-ref wfrlvenjytnowvjuzgom
```

No DB password needed when logged in.

```sh
supabase db push --linked --dry-run
supabase db push --linked
```

```sh
umask 077
tmp=$(mktemp)
sed -n 's/^GEMINI_API_KEY *= *//p' Config/Secrets.xcconfig | tr -d '[:space:]' | sed 's/^/GEMINI_API_KEY=/' > "$tmp"
grep -q '^GEMINI_API_KEY=.\+' "$tmp" || { echo "GEMINI_API_KEY missing from Config/Secrets.xcconfig" >&2; rm -f "$tmp"; exit 1; }
supabase secrets set --env-file "$tmp"
rm -f "$tmp"
supabase secrets list
```

`secrets list` shows a digest only. Never echo the key.

```sh
deno test supabase/functions/gemini/
supabase functions deploy gemini --use-api
```

JWT verification stays on through `config.toml`.

**Auth:** do not run `supabase config push` against this project. It would also flip remote email confirmations, TOTP MFA, OTP length and `site_url`. Set only the two anonymous-auth keys with the Management API. `$SUPABASE_ACCESS_TOKEN` is a personal access token from the dashboard (Account → Access Tokens), not the project's anon or service_role key.

```sh
curl -X PATCH 'https://api.supabase.com/v1/projects/wfrlvenjytnowvjuzgom/config/auth' \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"external_anonymous_users_enabled": true, "rate_limit_anonymous_users": 300}'
```

**App:** get the publishable key. Plain `supabase projects api-keys` would also print the legacy `service_role` JWT in full, so filter it:

```sh
supabase projects api-keys --project-ref wfrlvenjytnowvjuzgom -o json | jq -r '.[] | select(.type == "publishable") | .api_key'
```

Put `SUPABASE_HOST = wfrlvenjytnowvjuzgom.supabase.co` (bare host; xcconfig treats `//` as a comment) and `SUPABASE_ANON_KEY = sb_publishable_…` into the git-ignored `Config/Secrets.xcconfig`. Never use the secret/service_role key.

**Checks:** Security/Performance advisors in the dashboard (or Management API `GET /v1/projects/{ref}/advisors/security|performance`). Accepted remaining items: WARN `auth_allow_anonymous_sign_ins` (by design: the app uses anonymous auth), WARN `auth_leaked_password_protection` (no password sign-ins; feature needs a paid plan), plus INFO `unused_index` on a fresh DB.

Spec: `docs/`. Agent conventions: `AGENTS.md`. Regenerate the project with `xcodegen generate` only if `project.yml` changes.
