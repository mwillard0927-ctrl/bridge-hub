-- Bridge Hub v4: private posts to selected devices + choose-your-manager on first lock-in.
-- Run AFTER board-v3.sql. Safe to run more than once.
alter table public.hub_posts add column if not exists recipients text[];

-- direct reads only see board-wide (public) posts and their replies; private ones come through the functions below
drop policy if exists "posts read" on public.hub_posts;
create policy "posts read" on public.hub_posts for select to authenticated using (hub_is_member(project_id) and recipients is null);
drop policy if exists "replies read" on public.hub_replies;
create policy "replies read" on public.hub_replies for select to authenticated
  using (hub_is_member(project_id) and exists (select 1 from public.hub_posts p where p.id = post_id and p.recipients is null));

create or replace function public.hub_can_see(p hub_posts, dname text) returns boolean language sql immutable as $$
  select p.recipients is null or exists (select 1 from unnest(p.recipients) r where lower(r) = lower(dname));
$$;

create or replace function public.hub_private_posts(p_token text, p_project uuid) returns setof public.hub_posts
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null or not hub_is_member(p_project) then return; end if;
  return query select * from hub_posts p where p.project_id = p_project and p.recipients is not null and hub_can_see(p, m.name) order by created_at desc limit 500;
end $$;

create or replace function public.hub_private_replies(p_token text, p_project uuid) returns setof public.hub_replies
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null or not hub_is_member(p_project) then return; end if;
  return query select r.* from hub_replies r join hub_posts p on p.id = r.post_id
    where r.project_id = p_project and p.recipients is not null and hub_can_see(p, m.name) order by r.created_at limit 3000;
end $$;

drop function if exists public.hub_post(text,uuid,text,text,text,date,text,text,bigint,text);
create or replace function public.hub_post(p_token text, p_project uuid, p_title text, p_body text, p_tag text, p_due date,
  p_file_path text default null, p_file_name text default null, p_file_size bigint default null, p_file_type text default null,
  p_recipients text[] default null) returns public.hub_posts
language plpgsql security definer set search_path = public as $$
declare m hub_devices; r hub_posts; rec text[];
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in this device first'; end if;
  if not hub_is_member(p_project) then raise exception 'Not a member of this board'; end if;
  if p_recipients is not null then rec := array(select distinct x from unnest(p_recipients || m.name) x where x is not null and x <> ''); end if;
  insert into hub_posts(project_id, user_id, device, title, body, tag, due, file_path, file_name, file_size, file_type, recipients)
  values (p_project, auth.uid(), m.name, left(p_title,140), p_body, coalesce(p_tag,'Note'), p_due, p_file_path, p_file_name, p_file_size, p_file_type, rec) returning * into r;
  return r;
end $$;

create or replace function public.hub_reply(p_token text, p_post uuid, p_parent uuid, p_body text,
  p_file_path text default null, p_file_name text default null, p_file_size bigint default null, p_file_type text default null) returns public.hub_replies
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts; r hub_replies;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in this device first'; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or not hub_is_member(p.project_id) or not hub_can_see(p, m.name) then raise exception 'Post not found'; end if;
  insert into hub_replies(post_id, project_id, parent_id, user_id, device, body, file_path, file_name, file_size, file_type)
  values (p.id, p.project_id, p_parent, auth.uid(), m.name, p_body, p_file_path, p_file_name, p_file_size, p_file_type) returning * into r;
  return r;
end $$;

create or replace function public.hub_view(p_token text, p_post uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts;
begin
  m := hub_me(p_token); if m.id is null then return; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or not hub_is_member(p.project_id) or not hub_can_see(p, m.name) then return; end if;
  insert into hub_views(post_id, user_id, project_id, device) values (p.id, auth.uid(), p.project_id, m.name) on conflict do nothing;
end $$;

-- lock-in: the device chooses whether to be manager (only allowed while the login has no manager)
drop function if exists public.hub_claim_device(text,text,text);
create or replace function public.hub_claim_device(p_name text, p_token text, p_recovery text, p_manager boolean default false) returns public.hub_devices
language plpgsql security definer set search_path = public as $$
declare d hub_devices; has_mgr boolean;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if char_length(trim(p_name)) < 1 or char_length(trim(p_name)) > 40 then raise exception 'Name must be 1-40 characters'; end if;
  select * into d from hub_devices where user_id = auth.uid() and lower(name) = lower(trim(p_name));
  if d.id is not null and d.token_hash is not null then raise exception 'That device name is already locked in by another device'; end if;
  select exists(select 1 from hub_devices where user_id = auth.uid() and is_manager) into has_mgr;
  if p_manager and has_mgr then raise exception 'This board already has a manager'; end if;
  if d.id is null then insert into hub_devices(user_id, name) values (auth.uid(), trim(p_name)) returning * into d; end if;
  update hub_devices set token_hash = hub_h(p_token), recovery_hash = hub_h(upper(p_recovery)), claimed_at = now(), is_manager = coalesce(p_manager,false)
   where id = d.id returning * into d;
  return d;
end $$;

-- a locked device can become manager later only if the login still has none
create or replace function public.hub_become_manager(p_token text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null then raise exception 'Lock in this device first'; end if;
  if exists(select 1 from hub_devices where user_id = auth.uid() and is_manager) then raise exception 'This board already has a manager'; end if;
  update hub_devices set is_manager = true where id = m.id;
end $$;

grant execute on function public.hub_can_see(hub_posts,text), public.hub_private_posts(text,uuid), public.hub_private_replies(text,uuid),
  public.hub_post(text,uuid,text,text,text,date,text,text,bigint,text,text[]), public.hub_reply(text,uuid,uuid,text,text,text,bigint,text),
  public.hub_view(text,uuid), public.hub_claim_device(text,text,text,boolean), public.hub_become_manager(text) to authenticated;
