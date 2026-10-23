-- The Scrappy Book site's database: hearts on drawings, comments, hearts on comments, reports, and each person's
-- profile (their name and whether bad words are masked for them). Run once in Supabase's SQL editor.
-- Anyone can read; only signed-in people can write, and only as themselves (row-level security).

-- each signed-in person: the name shown with their comments, and censored mode (on unless they turn it off)
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  censor boolean not null default true,
  created_at timestamptz not null default now()
);

-- a profile is made the first time someone signs in, named from their Google account
create function public.new_profile() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(coalesce(nullif(new.raw_user_meta_data->>'name', ''), 'Doot friend'), 40));
  return new;
end $$;
create trigger on_new_user after insert on auth.users for each row execute function public.new_profile();

-- who can hide any comment (Roman); add yourself once you've signed in (see README)
create table public.admins (user_id uuid primary key references auth.users on delete cascade);
create function public.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;

-- hearts on drawings (drawing_id is the drawing's id on the site, e.g. 'waving-hello-cat')
create table public.drawing_hearts (
  drawing_id text not null check (char_length(drawing_id) between 1 and 80),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (drawing_id, user_id)
);

create table public.comments (
  id bigint generated always as identity primary key,
  drawing_id text not null check (char_length(drawing_id) between 1 and 80),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  body text not null check (char_length(btrim(body)) between 1 and 500),
  hidden boolean not null default false,   -- hidden by Roman, or by 3 reports
  created_at timestamptz not null default now()
);
create index comments_by_drawing on public.comments (drawing_id, created_at);

create table public.comment_hearts (
  comment_id bigint not null references public.comments on delete cascade,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  primary key (comment_id, user_id)
);

create table public.reports (
  comment_id bigint not null references public.comments on delete cascade,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

-- no more than 5 comments a minute, or 100 a day, from one person
create function public.comment_limit() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.comments where user_id = new.user_id and created_at > now() - interval '1 minute') >= 5
     or (select count(*) from public.comments where user_id = new.user_id and created_at > now() - interval '1 day') >= 100 then
    raise exception 'Slow down a little: too many comments at once.';
  end if;
  return new;
end $$;
create trigger comment_limit before insert on public.comments for each row execute function public.comment_limit();

-- a comment reported by 3 people is hidden until Roman looks
create function public.hide_reported() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.reports where comment_id = new.comment_id) >= 3 then
    update public.comments set hidden = true where id = new.comment_id;
  end if;
  return new;
end $$;
create trigger hide_reported after insert on public.reports for each row execute function public.hide_reported();

-- counts, for showing and sorting
create view public.drawing_heart_counts with (security_invoker = true) as
  select drawing_id, count(*)::int as hearts from public.drawing_hearts group by drawing_id;
create view public.comment_counts with (security_invoker = true) as
  select drawing_id, count(*)::int as comments from public.comments where not hidden group by drawing_id;
-- a drawing's comments with their writer's name and hearts (hidden ones only for Roman)
create view public.comments_shown with (security_invoker = true) as
  select c.id, c.drawing_id, c.user_id, c.body, c.hidden, c.created_at, p.display_name,
         (select count(*)::int from public.comment_hearts h where h.comment_id = c.id) as hearts
  from public.comments c join public.profiles p on p.id = c.user_id;

-- who may do what
alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.drawing_hearts enable row level security;
alter table public.comments enable row level security;
alter table public.comment_hearts enable row level security;
alter table public.reports enable row level security;

create policy "names are public" on public.profiles for select using (true);
create policy "your own profile" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "admins see admins" on public.admins for select using (public.is_admin());

create policy "hearts are public" on public.drawing_hearts for select using (true);
create policy "heart as yourself" on public.drawing_hearts for insert with check (user_id = auth.uid());
create policy "unheart your own" on public.drawing_hearts for delete using (user_id = auth.uid());

create policy "shown comments are public" on public.comments for select using (not hidden or user_id = auth.uid() or public.is_admin());
create policy "comment as yourself" on public.comments for insert with check (user_id = auth.uid() and not hidden);
create policy "delete your own, or any as admin" on public.comments for delete using (user_id = auth.uid() or public.is_admin());
create policy "admins hide and unhide" on public.comments for update using (public.is_admin()) with check (public.is_admin());

create policy "comment hearts are public" on public.comment_hearts for select using (true);
create policy "heart a comment as yourself" on public.comment_hearts for insert with check (user_id = auth.uid());
create policy "unheart your own comment heart" on public.comment_hearts for delete using (user_id = auth.uid());

create policy "report as yourself" on public.reports for insert with check (user_id = auth.uid());
create policy "admins read reports" on public.reports for select using (public.is_admin() or user_id = auth.uid());

-- what the site may touch at all (with "automatically expose new tables" off, nothing is reachable until granted);
-- the policies above then decide which rows
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.drawing_hearts, public.comments, public.comment_hearts to anon, authenticated;
grant select on public.drawing_heart_counts, public.comment_counts, public.comments_shown to anon, authenticated;
grant insert, delete on public.drawing_hearts, public.comment_hearts to authenticated;
grant insert, delete on public.comments to authenticated;
grant update (hidden) on public.comments to authenticated;           -- only admins get past the policy
grant insert, select on public.reports to authenticated;
grant select on public.admins to authenticated;
grant execute on function public.is_admin() to anon, authenticated;
-- a profile's name and censored mode can be changed, never its id
revoke update on public.profiles from anon, authenticated;
grant update (display_name, censor) on public.profiles to authenticated;
