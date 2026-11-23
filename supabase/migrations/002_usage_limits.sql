-- Server-side daily usage limits for the lesson server's paid endpoints (AI, speech, YouTube search).
-- Only the lesson server can count: bump_usage() requires a secret token whose SHA-256 is stored in
-- private.config (not exposed through the API). The token itself lives only in Vercel (USAGE_TOKEN).

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.config (
  name  text primary key,
  value text not null
);

create table if not exists private.usage_counters (
  subject text not null,        -- 'd:<device id>' or 'ip:<address>'
  feature text not null,        -- tts, lesson, picture, phrase, path, grammar, reaction, search
  day     date not null default (now() at time zone 'utc')::date,
  count   int  not null default 0,
  primary key (subject, feature, day)
);

-- Adds one use and returns the new count, or -1 when the limit is already reached (nothing is added).
-- Returns -2 when the token is wrong.
create or replace function public.bump_usage(p_token text, p_subject text, p_feature text, p_limit int)
returns int
language plpgsql security definer set search_path = '' as $$
declare
  n int;
  today date := (now() at time zone 'utc')::date;
begin
  if p_token is null or encode(extensions.digest(p_token, 'sha256'), 'hex')
       is distinct from (select value from private.config where name = 'usage_token_sha256') then
    return -2;
  end if;
  if length(p_subject) > 120 or length(p_feature) > 20 or p_limit < 0 then return -2; end if;

  insert into private.usage_counters as u (subject, feature, day, count)
  values (p_subject, p_feature, today, 1)
  on conflict (subject, feature, day) do update set count = u.count + 1
    where u.count < p_limit
  returning count into n;

  return coalesce(n, -1);   -- no row returned: the update's WHERE failed, so the limit was reached
end $$;

revoke all on function public.bump_usage(text, text, text, int) from public;
grant execute on function public.bump_usage(text, text, text, int) to anon, authenticated;

-- Old counters are useless after a day; keep a week for looking into abuse.
create or replace function private.prune_usage() returns void language sql as $$
  delete from private.usage_counters where day < (now() at time zone 'utc')::date - 7;
$$;
