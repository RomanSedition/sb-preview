-- Drawings Doot owners share from their Doot's Scrappy Book (run once in Supabase's SQL editor, after schema.sql).
-- Only signed-in people can share, as themselves, up to 20 a day; a drawing has to be a small SVG with nothing in it
-- that could run (the site only ever shows it as an image, and the app tidies it again, but it's checked here too).

create table public.shared_drawings (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  title text not null check (char_length(btrim(title)) between 1 and 60),
  blurb text not null default '' check (char_length(blurb) <= 300),
  svg text not null check (char_length(svg) <= 16000 and svg ~* '^\s*<svg[\s>]' and svg ~* '</svg>\s*$'
                           and svg !~* '<script|<foreignobject|\son[a-z]+\s*=|javascript:'),
  tags text[] not null default '{}' check (cardinality(tags) <= 8),
  when_fits text not null default '' check (char_length(when_fits) <= 120),  -- an animation's "when"
  hidden boolean not null default false,                                    -- hidden by Roman
  created_at timestamptz not null default now()
);
create index shared_drawings_newest on public.shared_drawings (created_at desc);

create function public.share_limit() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.shared_drawings where user_id = new.user_id and created_at > now() - interval '1 day') >= 20 then
    raise exception 'That''s plenty for today: up to 20 shared drawings a day.';
  end if;
  return new;
end $$;
create trigger share_limit before insert on public.shared_drawings for each row execute function public.share_limit();

-- the list on the site, with who shared each one
create view public.shared_drawings_shown with (security_invoker = true) as
  select d.id, d.user_id, d.title, d.blurb, d.svg, d.tags, d.when_fits, d.hidden, d.created_at, p.display_name
  from public.shared_drawings d join public.profiles p on p.id = d.user_id;

-- one drawing, as Doot's app adds it ("Add to my Doot"): {"title", "blurb", "svg", "tags", "when"}
create function public.shared_drawing(n bigint) returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('title', d.title, 'blurb', d.blurb, 'svg', d.svg, 'tags', d.tags, 'when', d.when_fits)
  from public.shared_drawings d where d.id = n and not d.hidden
$$;

alter table public.shared_drawings enable row level security;
create policy "shown drawings are public" on public.shared_drawings for select using (not hidden or user_id = auth.uid() or public.is_admin());
create policy "share as yourself" on public.shared_drawings for insert with check (user_id = auth.uid() and not hidden);
create policy "delete your own, or any as admin" on public.shared_drawings for delete using (user_id = auth.uid() or public.is_admin());
create policy "admins hide and unhide drawings" on public.shared_drawings for update using (public.is_admin()) with check (public.is_admin());

grant select on public.shared_drawings, public.shared_drawings_shown to anon, authenticated;
grant insert (title, blurb, svg, tags, when_fits), delete on public.shared_drawings to authenticated;
grant update (hidden) on public.shared_drawings to authenticated;
grant execute on function public.shared_drawing(bigint) to anon, authenticated;
