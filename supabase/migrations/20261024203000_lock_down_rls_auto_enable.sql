-- Hosted Supabase creates public.rls_auto_enable() (returns event_trigger,
-- security definer) so new public tables get rls automatically. The security
-- advisor flags it as executable by anon and authenticated via
-- /rest/v1/rpc/rls_auto_enable. A fresh local `supabase start` does not have
-- this function, so the revoke is guarded. Do not drop or alter the function:
-- the event trigger still fires without execute grants for those roles.

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end
$$;
