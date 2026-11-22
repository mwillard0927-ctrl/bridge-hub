-- Board v2: track which DEVICE posted/viewed (so a shared login still shows "seen by Work laptop, Phone…").
-- Run AFTER board-setup.sql. Safe to run more than once.
alter table public.hub_posts   add column if not exists device text;
alter table public.hub_replies add column if not exists device text;
alter table public.hub_views   add column if not exists device text not null default '';
alter table public.hub_views drop constraint if exists hub_views_pkey;
alter table public.hub_views add constraint hub_views_pkey primary key (post_id, user_id, device);
