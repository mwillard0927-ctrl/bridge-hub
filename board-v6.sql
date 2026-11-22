-- Bridge Hub v6: only the manager device can create new boards or join other logins' boards.
drop function if exists public.hub_create_project(text);
create or replace function public.hub_create_project(p_name text, p_token text default null) returns public.hub_projects
language plpgsql security definer set search_path = public as $$
declare r hub_projects; m hub_devices;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if exists (select 1 from hub_members where user_id = auth.uid()) then
    m := hub_me(p_token);
    if m.id is null or not m.is_manager then raise exception 'Only the manager device can create boards'; end if;
  end if;
  insert into hub_projects(name, invite_code, owner)
  values (trim(p_name), upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)), auth.uid()) returning * into r;
  insert into hub_members(project_id, user_id, role) values (r.id, auth.uid(), 'admin');
  return r;
end $$;
drop function if exists public.hub_join_project(text);
create or replace function public.hub_join_project(p_code text, p_token text default null) returns public.hub_projects
language plpgsql security definer set search_path = public as $$
declare r hub_projects; m hub_devices;
begin
  m := hub_me(p_token);
  if m.id is null or not m.is_manager then raise exception 'Only the manager device can join other boards'; end if;
  select * into r from hub_projects where invite_code = upper(trim(p_code));
  if r.id is null then raise exception 'No project with that code'; end if;
  insert into hub_members(project_id, user_id) values (r.id, auth.uid()) on conflict do nothing;
  return r;
end $$;
grant execute on function public.hub_create_project(text,text), public.hub_join_project(text,text) to authenticated;
