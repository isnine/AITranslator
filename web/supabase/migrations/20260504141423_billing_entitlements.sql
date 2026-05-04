create table public.billing_entitlements (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null check (plan in ('monthly', 'yearly', 'lifetime')),
  status text not null,
  lifetime_access boolean not null default false,
  current_period_end timestamptz null,
  stripe_customer_id text,
  stripe_subscription_id text unique,
  stripe_price_id text,
  stripe_checkout_session_id text,
  last_event_id text,
  updated_at timestamptz not null default now()
);

alter table public.billing_entitlements enable row level security;

create policy "billing_entitlements own row read"
  on public.billing_entitlements for select
  using ((select auth.uid()) = user_id);

create index billing_entitlements_customer_idx
  on public.billing_entitlements (stripe_customer_id);
