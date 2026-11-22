-- Bridge Hub upgrade: v3 (device lock-in + manager) + v4 (private posts + manager choice) + v5 (manager-only read tracking)
-- Run once, after supabase-setup.sql, board-setup.sql and board-v2.sql.
create extension if not exists pgcrypto with schema extensions;

alter table public.hub_devices add column if not exists token_hash text;
alter table public.hub_devices add column if not exists recovery_hash text;
alter table public.hub_devices add column if not exists claimed_at timestamptz;
alter table public.hub_devices add column if not exists is_manager boolean not null default false;

create or replace function public.hub_h(t text) returns text language sql immutable as $$
  select encode(extensions.digest(coalesce(t,''), 'sha256'), 'hex');
$$;

create or replace function public.hub_me(p_token text) returns public.hub_devices
language sql stable security definer set search_path = public as $$
  select * from hub_devices where user_id = auth.uid() and token_hash = hub_h(p_token) limit 1;
$$;

create or replace function public.hub_claim_device(p_name text, p_token text, p_recovery text) returns public.hub_devices
language plpgsql security definer set search_path = public as $$
declare d hub_devices; has_mgr boolean;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if char_length(trim(p_name)) < 1 or char_length(trim(p_name)) > 40 then raise exception 'Name must be 1-40 characters'; end if;
  select * into d from hub_devices where user_id = auth.uid() and lower(name) = lower(trim(p_name));
  if d.id is not null and d.token_hash is not null then raise exception 'That device name is already locked in by another device'; end if;
  select exists(select 1 from hub_devices where user_id = auth.uid() and is_manager) into has_mgr;
  if d.id is null then
    insert into hub_devices(user_id, name) values (auth.uid(), trim(p_name)) returning * into d;
  end if;
  update hub_devices set token_hash = hub_h(p_token), recovery_hash = hub_h(upper(p_recovery)), claimed_at = now(),
         is_manager = not has_mgr
   where id = d.id returning * into d;
  return d;
end $$;

create or replace function public.hub_recover_device(p_name text, p_recovery text, p_token text) returns public.hub_devices
language plpgsql security definer set search_path = public as $$
declare d hub_devices;
begin
  select * into d from hub_devices where user_id = auth.uid() and lower(name) = lower(trim(p_name)) and recovery_hash = hub_h(upper(trim(p_recovery)));
  if d.id is null then raise exception 'Name or recovery code is wrong'; end if;
  update hub_devices set token_hash = hub_h(p_token) where id = d.id returning * into d;
  return d;
end $$;

create or replace function public.hub_manage_device(p_token text, p_device uuid, p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager device can do that'; end if;
  if p_device = m.id then raise exception 'The manager device cannot change itself'; end if;
  if p_action = 'remove' then delete from hub_devices where id = p_device and user_id = auth.uid();
  elsif p_action = 'unlock' then update hub_devices set token_hash = null, recovery_hash = null, claimed_at = null where id = p_device and user_id = auth.uid();
  elsif p_action = 'make_manager' then
    update hub_devices set is_manager = false where id = m.id;
    update hub_devices set is_manager = true where id = p_device and user_id = auth.uid();
  else raise exception 'Unknown action'; end if;
end $$;

create or replace function public.hub_post(p_token text, p_project uuid, p_title text, p_body text, p_tag text, p_due date,
  p_file_path text default null, p_file_name text default null, p_file_size bigint default null, p_file_type text default null) returns public.hub_posts
language plpgsql security definer set search_path = public as $$
declare m hub_devices; r hub_posts;
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in this device first'; end if;
  if not hub_is_member(p_project) then raise exception 'Not a member of this board'; end if;
  insert into hub_posts(project_id, user_id, device, title, body, tag, due, file_path, file_name, file_size, file_type)
  values (p_project, auth.uid(), m.name, left(p_title,140), p_body, coalesce(p_tag,'Note'), p_due, p_file_path, p_file_name, p_file_size, p_file_type) returning * into r;
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
  if p.id is null or not hub_is_member(p.project_id) then raise exception 'Post not found'; end if;
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
  if p.id is null or not hub_is_member(p.project_id) then return; end if;
  insert into hub_views(post_id, user_id, project_id, device) values (p.id, auth.uid(), p.project_id, m.name) on conflict do nothing;
end $$;

create or replace function public.hub_mod(p_token text, p_kind text, p_id uuid, p_action text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; pid uuid;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager device can do that'; end if;
  if p_kind = 'post' then
    select project_id into pid from hub_posts where id = p_id;
    if pid is null or not hub_is_member(pid) then raise exception 'Not found'; end if;
    if p_action = 'delete' then delete from hub_posts where id = p_id;
    elsif p_action = 'resolve' then update hub_posts set status = 'resolved', updated_at = now() where id = p_id;
    elsif p_action = 'reopen' then update hub_posts set status = 'open', updated_at = now() where id = p_id;
    elsif p_action = 'pin' then update hub_posts set pinned = true where id = p_id;
    elsif p_action = 'unpin' then update hub_posts set pinned = false where id = p_id;
    else raise exception 'Unknown action'; end if;
  elsif p_kind = 'reply' and p_action = 'delete' then
    select project_id into pid from hub_replies where id = p_id;
    if pid is null or not hub_is_member(pid) then raise exception 'Not found'; end if;
    delete from hub_replies where id = p_id;
  else raise exception 'Unknown action'; end if;
end $$;

revoke insert, update, delete on public.hub_posts, public.hub_replies, public.hub_views from authenticated;
revoke insert, update, delete on public.hub_devices from authenticated;
revoke select on public.hub_devices from authenticated;
grant select (id, user_id, name, created_at, claimed_at, is_manager) on public.hub_devices to authenticated;

grant execute on function public.hub_me(text), public.hub_claim_device(text,text,text), public.hub_recover_device(text,text,text),
  public.hub_manage_device(text,uuid,text), public.hub_post(text,uuid,text,text,text,date,text,text,bigint,text),
  public.hub_reply(text,uuid,uuid,text,text,text,bigint,text), public.hub_view(text,uuid), public.hub_mod(text,text,uuid,text) to authenticated;
alter table public.hub_posts add column if not exists recipients text[];

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
alter table public.hub_devices add column if not exists last_seen timestamptz;

create table if not exists public.hub_file_opens (
  post_id uuid references public.hub_posts on delete cascade,
  project_id uuid references public.hub_projects on delete cascade,
  user_id uuid references auth.users on delete cascade,
  device text not null,
  file_path text not null,
  opened_at timestamptz not null default now(),
  primary key (file_path, user_id, device)
);
alter table public.hub_file_opens enable row level security;  -- no policies: only reachable through the functions below

revoke select on public.hub_views from authenticated;

create or replace function public.hub_ping(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin update hub_devices set last_seen = now() where user_id = auth.uid() and token_hash = hub_h(p_token); end $$;

create or replace function public.hub_my_views(p_token text) returns table(post_id uuid, project_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null then return; end if;
  return query select v.post_id, v.project_id from hub_views v where v.user_id = auth.uid() and v.device = m.name;
end $$;

create or replace function public.hub_file_open(p_token text, p_post uuid, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts;
begin
  m := hub_me(p_token); if m.id is null then return; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or not hub_is_member(p.project_id) or not hub_can_see(p, m.name) then return; end if;
  insert into hub_file_opens(post_id, project_id, user_id, device, file_path) values (p.id, p.project_id, auth.uid(), m.name, p_path)
  on conflict (file_path, user_id, device) do update set opened_at = excluded.opened_at;
end $$;

create or replace function public.hub_tracking(p_token text, p_project uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager or not hub_is_member(p_project) then return null; end if;
  return json_build_object(
    'views',   coalesce((select json_agg(json_build_object('post_id', post_id, 'user_id', user_id, 'device', device, 'at', viewed_at)) from hub_views where project_id = p_project), '[]'::json),
    'opens',   coalesce((select json_agg(json_build_object('post_id', post_id, 'user_id', user_id, 'device', device, 'path', file_path, 'at', opened_at)) from hub_file_opens where project_id = p_project), '[]'::json),
    'devices', coalesce((select json_agg(json_build_object('name', name, 'last_seen', last_seen)) from hub_devices where user_id = auth.uid()), '[]'::json));
end $$;

grant execute on function public.hub_ping(text), public.hub_my_views(text), public.hub_file_open(text,uuid,text), public.hub_tracking(text,uuid) to authenticated;
