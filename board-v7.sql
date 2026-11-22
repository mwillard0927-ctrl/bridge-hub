-- Bridge Hub v7: any locked device can create a project and choose which devices can see it. No invite codes.
alter table public.hub_projects add column if not exists allowed text[];
alter table public.hub_projects add column if not exists created_by_device text;

create or replace function public.hub_dev_sees_project(pid uuid, dname text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from hub_projects p where p.id = pid and hub_is_member(p.id)
    and (p.allowed is null or exists (select 1 from unnest(p.allowed) a where lower(a) = lower(dname))));
$$;

-- direct reads: only projects/posts open to every device on the login
drop policy if exists "projects read" on public.hub_projects;
create policy "projects read" on public.hub_projects for select to authenticated using (hub_is_member(id) and allowed is null);
drop policy if exists "posts read" on public.hub_posts;
create policy "posts read" on public.hub_posts for select to authenticated
  using (hub_is_member(project_id) and recipients is null and exists (select 1 from public.hub_projects pr where pr.id = project_id and pr.allowed is null));

-- projects this device can see (open + restricted ones it's on)
create or replace function public.hub_my_projects(p_token text) returns setof public.hub_projects
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token);
  return query select p.* from hub_projects p where hub_is_member(p.id)
    and (p.allowed is null or (m.id is not null and exists (select 1 from unnest(p.allowed) a where lower(a) = lower(m.name))))
    order by p.created_at;
end $$;

-- posts/replies not readable directly (private posts, or posts in restricted projects) that this device may see
create or replace function public.hub_private_posts(p_token text, p_project uuid) returns setof public.hub_posts
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices; restricted boolean;
begin
  m := hub_me(p_token); if m.id is null or not hub_dev_sees_project(p_project, m.name) then return; end if;
  select allowed is not null into restricted from hub_projects where id = p_project;
  return query select * from hub_posts p where p.project_id = p_project and (p.recipients is not null or restricted) and hub_can_see(p, m.name)
    order by created_at desc limit 500;
end $$;
create or replace function public.hub_private_replies(p_token text, p_project uuid) returns setof public.hub_replies
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices; restricted boolean;
begin
  m := hub_me(p_token); if m.id is null or not hub_dev_sees_project(p_project, m.name) then return; end if;
  select allowed is not null into restricted from hub_projects where id = p_project;
  return query select r.* from hub_replies r join hub_posts p on p.id = r.post_id
    where r.project_id = p_project and (p.recipients is not null or restricted) and hub_can_see(p, m.name) order by r.created_at limit 3000;
end $$;

-- create: any locked device (or the very first auto board on a new login)
drop function if exists public.hub_create_project(text);
drop function if exists public.hub_create_project(text,text);
create or replace function public.hub_create_project(p_name text, p_token text default null, p_devices text[] default null) returns public.hub_projects
language plpgsql security definer set search_path = public as $$
declare r hub_projects; m hub_devices; al text[];
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  m := hub_me(p_token);
  if exists (select 1 from hub_members where user_id = auth.uid()) and m.id is null then raise exception 'Lock in this device first'; end if;
  if p_devices is not null and m.id is not null then al := array(select distinct x from unnest(p_devices || m.name) x where x is not null and x <> ''); end if;
  insert into hub_projects(name, invite_code, owner, allowed, created_by_device)
  values (trim(p_name), upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)), auth.uid(), al, m.name) returning * into r;
  insert into hub_members(project_id, user_id, role) values (r.id, auth.uid(), 'admin');
  return r;
end $$;

-- change who can see a project: its creator device or the manager
create or replace function public.hub_set_project_devices(p_token text, p_project uuid, p_devices text[]) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_projects;
begin
  m := hub_me(p_token); select * into p from hub_projects where id = p_project;
  if m.id is null or p.id is null or not hub_is_member(p.id) then raise exception 'Not found'; end if;
  if not (m.is_manager or lower(coalesce(p.created_by_device,'')) = lower(m.name)) then raise exception 'Only the project creator or the manager can change this'; end if;
  update hub_projects set allowed = case when p_devices is null then null else array(select distinct x from unnest(p_devices || m.name) x where x <> '') end where id = p.id;
end $$;

-- posting/replying/viewing also respect project access
create or replace function public.hub_post(p_token text, p_project uuid, p_title text, p_body text, p_tag text, p_due date,
  p_file_path text default null, p_file_name text default null, p_file_size bigint default null, p_file_type text default null,
  p_recipients text[] default null) returns public.hub_posts
language plpgsql security definer set search_path = public as $$
declare m hub_devices; r hub_posts; rec text[];
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Lock in this device first'; end if;
  if not hub_dev_sees_project(p_project, m.name) then raise exception 'Not on this project'; end if;
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
  if p.id is null or not hub_dev_sees_project(p.project_id, m.name) or not hub_can_see(p, m.name) then raise exception 'Post not found'; end if;
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
  if p.id is null or not hub_dev_sees_project(p.project_id, m.name) or not hub_can_see(p, m.name) then return; end if;
  insert into hub_views(post_id, user_id, project_id, device) values (p.id, auth.uid(), p.project_id, m.name) on conflict do nothing;
end $$;

grant execute on function public.hub_dev_sees_project(uuid,text), public.hub_my_projects(text), public.hub_private_posts(text,uuid),
  public.hub_private_replies(text,uuid), public.hub_create_project(text,text,text[]), public.hub_set_project_devices(text,uuid,text[]),
  public.hub_post(text,uuid,text,text,text,date,text,text,bigint,text,text[]), public.hub_reply(text,uuid,uuid,text,text,text,bigint,text),
  public.hub_view(text,uuid) to authenticated;

-- rename / delete a project: its creator device or the manager
create or replace function public.hub_project_admin(p_token text, p_project uuid, p_action text, p_name text default null) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_projects;
begin
  m := hub_me(p_token); select * into p from hub_projects where id = p_project;
  if m.id is null or p.id is null or not hub_is_member(p.id) then raise exception 'Not found'; end if;
  if not (m.is_manager or lower(coalesce(p.created_by_device,'')) = lower(m.name)) then raise exception 'Only the project creator or the manager can change this'; end if;
  if p_action = 'rename' then update hub_projects set name = left(trim(p_name),60) where id = p.id;
  elsif p_action = 'delete' then delete from hub_projects where id = p.id;
  else raise exception 'Unknown action'; end if;
end $$;
grant execute on function public.hub_project_admin(text,uuid,text,text) to authenticated;
