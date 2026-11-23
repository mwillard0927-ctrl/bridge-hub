-- ===== v14 Part 1: live shared pool (counts, not reservations) =====
create index if not exists hub_redemptions_code on public.hub_redemptions(code);
-- backfill: everyone who already joined through a QR counts as one used spot
insert into hub_redemptions(code, granted, claimed)
select d.invite_code, 0, true from hub_devices d
where d.invite_code is not null
  and not exists (select 1 from hub_redemptions r where r.code = d.invite_code and r.claimed);

-- joins that count: finished, or started in the last 24h
create or replace function public.hub_used(p uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from hub_redemptions r join hub_invites i on i.code = r.code
  where (r.claimed or r.created_at > now() - interval '1 day')
    and (i.made_by = p or hub_is_above(p, i.made_by));
$$;
create or replace function public.hub_seed_used(u uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from hub_redemptions r join hub_invites i on i.code = r.code
  where i.user_id = u and (r.claimed or r.created_at > now() - interval '1 day');
$$;
-- spots left for a person = smallest of their own room, everyone above them, and the seed pool
create or replace function public.hub_left(p uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare d hub_devices; lft int := 1000000; s hub_seed; n int := 0;
begin
  select * into d from hub_devices where id = p;
  while d.id is not null and not d.is_manager and n < 50 loop
    if d.blocked then return 0; end if;
    lft := least(lft, d.pool - hub_used(d.id));
    select * into d from hub_devices where id = d.invited_by; n := n + 1;
  end loop;
  select * into s from hub_seed where user_id = coalesce(d.user_id, (select user_id from hub_devices where id = p));
  if s.total is not null then lft := least(lft, s.total - hub_seed_used(s.user_id)); end if;
  return greatest(lft, 0);
end $$;
-- ===== v14 Part 2: scan, tag, make =====
create or replace function public.hub_redeem(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare i hub_invites; mk hub_devices;
begin
  select * into i from hub_invites where code = upper(p_code);
  if i.code is null or not i.active then raise exception 'This invite was turned off or doesn''t exist'; end if;
  insert into hub_seed(user_id) values (i.user_id) on conflict do nothing;
  perform 1 from hub_seed where user_id = i.user_id for update;   -- one scan at a time per board
  select * into i from hub_invites where code = upper(p_code);
  if i.expires_at is not null and i.expires_at < now() then raise exception 'This invite has expired'; end if;
  if i.max_uses is not null and i.uses >= i.max_uses then raise exception 'This invite has been used up'; end if;
  if i.made_by is not null then
    select * into mk from hub_devices where id = i.made_by;
    if mk.id is null or mk.blocked then raise exception 'This invite was turned off'; end if;
  end if;
  if (case when i.made_by is null then
        (select case when total is null then 1 else total - hub_seed_used(user_id) end from hub_seed where user_id = i.user_id)
      else hub_left(i.made_by) end) < 1 then
    raise exception 'No spots left in this invite';
  end if;
  update hub_invites set uses = uses + 1 where code = i.code;
  insert into hub_redemptions(code, granted) values (i.code, i.can_pass);
  return i.user_id;
end $$;
revoke execute on function public.hub_redeem(text) from public, anon, authenticated;
grant execute on function public.hub_redeem(text) to service_role;

create or replace function public.hub_tag_invite(p_token text, p_code text) returns void
language plpgsql security definer set search_path = public as $$
declare i hub_invites; r hub_redemptions;
begin
  select * into i from hub_invites where code = upper(p_code) and user_id = auth.uid();
  if i.code is null then return; end if;
  select * into r from hub_redemptions where code = i.code and not claimed order by id limit 1 for update;
  update hub_devices set invite_code = i.code, invited_by = i.made_by, pool = coalesce(r.granted, i.can_pass), pool_used = 0
  where user_id = auth.uid() and token_hash = hub_h(p_token) and not is_manager and invite_code is null;
  if found and r.id is not null then update hub_redemptions set claimed = true where id = r.id; end if;
end $$;

create or replace function public.hub_make_invite(p_token text, p_days int, p_max int, p_pass int) returns public.hub_invites
language plpgsql security definer set search_path = public as $$
declare m hub_devices; i hub_invites; c text; lft int;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in your name first'; end if;
  p_pass := greatest(coalesce(p_pass,0),0); p_max := greatest(coalesce(p_max,0),0);
  if not m.is_manager then
    lft := hub_left(m.id);
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
-- ===== v14 Part 3: give, take, give back, live status =====
create or replace function public.hub_give_allowance(p_token text, p_id uuid, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; t hub_devices;
begin
  m := hub_me(p_token);
  select * into t from hub_devices where id = p_id and user_id = auth.uid();
  if m.id is null or t.id is null or t.is_manager then raise exception 'Not allowed'; end if;
  if not (m.is_manager or hub_is_above(m.id, t.id)) then raise exception 'You can only give invites to people below you'; end if;
  if p_n < 0 and not m.is_manager then raise exception 'Only the manager can take invites away'; end if;
  if p_n > 0 and not m.is_manager and p_n > hub_left(m.id) then raise exception 'You only have % left', hub_left(m.id); end if;
  update hub_devices set pool = greatest(pool + p_n, hub_used(t.id)) where id = t.id;
end $$;
grant execute on function public.hub_give_allowance(text,uuid,int) to authenticated;

create or replace function public.hub_return_invites(p_token text, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; room int;
begin
  m := hub_me(p_token);
  if m.id is null or m.is_manager then raise exception 'Not allowed'; end if;
  room := m.pool - hub_used(m.id);
  if coalesce(p_n,0) < 1 or p_n > room then raise exception 'You can give back up to %', room; end if;
  update hub_devices set pool = pool - p_n where id = m.id;
end $$;

-- everyone's live numbers for the app
create or replace function public.hub_pool_status() returns table(id uuid, given int, used int, left_now int)
language sql stable security definer set search_path = public as $$
  select d.id, d.pool, hub_used(d.id), hub_left(d.id) from hub_devices d
  where d.user_id = auth.uid() and not d.is_manager;
$$;
grant execute on function public.hub_pool_status() to authenticated;
create or replace function public.hub_seed_status() returns table(total int, used int)
language sql stable security definer set search_path = public as $$
  select s.total, hub_seed_used(auth.uid()) from hub_seed s where s.user_id = auth.uid()
  union all select null::int, hub_seed_used(auth.uid()) where not exists (select 1 from hub_seed where user_id = auth.uid())
  limit 1;
$$;
grant execute on function public.hub_seed_status() to authenticated;
