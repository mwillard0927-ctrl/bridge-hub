-- Bridge Hub v9: polls, checklists, events.
alter table public.hub_posts add column if not exists ptype text not null default 'post';
alter table public.hub_posts add column if not exists options jsonb;
alter table public.hub_posts add column if not exists event_at timestamptz;

create table if not exists public.hub_votes (
  post_id uuid references public.hub_posts on delete cascade,
  user_id uuid references auth.users on delete cascade,
  device text not null,
  choice int not null,
  voted_at timestamptz not null default now(),
  primary key (post_id, user_id, device)
);
alter table public.hub_votes enable row level security;

create or replace function public.hub_post_x(p_token text, p_project uuid, p_title text, p_body text, p_tag text, p_due date,
  p_file_path text, p_file_name text, p_file_size bigint, p_file_type text, p_recipients text[],
  p_ptype text, p_options jsonb, p_event_at timestamptz) returns public.hub_posts
language plpgsql security definer set search_path = public as $$
declare m hub_devices; r hub_posts; rec text[];
begin
  m := hub_me(p_token);
  if m.id is null then raise exception 'Pick your name first'; end if;
  if not hub_dev_sees_project(p_project, m.name) then raise exception 'Not on this project'; end if;
  if coalesce(p_ptype,'post') not in ('post','poll','checklist','event') then raise exception 'Unknown post type'; end if;
  if p_recipients is not null then rec := array(select distinct x from unnest(p_recipients || m.name) x where x is not null and x <> ''); end if;
  insert into hub_posts(project_id, user_id, device, title, body, tag, due, file_path, file_name, file_size, file_type, recipients, ptype, options, event_at)
  values (p_project, auth.uid(), m.name, left(p_title,140), p_body, coalesce(p_tag,'Note'), p_due, p_file_path, p_file_name, p_file_size, p_file_type, rec,
          coalesce(p_ptype,'post'), p_options, p_event_at) returning * into r;
  return r;
end $$;

create or replace function public.hub_vote(p_token text, p_post uuid, p_choice int) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts;
begin
  m := hub_me(p_token); if m.id is null then raise exception 'Pick your name first'; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or p.ptype <> 'poll' or not hub_dev_sees_project(p.project_id, m.name) or not hub_can_see(p, m.name) then raise exception 'Poll not found'; end if;
  if p_choice < 0 or p_choice >= jsonb_array_length(p.options) then raise exception 'Bad choice'; end if;
  insert into hub_votes(post_id, user_id, device, choice) values (p.id, auth.uid(), m.name, p_choice)
  on conflict (post_id, user_id, device) do update set choice = excluded.choice, voted_at = now();
end $$;

create or replace function public.hub_check_item(p_token text, p_post uuid, p_idx int, p_done boolean) returns void
language plpgsql security definer set search_path = public as $$
declare m hub_devices; p hub_posts;
begin
  m := hub_me(p_token); if m.id is null then raise exception 'Pick your name first'; end if;
  select * into p from hub_posts where id = p_post;
  if p.id is null or p.ptype <> 'checklist' or not hub_dev_sees_project(p.project_id, m.name) or not hub_can_see(p, m.name) then raise exception 'Checklist not found'; end if;
  if p_idx < 0 or p_idx >= jsonb_array_length(p.options) then raise exception 'Bad item'; end if;
  update hub_posts set options = jsonb_set(jsonb_set(options, array[p_idx::text,'done'], to_jsonb(p_done)), array[p_idx::text,'by'],
    case when p_done then to_jsonb(m.name) else 'null'::jsonb end), updated_at = now() where id = p.id;
end $$;

create or replace function public.hub_poll_votes(p_token text, p_project uuid) returns table(post_id uuid, device text, user_id uuid, choice int)
language plpgsql stable security definer set search_path = public as $$
declare m hub_devices;
begin
  m := hub_me(p_token); if m.id is null or not hub_dev_sees_project(p_project, m.name) then return; end if;
  return query select v.post_id, v.device, v.user_id, v.choice from hub_votes v join hub_posts p on p.id = v.post_id
    where p.project_id = p_project and hub_can_see(p, m.name);
end $$;

grant execute on function public.hub_post_x(text,uuid,text,text,text,date,text,text,bigint,text,text[],text,jsonb,timestamptz),
  public.hub_vote(text,uuid,int), public.hub_check_item(text,uuid,int,boolean), public.hub_poll_votes(text,uuid) to authenticated;
