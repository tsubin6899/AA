-- 旅伴分帳：Supabase 基礎雲端同步資料表
create extension if not exists pgcrypto;

create table if not exists public.travel_workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade unique,
  payload jsonb not null default '{}'::jsonb,
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10)),
  updated_at timestamptz not null default now()
);

alter table public.travel_workspaces enable row level security;

drop policy if exists "workspace owner can read" on public.travel_workspaces;
create policy "workspace owner can read" on public.travel_workspaces
  for select to authenticated using (owner_id = auth.uid());

drop policy if exists "workspace owner can insert" on public.travel_workspaces;
create policy "workspace owner can insert" on public.travel_workspaces
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists "workspace owner can update" on public.travel_workspaces;
create policy "workspace owner can update" on public.travel_workspaces
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create index if not exists travel_workspaces_invite_code_idx on public.travel_workspaces(invite_code);
