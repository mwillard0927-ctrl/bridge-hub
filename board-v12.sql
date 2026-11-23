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
