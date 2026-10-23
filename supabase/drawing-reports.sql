-- Reports on drawings: anyone signed in can report one (once); Roman (admin) reviews them on the Reported Images
-- page. A shared drawing reported by 3 people is hidden until he looks. Run once in Supabase's SQL editor.
create table public.drawing_reports (
  drawing_id text not null check (char_length(drawing_id) between 1 and 80),
  user_id uuid not null references auth.users on delete cascade default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (drawing_id, user_id)
);

create function public.hide_reported_drawing() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.drawing_id ~ '^s[0-9]+$' and (select count(*) from public.drawing_reports where drawing_id = new.drawing_id) >= 3 then
    update public.shared_drawings set hidden = true where id = substring(new.drawing_id from 2)::bigint;
  end if;
  return new;
end $$;
create trigger hide_reported_drawing after insert on public.drawing_reports for each row execute function public.hide_reported_drawing();

alter table public.drawing_reports enable row level security;
create policy "report a drawing as yourself" on public.drawing_reports for insert with check (user_id = auth.uid());
create policy "admins read drawing reports" on public.drawing_reports for select using (public.is_admin() or user_id = auth.uid());
create policy "admins clear drawing reports" on public.drawing_reports for delete using (public.is_admin());
grant insert (drawing_id), select, delete on public.drawing_reports to authenticated;
