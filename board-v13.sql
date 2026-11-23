-- ===== Part A: per-person pools + manager seed pool =====
alter table public.hub_devices add column if not exists pool int not null default 0;
alter table public.hub_devices add column if not exists pool_used int not null default 0;
create table if not exists public.hub_seed(
  user_id uuid primary key references auth.users on delete cascade,
  total int, used int not null default 0);
alter table public.hub_seed enable row level security;
drop policy if exists seed_read on public.hub_seed;
create policy seed_read on public.hub_seed for select to authenticated using (user_id = auth.uid());
grant select on public.hub_seed to authenticated;
grant all on public.hub_seed to service_role;
create table if not exists public.hub_redemptions(
  id bigserial primary key, code text not null, granted int not null default 0,
  claimed boolean not null default false, created_at timestamptz not null default now());
alter table public.hub_redemptions enable row level security;
grant all on public.hub_redemptions to service_role;
grant usage, select on sequence public.hub_redemptions_id_seq to service_role;
grant select (pool, pool_used) on public.hub_devices to authenticated;
-- carry over what people already had
update hub_devices set pool = allowance + greatest(stream_cap - stream_used, 0), pool_used = 0
  where pool = 0 and not is_manager;

-- one scan: checks the QR, then charges 1 + pass-on to the maker's pool (or the seed pool)
create or replace function public.hub_redeem(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare i hub_invites; mk hub_devices; s hub_seed; lft int; g int;
begin
  select * into i from hub_invites where code = upper(p_code) for update;
  if i.code is null or not i.active then raise exception 'This invite was turned off or doesn''t exist'; end if;
  if i.expires_at is not null and i.expires_at < now() then raise exception 'This invite has expired'; end if;
  if i.max_uses is not null and i.uses >= i.max_uses then raise exception 'This invite has been used up'; end if;
  if i.made_by is not null then
    select * into mk from hub_devices where id = i.made_by for update;
    if mk.id is null or mk.blocked then raise exception 'This invite was turned off'; end if;
  end if;
  if i.made_by is null or mk.is_manager then
    insert into hub_seed(user_id) values (i.user_id) on conflict do nothing;
    select * into s from hub_seed where user_id = i.user_id for update;
    lft := case when s.total is null then 1000000 else s.total - s.used end;
  else
    lft := mk.pool - mk.pool_used;
  end if;
  if lft < 1 then raise exception 'No spots left in this invite'; end if;
  g := least(i.can_pass, lft - 1);
  if i.made_by is null or mk.is_manager then update hub_seed set used = used + 1 + g where user_id = i.user_id;
  else update hub_devices set pool_used = pool_used + 1 + g where id = mk.id; end if;
  update hub_invites set uses = uses + 1 where code = i.code;
  insert into hub_redemptions(code, granted) values (i.code, g);
  return i.user_id;
end $$;
revoke execute on function public.hub_redeem(text) from public, anon, authenticated;
grant execute on function public.hub_redeem(text) to service_role;
-- ===== Part B: making, tagging, giving, returning =====
drop function if exists public.hub_make_invite(text,int,int,int);
create or replace function public.hub_make_invite(p_token text, p_days int, p_max int, p_pass int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text; lft int;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in your name first'; end if;
  p_pass := greatest(coalesce(p_pass,0),0); p_max := greatest(coalesce(p_max,0),0);
  if not m.is_manager then
    lft := m.pool - m.pool_used;
    if lft < 1 then raise exception 'You don''t have any invites left'; end if;
    if p_max < 1 or p_max > lft then raise exception 'Pick 1 to % people', lft; end if;
    if p_pass > lft - 1 then raise exception 'They can pass on at most %', lft - 1; end if;
  end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into hub_invites(code,user_id,created_by,made_by,expires_at,max_uses,can_pass)
  values (c, auth.uid(), m.name, m.id,
    case when p_days > 0 then now() + make_interval(days => p_days) end,
    case when p_max > 0 then p_max end, p_pass)
  returning * into i;
  return i;
end $$;
grant execute on function public.hub_make_invite(text,int,int,int) to authenticated;

create or replace function public.hub_tag_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare i hub_invites; r hub_redemptions;
begin
  select * into i from hub_invites where code = upper(p_code) and user_id = auth.uid();
  if i.code is null then return; end if;
  select * into r from hub_redemptions where code = i.code and not claimed order by id limit 1 for update;
  update hub_devices set invite_code = i.code, invited_by = i.made_by, pool = coalesce(r.granted, 0)
  where user_id = auth.uid() and token_hash = hub_h(p_token) and not is_manager and invite_code is null;
  if found and r.id is not null then update hub_redemptions set claimed = true where id = r.id; end if;
end $$;

-- turning off no longer refunds: spots are only used when someone scans
create or replace function public.hub_end_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; d record;
begin
  m := hub_me(p_token);
  select * into i from hub_invites where code = p_code and user_id = auth.uid();
  if m.id is null or i.code is null then raise exception 'Not allowed'; end if;
  if not (m.is_manager or i.made_by = m.id or hub_is_above(m.id, i.made_by)) then raise exception 'Only the manager or someone above this invite can turn it off'; end if;
  update hub_invites set active = false where code = i.code;
  for d in select id from hub_devices where invite_code = i.code and not blocked and not is_manager loop
    perform hub_block_branch(d.id);
  end loop;
end $$;
-- ===== Part C: give, give back, seed size =====
drop function if exists public.hub_give_allowance(text,uuid,int);
create or replace function public.hub_give_allowance(p_token text, p_id uuid, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; t hub_devices; s hub_seed;
begin
  m := hub_me(p_token);
  select * into t from hub_devices where id = p_id and user_id = auth.uid() for update;
  if m.id is null or t.id is null or t.is_manager then raise exception 'Not allowed'; end if;
  if not (m.is_manager or hub_is_above(m.id, t.id)) then raise exception 'You can only give invites to people below you'; end if;
  if p_n < 0 then
    if not m.is_manager then raise exception 'Only the manager can take invites away'; end if;
    p_n := greatest(p_n, -(t.pool - t.pool_used));
    update hub_devices set pool = pool + p_n where id = t.id;
    update hub_seed set used = greatest(used + p_n, 0) where user_id = auth.uid();
    return;
  end if;
  if m.is_manager then
    insert into hub_seed(user_id) values (auth.uid()) on conflict do nothing;
    select * into s from hub_seed where user_id = auth.uid() for update;
    if s.total is not null and s.total - s.used < p_n then raise exception 'Only % left in the seed pool', s.total - s.used; end if;
    update hub_seed set used = used + p_n where user_id = auth.uid();
  else
    if m.pool - m.pool_used < p_n then raise exception 'You only have % to give', m.pool - m.pool_used; end if;
    update hub_devices set pool_used = pool_used + p_n where id = m.id;
  end if;
  update hub_devices set pool = pool + p_n where id = t.id;
end $$;
grant execute on function public.hub_give_allowance(text,uuid,int) to authenticated;

create or replace function public.hub_return_invites(p_token text, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; up hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or m.is_manager then raise exception 'Not allowed'; end if;
  if coalesce(p_n,0) < 1 or p_n > m.pool - m.pool_used then raise exception 'You can give back up to %', m.pool - m.pool_used; end if;
  update hub_devices set pool = pool - p_n where id = m.id;
  select * into up from hub_devices where id = m.invited_by;
  if up.id is null or up.is_manager then
    update hub_seed set used = greatest(used - p_n, 0) where user_id = auth.uid();
  else
    update hub_devices set pool_used = greatest(pool_used - p_n, 0) where id = up.id;
  end if;
end $$;

create or replace function public.hub_set_seed(p_token text, p_total int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager sets the seed pool'; end if;
  insert into hub_seed(user_id, total) values (auth.uid(), case when p_total > 0 then p_total end)
  on conflict (user_id) do update set total = excluded.total;
end $$;
grant execute on function public.hub_set_seed(text,int) to authenticated;
