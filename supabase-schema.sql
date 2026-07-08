-- ============================================================
-- Win and Swim Finance — Supabase schema
-- Paste this whole file into the Supabase SQL Editor and Run.
-- Safe to re-run: everything is idempotent.
-- ============================================================

-- ---------- tables ----------

create table if not exists public.categories (
  id          bigint generated always as identity primary key,
  name        text not null unique,
  kind        text not null check (kind in ('income','expense')),
  sort_order  int  not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.transactions (
  id                  bigint generated always as identity primary key,
  account_iban        text not null default 'MANUAL',   -- Rabobank "IBAN/BBAN"; 'MANUAL' for hand-entered rows
  sequence_no         bigint,                            -- Rabobank "Volgnr"; null for manual rows
  booking_date        date not null,                     -- "Datum"
  amount_cents        bigint not null,                   -- signed cents; negative = money out
  currency            text not null default 'EUR',       -- "Munt"
  counterparty_iban   text not null default '',          -- "Tegenrekening IBAN/BBAN"
  counterparty_name   text not null default '',          -- "Naam tegenpartij"
  description         text not null default '',          -- Omschrijving-1..3 joined
  code                text not null default '',          -- Rabobank "Code"
  transaction_ref     text not null default '',          -- "Transactiereferentie"
  balance_after_cents bigint,                            -- "Saldo na trn"
  category_id         bigint references public.categories(id) on delete set null,
  report_date         date,                               -- month the cost/income belongs to, when it differs from booking_date (e.g. invoices paid a month later)
  source              text not null default 'import' check (source in ('import','manual')),
  created_at          timestamptz not null default now(),
  -- (IBAN, Volgnr) uniquely identifies a booked Rabobank transaction, so
  -- re-uploading overlapping CSV exports can never create duplicates.
  -- Manual rows have sequence_no = null and never collide (NULLS DISTINCT).
  constraint transactions_dedupe unique (account_iban, sequence_no)
);

create index if not exists transactions_date_idx     on public.transactions (booking_date desc);
create index if not exists transactions_category_idx on public.transactions (category_id);

create table if not exists public.rules (
  id          bigint generated always as identity primary key,
  keyword     text not null,
  match_field text not null default 'any' check (match_field in ('counterparty','description','any')),
  category_id bigint not null references public.categories(id) on delete cascade,
  priority    int not null default 100,   -- lower = checked first
  shift_months int not null default 0,    -- -1 = invoice covers the previous month (report_date shifts back)
  created_at  timestamptz not null default now()
);

-- columns added after the first release (no-ops on fresh installs)
alter table public.transactions add column if not exists report_date date;
alter table public.rules add column if not exists shift_months int not null default 0;

create table if not exists public.imports (
  id            bigint generated always as identity primary key,
  filename      text not null,
  added_count   int not null,
  skipped_count int not null,
  imported_at   timestamptz not null default now()
);

-- ---------- row level security ----------
-- Financial data: NOTHING is readable or writable without being logged in.
-- There is deliberately no policy for the anon role.

alter table public.categories   enable row level security;
alter table public.transactions enable row level security;
alter table public.rules        enable row level security;
alter table public.imports      enable row level security;

drop policy if exists "authenticated full access" on public.categories;
create policy "authenticated full access" on public.categories
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on public.transactions;
create policy "authenticated full access" on public.transactions
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on public.rules;
create policy "authenticated full access" on public.rules
  for all to authenticated using (true) with check (true);

drop policy if exists "authenticated full access" on public.imports;
create policy "authenticated full access" on public.imports
  for all to authenticated using (true) with check (true);

-- ---------- seed data (only when categories is empty) ----------

do $$
declare
  pool_rental_id bigint;
begin
  if not exists (select 1 from public.categories) then
    insert into public.categories (name, kind, sort_order) values
      ('Lesson fees',   'income',  1),
      ('Other income',  'income',  2),
      ('Pool rental',   'expense', 10),
      ('Salaries',      'expense', 11),
      ('Insurance',     'expense', 12),
      ('Marketing',     'expense', 13),
      ('Materials',     'expense', 14),
      ('Software',      'expense', 15),
      ('Bank fees',     'expense', 16),
      ('Other expense', 'expense', 17);

    select id into pool_rental_id from public.categories where name = 'Pool rental';

    -- Example auto-categorization rule; manage rules in the app's Settings.
    insert into public.rules (keyword, match_field, category_id, priority)
    values ('optisport', 'any', pool_rental_id, 10);
  end if;
end $$;
