-- ============================================================
-- Win and Swim Finance: monthly_summary(), one month's totals for a report key
--
-- Lets a script without a login (Vlad's chief of staff) read ONE month's totals:
-- income, costs, profit, investments and the btw due. Never individual transactions.
-- The caller must pass a long random report key; only its SHA-256 hash is stored,
-- in private.report_keys, which no API role can see.
--
-- This copy is the one in the public repo: it has NO key hash. The copy with the
-- real hash lives only on Vlad's Mac (~/.config/chief-of-staff/wsfin_report_setup.sql).
-- See SETUP.md, "Monthly totals for the chief of staff", for setup and key rotation.
--
-- Safe to re-run.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- investment categories (see supabase-schema.sql); repeated here so this file runs on its own
alter table public.categories add column if not exists is_investment boolean not null default false;

-- ---------- key store: invisible to the API ----------
-- The `private` schema isn't exposed by the Data API, and anon/authenticated get no
-- rights on it at all. RLS with no policies is a second lock on the table itself.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.report_keys (
  id          bigint generated always as identity primary key,
  label       text not null,                       -- who holds the key, e.g. 'chief-of-staff'
  key_sha256  text not null unique
              check (key_sha256 ~ '^[0-9a-f]{64}$'),  -- hex SHA-256 of the key; never the key itself
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz                          -- set it to switch the key off
);
alter table private.report_keys enable row level security;
revoke all on table private.report_keys from public, anon, authenticated;

-- ---------- the function ----------
-- Mirrors the app (index.html) exactly:
--   * a row counts in the month of report_date when set, else booking_date   (txDate)
--   * categories with exclude_from_pl never count (Stripe payouts, owner money, loans) (inPL)
--   * the category's kind decides the side: money back in a cost category lowers that
--     cost; uncategorized rows go by their sign                              (isCost)
--   * from 2026-10-04 (KOR ended) amounts are excl. btw: btw comes from the row's vat_code,
--     else its category's; vat_cents on a row pins it; shifted btw (rc_eu/rc_world) never
--     changes what a row costs                                               (vatOf, netCents)
--   * investments: costs in categories marked is_investment (refunds lower them too);
--     they stay inside costs and profit, operating_profit = profit + investments
--   * btw_due is the month's exact btw, worked out like the Dashboard's btw for a quarter:
--     sales by the month they count in, costs by the day they were paid, hand-entered costs
--     without a btw code waiting (vatReturn). null for months before the KOR ended.
-- VAT_SINCE in index.html and vat_since below must stay the same date.
-- Uses SHA-256, not bcrypt: the key is 256 random bits, so a slow hash adds no safety,
-- and it would let anyone holding the public anon key burn database CPU per call.

create or replace function public.monthly_summary(p_month date, p_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  vat_since constant date := date '2026-10-04';
  m_start date;
  m_end   date;
  result  jsonb;
begin
  if p_key is null or length(p_key) not between 32 and 256 or not exists (
       select 1 from private.report_keys k
       where k.revoked_at is null
         and k.key_sha256 = encode(extensions.digest(p_key, 'sha256'), 'hex'))
  then
    raise exception 'not authorized' using errcode = '42501';
  end if;
  if p_month is null then
    raise exception 'p_month is required' using errcode = '22004';
  end if;

  m_start := date_trunc('month', p_month)::date;
  m_end   := (date_trunc('month', p_month) + interval '1 month' - interval '1 day')::date;

  with tx as (
    select t.amount_cents,
           t.booking_date,
           coalesce(t.report_date, t.booking_date)                   as counts_in,
           t.vat_cents,
           case when c.id is null then t.amount_cents < 0
                else c.kind = 'expense' end                          as is_cost,
           coalesce(t.vat_code, c.vat_code, 'none')                  as code,
           coalesce(c.is_investment, false)                          as is_investment,
           (t.source = 'manual' and t.vat_code is null
                                and t.vat_cents is null)             as manual_uncoded
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    where not coalesce(c.exclude_from_pl, false)
  ), coded as (
    select tx.*,
           case tx.code when 'none' then null when 'nl9' then 9 else 21 end as rate,
           tx.code in ('rc_eu', 'rc_world')                                  as shifted
    from tx
  ), vat as (
    select coded.*,
           case
             when coded.rate is null then null
             when coded.vat_cents is null and coded.counts_in < vat_since then null
             else (case when coded.amount_cents < 0 then -1 else 1 end) *
                  case when coded.vat_cents is not null then abs(coded.vat_cents)
                       when coded.shifted then round(abs(coded.amount_cents) * coded.rate / 100.0)
                       else round(abs(coded.amount_cents) * coded.rate / (100.0 + coded.rate))
                  end
           end as vat_c
    from coded
  ), net as (
    select vat.*,
           case when vat.vat_c is not null and not vat.shifted
                then vat.amount_cents - vat.vat_c else vat.amount_cents end as net_c
    from vat
  ), sums as (
    select coalesce(sum(net.net_c)  filter (where not net.is_cost
                                             and net.counts_in between m_start and m_end), 0) as income_c,
           coalesce(sum(-net.net_c) filter (where net.is_cost
                                             and net.counts_in between m_start and m_end), 0) as costs_c,
           coalesce(sum(-net.net_c) filter (where net.is_cost and net.is_investment
                                             and net.counts_in between m_start and m_end), 0) as invest_c,
           -- shifted btw nets to zero (declared and deducted together), so only btw inside
           -- an amount moves the total: sales add theirs, costs (negative btw) take theirs off
           coalesce(sum(net.vat_c) filter (where net.vat_c is not null
                                            and not net.shifted
                                            and not (net.is_cost and net.manual_uncoded)
                                            and (case when net.is_cost then net.booking_date
                                                      else net.counts_in end)
                                                between m_start and m_end), 0) as btw_c
    from net
  )
  select jsonb_build_object(
           'month',   to_char(m_start, 'YYYY-MM'),
           'income',  round(s.income_c / 100.0, 2),
           'costs',   round(s.costs_c / 100.0, 2),
           'profit',  round((s.income_c - s.costs_c) / 100.0, 2),
           'investments',      round(s.invest_c / 100.0, 2),
           'operating_profit', round((s.income_c - s.costs_c + s.invest_c) / 100.0, 2),
           'btw_due', case when m_end < vat_since then null else round(s.btw_c / 100.0, 2) end,
           -- last bank booking imported: a month after this date isn't fully in yet
           'bank_data_through', (select max(t.booking_date) from public.transactions t
                                 where t.source = 'import'))
    into result
  from sums s;

  return result;
end;
$$;

-- Only the anon API role may call it (with the key). Supabase grants new functions to
-- anon and authenticated by default, so revoke those explicitly too.
revoke all on function public.monthly_summary(date, text) from public, anon, authenticated;
grant execute on function public.monthly_summary(date, text) to anon;

-- ---------- the key ----------
-- Replace the placeholder with the SHA-256 hex of the key and run this line once.
-- The real hash is never committed here, see SETUP.md.
-- insert into private.report_keys (label, key_sha256)
--   values ('chief-of-staff', '<SHA256_HEX_OF_THE_KEY>')
--   on conflict (key_sha256) do nothing;

notify pgrst, 'reload schema';
