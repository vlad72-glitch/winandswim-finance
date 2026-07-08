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
- **Import** — upload new CSV exports.
- **Settings** — categories, auto-categorization rules, import history.
- **Add to phone**: open the site in Safari/Chrome → Share → **Add to Home Screen**.

## Updating the app

After changing any file:

1. Upload/push the changed files to GitHub (branch `main`).
2. **Bump the version in `sw.js`** (`ws-finance-v1` → `ws-finance-v2`) so
   phones drop the cached old version.

## Notes

- Free Supabase projects **pause after ~7 days without activity**; open the
  Supabase dashboard and hit Restore if that happens.
- All amounts are EUR. Positive = income, negative = expense.
- `sample-data/` contains fake Rabobank-format CSVs for testing the import —
  don't import them into your real database (if you do: they're all rows on
  IBAN `NL99RABO0000000001`, easy to filter and delete in Supabase).
