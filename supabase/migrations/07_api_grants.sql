-- =====================================================================
-- BillAlert — 07_api_grants.sql
-- Let the PostgREST roles reach the `app` helper schema.
--
-- WHY THIS FILE EXISTS
--
-- Every RLS policy in 04_rls.sql calls a helper in the `app` schema —
-- app.current_user_id(), app.current_role(), app.current_area(),
-- app.staff_in_area(), app.is_admin(), app.current_consumer_id().
--
-- Postgres evaluates those policies as the *connecting role*. Supabase
-- connects as `anon` before sign-in and `authenticated` after it. Neither
-- role was ever granted USAGE on the `app` schema, so the moment a policy
-- tried to call one of those helpers the whole query failed:
--
--   GET /rest/v1/profiles?select=id
--   401 {"code":"42501","message":"permission denied for schema app"}
--
-- Every table behaves the same way, because every table has a policy and
-- every policy calls into `app`. The app could authenticate and then read
-- nothing at all: sign-in succeeded, the profile lookup failed, and the
-- login screen reported a server error.
--
-- WHY THE TEST SUITE DID NOT CATCH IT
--
-- 05_seed.sql grants the `app` schema to `test_app`:
--
--   grant usage on schema public, app to test_app;
--   grant execute on all functions in schema public, app to test_app;
--
-- 06_tests.sql runs as `test_app`, so all 56 cases pass. They exercise the
-- policies as a role that can enter the schema; the API roles cannot. The
-- suite was testing the rules, not the grants — worth remembering, because
-- a green test run said nothing about whether the app could connect.
--
-- SAFETY
--
-- This grants the ability to CALL the helpers, not to bypass anything. The
-- helpers are SECURITY DEFINER and read only the caller's own row:
-- current_role() and current_area() return the caller's role and area,
-- current_user_id() returns auth.uid(). The RLS policies still decide which
-- rows come back — an unauthenticated caller gets an empty result rather
-- than an error, which is the correct behaviour.
--
-- Run this once, after 01–05, in the Supabase SQL editor or with psql.
-- =====================================================================

-- The two roles PostgREST connects as.
grant usage on schema app to anon, authenticated;

grant execute on all functions in schema app to anon, authenticated;

-- Helpers added later must not reintroduce the same failure. Without this,
-- the next person to write an app.* function has to remember to grant it,
-- and the symptom is the same silent, total loss of API access.
alter default privileges in schema app
  grant execute on functions to anon, authenticated;


-- ---------------------------------------------------------------------
-- Verify, as the roles that matter.
--
-- Both should return a row count without error. An empty result is fine
-- and expected for `anon` — RLS is doing its job. An error is not.
-- ---------------------------------------------------------------------
do $$
declare
  v_count integer;
begin
  set local role anon;
  select count(*) into v_count from profiles;
  raise notice 'anon can query profiles (% rows visible)', v_count;

  set local role authenticated;
  select count(*) into v_count from profiles;
  raise notice 'authenticated can query profiles (% rows visible)', v_count;

  reset role;
  raise notice 'OK: both API roles can enter the app schema.';
end $$;
