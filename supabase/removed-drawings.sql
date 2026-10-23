-- Drawings Roman (admin) took off the site that aren't shared ones: the examples kept as files on the site. The site
-- leaves out any drawing listed here. Run once in Supabase's SQL editor, after schema.sql.
create table public.removed_drawings (
  drawing_id text primary key check (char_length(drawing_id) between 1 and 80),
  removed_by uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.removed_drawings enable row level security;
create policy "everyone sees what's removed" on public.removed_drawings for select using (true);
create policy "admins remove" on public.removed_drawings for insert with check (public.is_admin());
create policy "admins put back" on public.removed_drawings for delete using (public.is_admin());
grant select on public.removed_drawings to anon, authenticated;
grant insert (drawing_id), delete on public.removed_drawings to authenticated;
