-- Sheep backend: per-user mirror of on-device data + Gemini proxy quota.
-- Every row belongs to an (anonymous) Supabase Auth user. The device stays the
-- source of truth; these tables are a fire-and-forget backup written by the app.
--
-- Access model (same for every table):
--   * RLS on, policies only `to authenticated` with `(select auth.uid()) = user_id`.
--   * `anon` gets nothing; `authenticated` gets only the verbs the app needs.
--   * `user_id` defaults to auth.uid(), so clients never send it.

-- ---------------------------------------------------------------------------
-- events: mirror of Documents/memory/events.jsonl (append-only)
-- ---------------------------------------------------------------------------
create table public.events (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id  uuid not null,
  ts         timestamptz not null,
  type       text not null check (char_length(type) between 1 and 40),
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  -- idempotent retries: the app upserts with on_conflict=user_id,client_id.
  -- Leading user_id also serves as the FK / RLS index.
  constraint events_user_client_key unique (user_id, client_id)
);
comment on table public.events is 'Sheep event log mirror. Never contains DM/post content.';

create index events_user_ts_idx on public.events (user_id, ts desc);

alter table public.events enable row level security;

create policy "events: select own" on public.events
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "events: insert own" on public.events
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- memory_files: backup of the markdown memory files (path relative to memory/)
-- ---------------------------------------------------------------------------
create table public.memory_files (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  path       text not null check (char_length(path) between 1 and 512),
  content    text not null check (char_length(content) <= 200000),
  updated_at timestamptz not null default now(),
  primary key (user_id, path)
);

alter table public.memory_files enable row level security;

create policy "memory_files: select own" on public.memory_files
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "memory_files: insert own" on public.memory_files
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "memory_files: update own" on public.memory_files
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "memory_files: delete own" on public.memory_files
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- sessions: one row per finished Focus / Rest / Play session
-- ---------------------------------------------------------------------------
create table public.sessions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_id   uuid not null,
  mode        text not null check (mode in ('idle', 'focus', 'rest', 'play')),
  title       text check (char_length(title) <= 500),
  planned_min integer check (planned_min >= 0),
  actual_min  double precision check (actual_min >= 0),
  done        integer check (done >= 0),
  total       integer check (total >= 0),
  xp          integer,
  started_at  timestamptz,
  ended_at    timestamptz not null,
  created_at  timestamptz not null default now(),
  constraint sessions_user_client_key unique (user_id, client_id)
);

create index sessions_user_ended_idx on public.sessions (user_id, ended_at desc);

alter table public.sessions enable row level security;

create policy "sessions: select own" on public.sessions
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "sessions: insert own" on public.sessions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "sessions: update own" on public.sessions
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- daily_scores: one row per local calendar day
-- ---------------------------------------------------------------------------
create table public.daily_scores (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date       date not null,
  score      integer not null,
  focus      integer not null default 0,
  rest       integer not null default 0,
  play       integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, date)
);

alter table public.daily_scores enable row level security;

create policy "daily_scores: select own" on public.daily_scores
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "daily_scores: insert own" on public.daily_scores
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "daily_scores: update own" on public.daily_scores
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- gemini_calls + consume_gemini_quota(): per-user rate limit for the proxy
-- ---------------------------------------------------------------------------
-- The `gemini` Edge Function calls `rpc/consume_gemini_quota` with the caller's
-- JWT. The function is SECURITY INVOKER, so RLS still applies: a user can only
-- see/insert their own rows and can only delete rows older than a day, so they
-- can't reset their own quota. Calling the RPC directly only burns their quota.
create table public.gemini_calls (
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index gemini_calls_user_created_idx on public.gemini_calls (user_id, created_at desc);

alter table public.gemini_calls enable row level security;

create policy "gemini_calls: select own" on public.gemini_calls
  for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "gemini_calls: insert own" on public.gemini_calls
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "gemini_calls: delete own old" on public.gemini_calls
  for delete to authenticated
  using ((select auth.uid()) = user_id and created_at < now() - interval '1 day');

create function public.consume_gemini_quota(
  per_minute integer default 30,
  per_day    integer default 500
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  uid        uuid := auth.uid();
  minute_cnt integer;
  day_cnt    integer;
begin
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  -- Serialise concurrent calls from the same user so the counts are exact.
  perform pg_advisory_xact_lock(hashtextextended(uid::text, 0));

  delete from public.gemini_calls
   where user_id = uid and created_at < now() - interval '2 days';

  select count(*) filter (where created_at > now() - interval '1 minute'),
         count(*)
    into minute_cnt, day_cnt
    from public.gemini_calls
   where user_id = uid and created_at > now() - interval '1 day';

  if minute_cnt >= least(per_minute, 30) then
    return jsonb_build_object('allowed', false, 'reason', 'minute', 'minute', minute_cnt, 'day', day_cnt);
  end if;
  if day_cnt >= least(per_day, 500) then
    return jsonb_build_object('allowed', false, 'reason', 'day', 'minute', minute_cnt, 'day', day_cnt);
  end if;

  insert into public.gemini_calls (user_id) values (uid);
  return jsonb_build_object('allowed', true, 'minute', minute_cnt + 1, 'day', day_cnt + 1);
end;
$$;

comment on function public.consume_gemini_quota(integer, integer) is
  'Records one Gemini proxy call for auth.uid() if under 30/min and 500/day. Limits can only be lowered by callers.';

-- ---------------------------------------------------------------------------
-- Privileges: least privilege for the Data API roles
-- ---------------------------------------------------------------------------
revoke all on table public.events, public.memory_files, public.sessions,
                    public.daily_scores, public.gemini_calls
  from anon, authenticated;

grant select, insert                 on table public.events       to authenticated;
grant select, insert, update, delete on table public.memory_files to authenticated;
grant select, insert, update         on table public.sessions     to authenticated;
grant select, insert, update         on table public.daily_scores to authenticated;
grant select, insert, delete         on table public.gemini_calls to authenticated;

revoke execute on function public.consume_gemini_quota(integer, integer) from public, anon;
grant  execute on function public.consume_gemini_quota(integer, integer) to authenticated;
