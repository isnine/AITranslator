-- TLingo Web initial schema: per-user settings and translation history.
-- All tables live in the exposed `public` schema, so RLS is mandatory.

create table public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  model text not null default 'gpt-5.4-nano',
  target_language text not null default 'zh-Hans',
  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;

create policy "user_settings own row read"
  on public.user_settings for select
  using ((select auth.uid()) = user_id);

create policy "user_settings own row insert"
  on public.user_settings for insert
  with check ((select auth.uid()) = user_id);

create policy "user_settings own row update"
  on public.user_settings for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create table public.translations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  action_id text not null,
  source_lang text not null,
  target_lang text not null,
  input text not null,
  output text not null
);

alter table public.translations enable row level security;

create policy "translations own rows read"
  on public.translations for select
  using ((select auth.uid()) = user_id);

create policy "translations own rows insert"
  on public.translations for insert
  with check ((select auth.uid()) = user_id);

create policy "translations own rows delete"
  on public.translations for delete
  using ((select auth.uid()) = user_id);

create index translations_user_created_idx
  on public.translations (user_id, created_at desc);
