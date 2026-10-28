-- TRIP: schema support for admin-created test accounts and profile avatars.
-- Test account classification already exists in public.profiles; make this migration safe to re-run.
alter table public.profiles add column if not exists avatar_url text;
create index if not exists profiles_phone_idx on public.profiles(phone) where phone is not null;

-- This bucket is only for profile avatars (never driver identity documents).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];
