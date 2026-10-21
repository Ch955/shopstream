# Day 1 — Load Olist into Azure SQL Database

Goal: the 9 Olist tables typed, keyed and validated in `olist.*` on a free Azure SQL Database,
loaded by a repeatable script. Time: about 60–90 minutes.

## 1. Create the resource group and budget (5 min)

1. Azure portal → Resource groups → Create: `rg-shopstream-dev`, region **Central India**, tag `project=shopstream`.
2. Cost Management → Budgets → Add: ₹500 monthly, alerts at 50 / 90 / 100 % (actual) and 100 % (forecast) to your email.

## 2. Create the free Azure SQL Database (10 min)

1. Portal → search **Azure SQL** → SQL databases → Create. Click **Apply offer** on the free-offer banner.
2. Basics
   - Resource group: `rg-shopstream-dev`
   - Database name: `sqldb-shopstream-oltp`
   - Server: Create new → `sql-shopstream-<initials>`, Central India
   - Authentication: **Use both SQL and Microsoft Entra authentication**. Admin login `shopstreamadmin` + a strong
     password (save it in a password manager). Set yourself as Entra admin.
   - Behavior when free limit reached: **Auto-pause the database until next month** (never "continue for additional charges" — it can't be undone)
3. Networking: Public endpoint · **Add current client IP address = Yes** · **Allow Azure services and resources to access this server = Yes** (ADF needs it on Day 2).
4. Additional settings: Use existing data = None. Collation default.
5. Review + create. Confirm the summary shows the free offer and an estimated cost of 0.

## 3. Get the data (5 min)

```bash
pip install -r requirements-dev.txt
python scripts/download_olist.py        # or: kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
python scripts/load_olist_to_azuresql.py --dry-run   # parses all 9 CSVs, no DB
```

The dry run should list 9 tables with the row counts in step 6 and flag nulls (e.g. `order_delivered_customer_date`).

## 4. Create the schema (5 min)

Connect with SSMS (server `sql-shopstream-<initials>.database.windows.net`, SQL Server authentication,
Options → Connection Properties → database `sqldb-shopstream-oltp`, Encrypt = Mandatory).
The first connection can take ~1 minute while the serverless DB resumes.

Run `sql/source/01_create_schema_and_tables.sql`.

## 5. Load (10–20 min, mostly geolocation's 1M rows)

1. Install **Microsoft ODBC Driver 18 for SQL Server** (Windows installer from Microsoft Learn).
2. `cp .env.example .env` and fill in server, database, user and password.
3. Run:

```bash
python scripts/load_olist_to_azuresql.py
```

The script loads parents before children, retries while the DB resumes (error 40613), clears and reloads
each table so it is safe to re-run, writes one row per table to `dbo.load_audit`, and closes the connection
at the end so the DB can auto-pause. To redo one table: `--tables geolocation`.

## 6. Constrain and validate (5 min)

Run `sql/source/02_constraints_and_indexes.sql` (foreign keys `WITH CHECK` + watermark indexes),
then `sql/source/03_validate_load.sql`. Every row should be PASS:

| Table | Rows |
| --- | ---: |
| geolocation | 1,000,163 |
| order_items | 112,650 |
| order_payments | 103,886 |
| customers | 99,441 |
| orders | 99,441 |
| order_reviews | 99,224 |
| products | 32,951 |
| sellers | 3,095 |
| product_category_translation | 71 |

## 7. Close out (2 min)

- Disconnect SSMS (an open session keeps the DB awake and spends free vCore-seconds).
- Commit: `git add . && git commit -m "Day 1: Olist source schema + loader" && git push`.
- In the portal, check the database → Overview → free amount remaining.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Cannot open server ... client with IP address ... is not allowed` | Server → Networking → add your current IP (home IPs change) |
| Error 40613 "database is not currently available" | DB is resuming from auto-pause; the loader retries, SSMS: wait a minute |
| `Data source name not found` | ODBC Driver 18 not installed, or `ODBC_DRIVER` in `.env` doesn't match the installed name |
| FK error in 02 | A table didn't fully load; check `dbo.load_audit`, re-run the loader for that table |
| Zip codes like `1151` instead of `01151` | You loaded with another tool; the loader restores leading zeros |

## Design notes (interview talking points)

- **Typed, keyed OLTP, not a CSV dump.** PKs on load, FKs validated after load, so the pipeline sees a realistic source.
- **Two source quirks handled explicitly**: `review_id` isn't unique (PK is `review_id, order_id`); geolocation has duplicate rows (surrogate key).
- **`updated_at` on every table** is the watermark for Day 2's incremental ADF copy; the simulator will bump it on change.
- **Idempotent loader with an audit table** — the same pattern ADF will use for its run log.
