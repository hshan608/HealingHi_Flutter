alter table public.users
  add column if not exists tutorial_progress jsonb not null default '{}'::jsonb;

comment on column public.users.tutorial_progress is
  'Per-device completion state for versioned in-app tutorial sections.';
