-- Bridge Hub: run once in Supabase → SQL Editor
create table if not exists public.hub_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
create table if not exists public.hub_drops (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  from_device text,
  kind text not null check (kind in ('text','file')),
  title text, text text check (char_length(text) <= 200000),
  name text, size bigint, type text, path text, is_text boolean default false,
  created_at timestamptz not null default now()
);
alter table public.hub_devices enable row level security;
alter table public.hub_drops enable row level security;
grant select, insert, update, delete on public.hub_devices to authenticated;
grant select, insert, delete on public.hub_drops to authenticated;
create policy "own devices" on public.hub_devices for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own drops"   on public.hub_drops   for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
alter publication supabase_realtime add table public.hub_drops;
alter table public.hub_drops replica identity full;

insert into storage.buckets (id, name, public, file_size_limit)
values ('hub','hub',false, 10485760) on conflict (id) do nothing;
create policy "hub own read"   on storage.objects for select to authenticated using (bucket_id='hub' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "hub own upload" on storage.objects for insert to authenticated with check (bucket_id='hub' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "hub own delete" on storage.objects for delete to authenticated using (bucket_id='hub' and (storage.foldername(name))[1] = auth.uid()::text);
