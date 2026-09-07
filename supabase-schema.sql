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

-- 共享旅行：每趟旅行各自儲存，讓受邀成員只讀取自己有權限的旅行。
create table if not exists public.travel_shared_trips (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  client_trip_id text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revision bigint not null default 1,
  unique (owner_id, client_trip_id)
);

alter table public.travel_shared_trips add column if not exists revision bigint not null default 1;

create table if not exists public.travel_shared_trip_members (
  trip_id uuid not null references public.travel_shared_trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_id text not null,
  role text not null default 'member' check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (trip_id, user_id),
  unique (trip_id, member_id)
);

create table if not exists public.travel_shared_invites (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 10)),
  trip_id uuid not null references public.travel_shared_trips(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  member_id text not null,
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now()
);

alter table public.travel_shared_trips enable row level security;
alter table public.travel_shared_trip_members enable row level security;
alter table public.travel_shared_invites enable row level security;

drop policy if exists "shared trip members can read" on public.travel_shared_trips;
create policy "shared trip members can read" on public.travel_shared_trips
  for select to authenticated using (
    owner_id = auth.uid() or exists (
      select 1 from public.travel_shared_trip_members m
      where m.trip_id = id and m.user_id = auth.uid()
    )
  );

drop policy if exists "shared trip owner can insert" on public.travel_shared_trips;
create policy "shared trip owner can insert" on public.travel_shared_trips
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists "shared trip members can update" on public.travel_shared_trips;

drop policy if exists "shared trip owner can delete" on public.travel_shared_trips;
create policy "shared trip owner can delete" on public.travel_shared_trips
  for delete to authenticated using (owner_id = auth.uid());

drop policy if exists "shared members can read their trip" on public.travel_shared_trip_members;
create policy "shared members can read their trip" on public.travel_shared_trip_members
  for select to authenticated using (
    user_id = auth.uid() or exists (
      select 1 from public.travel_shared_trips t where t.id = trip_id and t.owner_id = auth.uid()
    )
  );

drop policy if exists "shared invite owner can manage" on public.travel_shared_invites;
create policy "shared invite owner can manage" on public.travel_shared_invites
  for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create index if not exists travel_shared_members_user_idx on public.travel_shared_trip_members(user_id);
create index if not exists travel_shared_invites_code_idx on public.travel_shared_invites(code);

create or replace function public.create_shared_trip(p_client_trip_id text, p_payload jsonb, p_owner_member_id text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare trip_uuid uuid;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  insert into public.travel_shared_trips (owner_id, client_trip_id, payload, updated_at)
  values (auth.uid(), p_client_trip_id, p_payload, now())
  on conflict (owner_id, client_trip_id)
  do update set payload = excluded.payload, updated_at = now()
  returning id into trip_uuid;
  insert into public.travel_shared_trip_members (trip_id, user_id, member_id, role)
  values (trip_uuid, auth.uid(), p_owner_member_id, 'owner')
  on conflict (trip_id, user_id) do update set member_id = excluded.member_id, role = 'owner';
  return trip_uuid;
end;
$$;

create or replace function public.accept_shared_trip_invite(p_code text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare invite_row public.travel_shared_invites%rowtype;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  select * into invite_row from public.travel_shared_invites
  where upper(code) = upper(trim(p_code)) and expires_at > now();
  if invite_row.id is null then raise exception '邀請連結不存在或已過期'; end if;
  insert into public.travel_shared_trip_members (trip_id, user_id, member_id, role)
  values (invite_row.trip_id, auth.uid(), invite_row.member_id, 'member')
  on conflict (trip_id, user_id) do update set member_id = excluded.member_id;
  return invite_row.trip_id;
end;
$$;

create or replace function public.update_shared_trip(p_trip_id uuid, p_payload jsonb, p_expected_revision bigint)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare next_revision bigint;
begin
  if auth.uid() is null then raise exception '請先登入'; end if;
  if not exists (
    select 1 from public.travel_shared_trips t
    where t.id = p_trip_id and (
      t.owner_id = auth.uid() or exists (
        select 1 from public.travel_shared_trip_members m where m.trip_id = t.id and m.user_id = auth.uid()
      )
    )
  ) then raise exception '沒有此旅行的編輯權限'; end if;
  update public.travel_shared_trips
     set payload = p_payload, updated_at = now(), revision = revision + 1
   where id = p_trip_id and revision = p_expected_revision
  returning revision into next_revision;
  return next_revision;
end;
$$;

revoke all on function public.create_shared_trip(text, jsonb, text) from public;
revoke all on function public.accept_shared_trip_invite(text) from public;
revoke all on function public.update_shared_trip(uuid, jsonb, bigint) from public;
grant execute on function public.create_shared_trip(text, jsonb, text) to authenticated;
grant execute on function public.accept_shared_trip_invite(text) to authenticated;
grant execute on function public.update_shared_trip(uuid, jsonb, bigint) to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.travel_shared_trips;
exception when duplicate_object then null;
end $$;

-- 避免旅行與成員的 RLS 政策互相查詢而遞迴；此函式只用於權限判斷。
create or replace function public.can_access_shared_trip(p_trip_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.travel_shared_trips t
    where t.id = p_trip_id and t.owner_id = auth.uid()
  ) or exists (
    select 1 from public.travel_shared_trip_members m
    where m.trip_id = p_trip_id and m.user_id = auth.uid()
  );
$$;

drop policy if exists "shared trip members can read" on public.travel_shared_trips;
create policy "shared trip members can read" on public.travel_shared_trips
  for select to authenticated using (public.can_access_shared_trip(id));

drop policy if exists "shared members can read their trip" on public.travel_shared_trip_members;

revoke all on function public.can_access_shared_trip(uuid) from public;
grant execute on function public.can_access_shared_trip(uuid) to authenticated;
