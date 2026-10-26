-- Starred drawings (Roman's, as admin): a shortlist of Doot's sketches (sketches.json) to pick its 500 treasured
-- drawings from, and the ones he's starred. Only admins can see or change either. Run once in Supabase's SQL editor,
-- after schema.sql; the shortlist itself is added separately (its ids aren't kept in this public repo).
create table public.sketch_shortlist (
  sketch_id text primary key check (char_length(sketch_id) between 1 and 80),
  created_at timestamptz not null default now()
);
create table public.sketch_stars (
  sketch_id text primary key references public.sketch_shortlist on delete cascade,
  starred_by uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now()
);

alter table public.sketch_shortlist enable row level security;
alter table public.sketch_stars enable row level security;
create policy "admins see the shortlist" on public.sketch_shortlist for select using (public.is_admin());
create policy "admins see stars" on public.sketch_stars for select using (public.is_admin());
create policy "admins star" on public.sketch_stars for insert with check (public.is_admin());
create policy "admins unstar" on public.sketch_stars for delete using (public.is_admin());

grant select on public.sketch_shortlist to authenticated;
grant select, delete on public.sketch_stars to authenticated;
grant insert (sketch_id) on public.sketch_stars to authenticated;
