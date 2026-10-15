-- Työajanseuranta: Supabase-tietokanta. Aja kerran: Supabase > SQL Editor > New query > Run.

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text,
  role text not null default 'user' check (role in ('user','admin'))
);

create table public.docs (
  path text primary key,
  parent text not null,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
create index docs_parent_idx on public.docs(parent);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin')
$$;

-- Työntekijä saa kirjoittaa vain omaan haaraansa (entries/<oma id>/..., staff/<oma id>); projektit vain admin.
create or replace function public.can_write(p text) returns boolean
language sql stable set search_path = public as $$
  select (split_part(p,'/',1) in ('entries','staff') and split_part(p,'/',2) = auth.uid()::text)
      or (split_part(p,'/',1) = 'projects' and public.is_admin())
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.docs enable row level security;

create policy profiles_read on public.profiles for select to authenticated using (true);

create policy docs_select on public.docs for select to authenticated using (
  public.is_admin()
  or split_part(path,'/',1) = 'projects'
  or (split_part(path,'/',1) in ('entries','staff') and split_part(path,'/',2) = auth.uid()::text)
);
create policy docs_insert on public.docs for insert to authenticated with check (public.can_write(path));
create policy docs_update on public.docs for update to authenticated using (public.can_write(path)) with check (public.can_write(path));
create policy docs_delete on public.docs for delete to authenticated using (public.can_write(path));

-- Reaaliaikaiset päivitykset
alter publication supabase_realtime add table public.docs;

-- Tositteet (yksityinen säilö): työntekijä lataa omaan kansioonsa, admin näkee kaikki
insert into storage.buckets (id, name, public) values ('receipts', 'receipts', false) on conflict do nothing;
create policy receipts_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);
create policy receipts_select on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy receipts_delete on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

-- Tee itsestäsi esihenkilö (aja sen jälkeen kun olet luonut oman käyttäjäsi, vaihda sähköposti):
-- update public.profiles set role = 'admin' where id = (select id from auth.users where email = 'sinun@osoite.fi');
