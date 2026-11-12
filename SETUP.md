# Win and Swim Finance — Setup

A private finance dashboard for Win and Swim. Tracks income and expenses from
Rabobank CSV exports, shows monthly profit, margin, and cost breakdowns.
Nothing is visible without logging in.

Stack: one static web page (no build tools) + Supabase (free tier) + GitHub Pages (free).

---

## 1. Create the Supabase project (one time)

1. Go to [supabase.com](https://supabase.com) → sign in → **New project**.
2. Name it e.g. `ws-finance`, pick a **strong database password** (save it), region **West EU**.
3. Wait a minute for the project to be created.

## 2. Create the database

1. In the project, open **SQL Editor** → **New query**.
2. Paste the entire contents of `supabase-schema.sql` from this folder → **Run**.
3. Check **Table Editor**: you should see `categories` (pre-filled), `transactions`, `rules`, `imports`.

The script is safe to run more than once.

## 3. Create your login

1. **Authentication → Users → Add user → Create new user**.
2. Enter your email + a strong password, tick **Auto Confirm User**.

There is no sign-up in the app — this is the only account, created here.

## 4. Connect the app

1. In Supabase: **Project Settings → API** (or "Data API").
2. Copy the **Project URL** and the **anon public** key.
3. Open `config.js` in this folder and paste them in:

```js
window.WSFIN_CONFIG = {
  url: "https://xxxxxxxx.supabase.co",
  anonKey: "eyJ..."
};
```

The anon key is safe to publish — Row Level Security means it can read
**nothing** without your login. Never put the `service_role` key anywhere.

## 5. Host it on GitHub Pages

Already done if the repo exists — the app lives at the repo's Pages URL.
If setting up fresh:

1. Create a GitHub repository and upload every file in this folder.
2. Repo → **Settings → Pages** → Source: **Deploy from a branch** → Branch `main`, folder `/ (root)` → Save.
3. After ~1 minute the app is live at `https://<username>.github.io/<repo>/`.

## 6. Get your bank data in

1. Log in to Rabobank online banking.
2. Payments → **Transactions** → **Download**.
3. Format: **CSV (kommagescheiden)** — pick any date range.
4. In the app: **Import** tab → drop the file in → check the preview → Import.

Re-uploading overlapping periods is safe: duplicates are detected
(by account + Rabobank's sequence number) and skipped automatically.

**Tip:** download once a month; set up rules in **Settings** so recurring
counterparties (pool rental, insurance, …) are categorized automatically.

## 7. Everyday use

- **Dashboard** — pick a year/month: income vs expenses, profit, margin %, cost breakdown.
- **Transactions** — filter, search, and assign categories (rows marked *review* need one).
  Each row also has a **"counts in" month** — use it when an invoice is paid in a
  different month than the one it covers (e.g. pool rent for May paid in June).
  Rules can do this automatically ("month before" option in Settings).
- **Investments** — a cost you chose to make (equipment, a campaign, a course) rather
  than a running cost: give it the category **Investment** in Transactions, or tick
  **investment** on a whole category in Settings. It still counts in Expenses and
  Profit; the Dashboard adds a **Profit before investments** tile. Moving a row to an
  investment category keeps its btw, so Profit itself doesn't change.
- **Import** — upload new CSV exports.
- **Settings** — categories, auto-categorization rules, import history.
- **Add to phone**: open the site in Safari/Chrome → Share → **Add to Home Screen**.

## Updating the app

After changing any file:

1. Upload/push the changed files to GitHub (branch `main`).
2. **Bump the version in `sw.js`** (`ws-finance-v1` → `ws-finance-v2`) so
   phones drop the cached old version.

## Monthly totals for the chief of staff

Vlad's chief of staff (a script with no login) reads one month's totals through the
database function `public.monthly_summary(p_month, p_key)`, defined in
`supabase-monthly-summary.sql`. It returns aggregates only, never a transaction:

```json
{"month":"2026-10","income":1234.56,"costs":987.65,"profit":246.91,"investments":100.00,"operating_profit":346.91,"btw_due":45.67,"bank_data_through":"2026-11-03"}
```

- `income`, `costs`, `profit`: exactly the Dashboard tiles for that month (same
  "counts in" month, same excluded categories, refunds lowering their cost, and excl.
  btw from 4 Oct 2026).
- `investments`: the month's costs in investment categories (already inside `costs`).
  `operating_profit` = `profit` + `investments`, the Dashboard's "Profit before
  investments" tile.
- `btw_due`: the month's exact btw (positive = to pay), worked out the same way as the
  Dashboard's btw for a quarter; `null` for months before the KOR ended.
- `bank_data_through`: the last imported bank booking. A month that ends after this
  date isn't fully imported yet, so its figures are still incomplete.

**How it's protected.** Calling it needs the public anon key (in `config.js`) *and*
a 64-character random report key. The key lives only on Vlad's Mac, in
`~/.config/chief-of-staff/wsfin_report_key` (chmod 600). The database stores only its
SHA-256 hash, in `private.report_keys`: a schema the API doesn't expose and no API
role can read. The function runs as `security definer` with an empty `search_path`,
only the anon role may execute it, and any wrong, short or revoked key gets
`not authorized`. A slow hash like bcrypt isn't needed: guessing 256 random bits is
impossible either way, and bcrypt would let anyone with the public anon key burn
database CPU.

**Never commit the key or its hash.** This repo is public, so
`supabase-monthly-summary.sql` here has only a placeholder. The ready-to-run copy with
the real hash is `~/.config/chief-of-staff/wsfin_report_setup.sql` on Vlad's Mac.

**Calling it.** POST, with the key in the body (never in the URL, which gets logged).
`printf` is a shell builtin, so the key doesn't show up in the process list:

```bash
printf '{"p_month":"%s","p_key":"%s"}' 2026-10-01 "$(cat ~/.config/chief-of-staff/wsfin_report_key)" | curl -s -X POST "https://qyiiyojmkdwireqtwwfd.supabase.co/rest/v1/rpc/monthly_summary" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" --data-binary @-
```

`$ANON` is the `anonKey` from `config.js`. Any day of the month works for `p_month`.

**Keep it in step with the app.** The function copies the profit rules in
`index.html` (`totals`, `isCost`, `catInvestment`, `vatOf`, `netCents`, `vatReturn`). If those change, or
`VAT_SINCE` moves, change the function to match and re-run the SQL.

### Rotate the key

1. Make a new key and hash it:

   ```bash
   (umask 077; openssl rand -hex 32 | tr -d '\n' > ~/.config/chief-of-staff/wsfin_report_key.new)
   ```

   ```bash
   shasum -a 256 < ~/.config/chief-of-staff/wsfin_report_key.new | cut -d' ' -f1
   ```

2. In Supabase → **SQL Editor**, add the new hash and switch every other key off:

   ```sql
   insert into private.report_keys (label, key_sha256) values ('chief-of-staff', '<new hash>');
   update private.report_keys set revoked_at = now()
    where revoked_at is null and key_sha256 <> '<new hash>';
   ```

3. Put the new key in place:

   ```bash
   mv ~/.config/chief-of-staff/wsfin_report_key.new ~/.config/chief-of-staff/wsfin_report_key
   ```

### Revoke access

Switch every key off at once (takes effect on the next call):

```sql
update private.report_keys set revoked_at = now() where revoked_at is null;
```

Remove the whole thing:

```sql
drop function if exists public.monthly_summary(date, text);
drop table if exists private.report_keys;
```

## Notes

- Free Supabase projects **pause after ~7 days without activity**; open the
  Supabase dashboard and hit Restore if that happens.
- All amounts are EUR. Positive = income, negative = expense.
- `sample-data/` contains fake Rabobank-format CSVs for testing the import —
  don't import them into your real database (if you do: they're all rows on
  IBAN `NL99RABO0000000001`, easy to filter and delete in Supabase).
