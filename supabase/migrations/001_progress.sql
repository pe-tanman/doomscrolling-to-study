-- Upscroll cloud progress: one row per signed-in user holding a JSON snapshot of their learning data
-- (words + review schedule, journey coverage, rewards, settings). Run once in Supabase → SQL editor.

create table if not exists public.progress (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       jsonb not null,
  version    int not null default 1,
  device     text,
  updated_at timestamptz not null default now()
);

alter table public.progress enable row level security;

-- Each user can only see and change their own row.
drop policy if exists "own progress: select" on public.progress;
drop policy if exists "own progress: insert" on public.progress;
drop policy if exists "own progress: update" on public.progress;
drop policy if exists "own progress: delete" on public.progress;
create policy "own progress: select" on public.progress for select to authenticated using (auth.uid() = user_id);
create policy "own progress: insert" on public.progress for insert to authenticated with check (auth.uid() = user_id);
create policy "own progress: update" on public.progress for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own progress: delete" on public.progress for delete to authenticated using (auth.uid() = user_id);

-- Keep updated_at honest on every write.
create or replace function public.touch_progress() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
drop trigger if exists progress_touch on public.progress;
create trigger progress_touch before insert or update on public.progress
  for each row execute function public.touch_progress();

-- Let a user delete their own account (and, by cascade, their progress) from the app.
create or replace function public.delete_my_account() returns void
language sql security definer set search_path = '' as $$
  delete from auth.users where id = auth.uid();
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
