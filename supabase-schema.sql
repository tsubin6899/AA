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

-- 邀請加入單一旅行：邀請連結只帶這趟旅行，不會公開管理者的其他旅行。
create table if not exists public.travel_invites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10)),
  owner_id uuid not null references auth.users(id) on delete cascade,
  trip_name text not null,
  trip_payload jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 days')
);

alter table public.travel_invites enable row level security;

drop policy if exists "invite owner can create" on public.travel_invites;
create policy "invite owner can create" on public.travel_invites
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists "invite owner can read" on public.travel_invites;
create policy "invite owner can read" on public.travel_invites
  for select to authenticated using (owner_id = auth.uid());

drop policy if exists "invite owner can delete" on public.travel_invites;
create policy "invite owner can delete" on public.travel_invites
  for delete to authenticated using (owner_id = auth.uid());

create index if not exists travel_invites_code_idx on public.travel_invites(code);

-- 讓已登入使用者以邀請碼取得單一旅行；不開放直接讀取整張邀請表。
create or replace function public.redeem_travel_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if auth.uid() is null then
    raise exception '請先登入後再使用邀請連結';
  end if;
  select jsonb_build_object('trip', trip_payload, 'trip_name', trip_name, 'owner_id', owner_id)
    into result
    from public.travel_invites
   where upper(code) = upper(trim(p_code)) and expires_at > now();
  if result is null then raise exception '邀請連結不存在或已過期'; end if;
  return result;
end;
$$;

revoke all on function public.redeem_travel_invite(text) from public;
grant execute on function public.redeem_travel_invite(text) to authenticated;
