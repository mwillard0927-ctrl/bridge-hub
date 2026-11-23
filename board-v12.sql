-- Bridge Hub v12: invite chain, allowances, blocking with manager review
alter table public.hub_devices add column if not exists invite_code text;
alter table public.hub_devices add column if not exists invited_by uuid;
alter table public.hub_devices add column if not exists allowance int not null default 0;
alter table public.hub_devices add column if not exists blocked boolean not null default false;
alter table public.hub_devices add column if not exists needs_review boolean not null default false;
alter table public.hub_invites add column if not exists made_by uuid;

create or replace function public.hub_me(p_token text) returns public.hub_devices
language sql stable security definer set search_path = public as $$
  select * from hub_devices where user_id = auth.uid() and token_hash = hub_h(p_token) and not blocked limit 1;
$$;

-- is device a anywhere above device b in the invite chain?
create or replace function public.hub_is_above(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  with recursive up(id, depth) as (
    select invited_by, 1 from hub_devices where id = b
    union all
    select d.invited_by, up.depth + 1 from hub_devices d join up on d.id = up.id where up.depth < 50)
  select exists (select 1 from up where id = a);
$$;

-- block one person; everyone they brought in gets flagged for the manager to review
create or replace function public.hub_block_branch(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update hub_devices set blocked = true, needs_review = false where id = p_id;
  update hub_devices set needs_review = true where invited_by = p_id and not blocked;
  update hub_invites set active = false where made_by = p_id;
end $$;
revoke execute on function public.hub_block_branch(uuid) from public, anon, authenticated;

create or replace function public.hub_make_invite(p_token text, p_days int, p_max int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in your name first'; end if;
  if not m.is_manager then
    if coalesce(p_max,0) < 1 then raise exception 'Pick how many people this invite is for'; end if;
    if p_max > m.allowance then raise exception 'You can only invite % more', m.allowance; end if;
    update hub_devices set allowance = allowance - p_max where id = m.id;
  end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into hub_invites(code,user_id,created_by,made_by,expires_at,max_uses)
  values (c, auth.uid(), m.name, m.id,
    case when p_days > 0 then now() + make_interval(days => p_days) end,
    case when p_max > 0 then p_max end)
  returning * into i;
  return i;
end $$;
grant execute on function public.hub_make_invite(text,int,int) to authenticated;

-- turn off a code: manager, its maker, or anyone above the maker
create or replace function public.hub_end_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; d record;
begin
  m := hub_me(p_token);
  select * into i from hub_invites where code = p_code and user_id = auth.uid();
  if m.id is null or i.code is null then raise exception 'Not allowed'; end if;
  if not (m.is_manager or i.made_by = m.id or hub_is_above(m.id, i.made_by)) then raise exception 'Only the manager or someone above this invite can turn it off'; end if;
  if i.active and i.max_uses is not null and i.made_by is not null then
    update hub_devices set allowance = allowance + greatest(i.max_uses - i.uses, 0) where id = i.made_by and not is_manager;
  end if;
  update hub_invites set active = false where code = i.code;
  for d in select id from hub_devices where invite_code = i.code and not blocked and not is_manager loop
    perform hub_block_branch(d.id);
  end loop;
end $$;
grant execute on function public.hub_end_invite(text,text) to authenticated;

-- give part of your allowance to someone below you (manager: anyone, unlimited)
create or replace function public.hub_give_allowance(p_token text, p_id uuid, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; t hub_devices;
begin
  m := hub_me(p_token);
  select * into t from hub_devices where id = p_id and user_id = auth.uid();
  if m.id is null or t.id is null then raise exception 'Not allowed'; end if;
  if not (m.is_manager or hub_is_above(m.id, t.id)) then raise exception 'You can only give invites to people below you'; end if;
  if m.is_manager then
    update hub_devices set allowance = greatest(allowance + p_n, 0) where id = t.id;
  else
    if p_n < 1 or p_n > m.allowance then raise exception 'You only have % to give', m.allowance; end if;
    update hub_devices set allowance = allowance - p_n where id = m.id;
    update hub_devices set allowance = allowance + p_n where id = t.id;
  end if;
end $$;
grant execute on function public.hub_give_allowance(text,uuid,int) to authenticated;

-- block a person directly (manager or anyone above them)
create or replace function public.hub_block_user(p_token text, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; t hub_devices;
begin
  m := hub_me(p_token);
  select * into t from hub_devices where id = p_id and user_id = auth.uid();
  if m.id is null or t.id is null or t.is_manager then raise exception 'Not allowed'; end if;
  if not (m.is_manager or hub_is_above(m.id, t.id)) then raise exception 'Only the manager or someone above them can block'; end if;
  perform hub_block_branch(t.id);
end $$;
grant execute on function public.hub_block_user(text,uuid) to authenticated;

-- manager decides on each flagged person: block (flags their branch next) or keep
create or replace function public.hub_review(p_token text, p_id uuid, p_block boolean) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager reviews'; end if;
  if p_block then perform hub_block_branch(p_id);
  else update hub_devices set needs_review = false, blocked = false where id = p_id and user_id = auth.uid(); end if;
end $$;
grant execute on function public.hub_review(text,uuid,boolean) to authenticated;

-- tie a newly locked-in name to the QR it joined with
create or replace function public.hub_tag_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare i hub_invites;
begin
  select * into i from hub_invites where code = upper(p_code) and user_id = auth.uid() and active;
  if i.code is null then return; end if;
  update hub_devices set invite_code = i.code, invited_by = i.made_by
  where user_id = auth.uid() and token_hash = hub_h(p_token) and not is_manager and invite_code is null;
end $$;
grant execute on function public.hub_tag_invite(text,text) to authenticated;

-- is the name saved on this phone blocked?
create or replace function public.hub_am_blocked(p_token text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from hub_devices where user_id = auth.uid() and token_hash = hub_h(p_token) and blocked);
$$;
grant execute on function public.hub_am_blocked(text) to authenticated;
-- Part 4: manager can change any invite's limit
alter table public.hub_invites add column if not exists reserved int not null default 0;

create or replace function public.hub_set_invite_limit(p_token text, p_code text, p_max int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager can change invite limits'; end if;
  update hub_invites set max_uses = case when p_max > 0 then greatest(p_max, uses) end
  where code = p_code and user_id = auth.uid();
end $$;
grant execute on function public.hub_set_invite_limit(text,text,int) to authenticated;

-- remember how much allowance each invite used, so refunds stay correct after a limit change
create or replace function public.hub_make_invite(p_token text, p_days int, p_max int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in your name first'; end if;
  if not m.is_manager then
    if coalesce(p_max,0) < 1 then raise exception 'Pick how many people this invite is for'; end if;
    if p_max > m.allowance then raise exception 'You can only invite % more', m.allowance; end if;
    update hub_devices set allowance = allowance - p_max where id = m.id;
  end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into hub_invites(code,user_id,created_by,made_by,expires_at,max_uses,reserved)
  values (c, auth.uid(), m.name, m.id,
    case when p_days > 0 then now() + make_interval(days => p_days) end,
    case when p_max > 0 then p_max end,
    case when m.is_manager then 0 else p_max end)
  returning * into i;
  return i;
end $$;

create or replace function public.hub_end_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; d record;
begin
  m := hub_me(p_token);
  select * into i from hub_invites where code = p_code and user_id = auth.uid();
  if m.id is null or i.code is null then raise exception 'Not allowed'; end if;
  if not (m.is_manager or i.made_by = m.id or hub_is_above(m.id, i.made_by)) then raise exception 'Only the manager or someone above this invite can turn it off'; end if;
  if i.active and i.reserved > 0 then
    update hub_devices set allowance = allowance + greatest(i.reserved - i.uses, 0) where id = i.made_by;
  end if;
  update hub_invites set active = false where code = i.code;
  for d in select id from hub_devices where invite_code = i.code and not blocked and not is_manager loop
    perform hub_block_branch(d.id);
  end loop;
end $$;
-- Part 5: shared-pool QR streams
alter table public.hub_invites add column if not exists pool_code text;
alter table public.hub_invites add column if not exists pool_used int not null default 0;
alter table public.hub_invites add column if not exists can_pass int not null default 0;
alter table public.hub_devices add column if not exists stream_code text;
alter table public.hub_devices add column if not exists stream_cap int not null default 0;
alter table public.hub_devices add column if not exists stream_used int not null default 0;
update hub_invites set pool_used = uses where pool_code is null and pool_used = 0;

-- spots left in a stream (null = no limit)
create or replace function public.hub_pool_left(p_root text) returns int
language sql stable security definer set search_path = public as $$
  select case when max_uses is null then null else greatest(max_uses - pool_used, 0) end
  from hub_invites where code = p_root and active;
$$;

-- one scan = one spot, checked and counted in one step (called by hub-join)
create or replace function public.hub_redeem(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare i hub_invites; r hub_invites;
begin
  select * into i from hub_invites where code = upper(p_code) for update;
  if i.code is null or not i.active then raise exception 'This invite was turned off or doesn''t exist'; end if;
  if i.expires_at is not null and i.expires_at < now() then raise exception 'This invite has expired'; end if;
  if i.max_uses is not null and i.uses >= i.max_uses then raise exception 'This invite has been used up'; end if;
  select * into r from hub_invites where code = coalesce(i.pool_code, i.code) for update;
  if r.code is null or not r.active then raise exception 'This invite was turned off'; end if;
  if r.max_uses is not null and r.pool_used >= r.max_uses then raise exception 'No spots left in this invite'; end if;
  update hub_invites set uses = uses + 1 where code = i.code;
  update hub_invites set pool_used = pool_used + 1 where code = r.code;
  return i.user_id;
end $$;
revoke execute on function public.hub_redeem(text) from public, anon, authenticated;
grant execute on function public.hub_redeem(text) to service_role;
-- Part 6: making invites (manager, allowance, or stream) with a pass-on choice
drop function if exists public.hub_make_invite(text,int,int);
create or replace function public.hub_make_invite(p_token text, p_days int, p_max int, p_pass int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text; lft int; root text; res int := 0;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in your name first'; end if;
  p_pass := greatest(coalesce(p_pass,0),0);
  if m.is_manager then null;
  elsif m.allowance > 0 then
    if coalesce(p_max,0) < 1 or p_max > m.allowance then raise exception 'You can invite up to %', m.allowance; end if;
    update hub_devices set allowance = allowance - p_max where id = m.id; res := p_max;
  elsif m.stream_code is not null and m.stream_cap > m.stream_used then
    root := m.stream_code; lft := hub_pool_left(root);
    if not exists (select 1 from hub_invites where code = root and active) then raise exception 'The invite you joined with was turned off'; end if;
    lft := least(coalesce(lft, 100000), m.stream_cap - m.stream_used);
    if coalesce(p_max,0) < 1 or p_max > lft then raise exception 'You can pass on up to %', lft; end if;
    if p_pass > lft - 1 then p_pass := greatest(lft - 1, 0); end if;
    update hub_devices set stream_used = stream_used + p_max where id = m.id; res := p_max;
  else raise exception 'You don''t have any invites to give'; end if;
  c := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  insert into hub_invites(code,user_id,created_by,made_by,expires_at,max_uses,reserved,pool_code,can_pass)
  values (c, auth.uid(), m.name, m.id,
    case when p_days > 0 then now() + make_interval(days => p_days) end,
    case when p_max > 0 then p_max end, res, root, p_pass)
  returning * into i;
  return i;
end $$;
grant execute on function public.hub_make_invite(text,int,int,int) to authenticated;

-- tie a new name to its QR; if that QR lets people pass on, give them their share of the stream
create or replace function public.hub_tag_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare i hub_invites;
begin
  select * into i from hub_invites where code = upper(p_code) and user_id = auth.uid() and active;
  if i.code is null then return; end if;
  update hub_devices set invite_code = i.code, invited_by = i.made_by,
    stream_code = case when i.can_pass > 0 then coalesce(i.pool_code, i.code) end,
    stream_cap = i.can_pass
  where user_id = auth.uid() and token_hash = hub_h(p_token) and not is_manager and invite_code is null;
end $$;

create or replace function public.hub_end_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; d record;
begin
  m := hub_me(p_token);
  select * into i from hub_invites where code = p_code and user_id = auth.uid();
  if m.id is null or i.code is null then raise exception 'Not allowed'; end if;
  if not (m.is_manager or i.made_by = m.id or hub_is_above(m.id, i.made_by)) then raise exception 'Only the manager or someone above this invite can turn it off'; end if;
  if i.active and i.reserved > 0 then
    if i.pool_code is not null then
      update hub_devices set stream_used = greatest(stream_used - greatest(i.reserved - i.uses, 0), 0) where id = i.made_by;
    else
      update hub_devices set allowance = allowance + greatest(i.reserved - i.uses, 0) where id = i.made_by;
    end if;
  end if;
  update hub_invites set active = false where code = i.code;
  for d in select id from hub_devices where invite_code = i.code and not blocked and not is_manager loop
    perform hub_block_branch(d.id);
  end loop;
end $$;
-- Part 7: give back unused invites
create or replace function public.hub_return_invites(p_token text, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; up hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or m.is_manager then raise exception 'Not allowed'; end if;
  if coalesce(p_n,0) < 1 then raise exception 'Pick how many to give back'; end if;
  if m.stream_code is not null and m.stream_cap - m.stream_used >= p_n then
    update hub_devices set stream_cap = stream_cap - p_n where id = m.id;
  elsif m.allowance >= p_n then
    update hub_devices set allowance = allowance - p_n where id = m.id;
    select * into up from hub_devices where id = m.invited_by;
    if up.id is not null and not up.is_manager and not up.blocked then
      update hub_devices set allowance = allowance + p_n where id = up.id;
    end if;
  else raise exception 'You don''t have that many to give back'; end if;
end $$;
grant execute on function public.hub_return_invites(text,int) to authenticated;
