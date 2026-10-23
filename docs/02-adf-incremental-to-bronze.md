# Day 2 — Incremental ingestion: Azure SQL → ADLS Gen2 Bronze with Azure Data Factory

**Previous stage:** Olist in Azure SQL (9 tables, `updated_at` on every row, validated 9/9).
**This stage:** a metadata-driven ADF pipeline that copies only new/changed rows into the lake as Parquet.
**Result:** `bronze/olist/<table>/load_date=YYYY-MM-DD/*.parquet`, a watermark per table, a run log, and a proven incremental re-run.
**Next stage:** Day 3 — an order simulator that keeps changing the source so the pipeline always has work.

## Design in one picture

```
etl.ingest_control ──Lookup──▶ ForEach table (4 in parallel)
                                 ├─ LKP_NewWatermark   SELECT MAX(updated_at)            (freeze upper bound)
                                 ├─ CP_SqlToBronze     WHERE updated_at > last AND <= new  → Parquet
                                 ├─ on success → etl.usp_ingest_success  (move watermark + log, 1 transaction)
                                 └─ on failure → etl.usp_ingest_failure  (log only) → Fail activity
```

Security: Data Factory uses its **system-assigned managed identity** for both SQL and the lake — no passwords or keys stored anywhere.

## 1. Control framework in SQL (5 min)

Query editor → **SQL authentication** → paste and run `sql/source/04_ingestion_control.sql` as is (no `GO` lines to remove).
Result: schema `etl`, 9 rows in `etl.ingest_control` with `last_watermark = 1900-01-01`, empty `etl.ingest_run_log`, two procedures.

## 2. Storage account with ADLS Gen2 (10 min)

Portal → Storage accounts → Create:

| Tab | Setting | Value |
| --- | --- | --- |
| Basics | Resource group | `rg-shopstream-dev` |
| | Name | `stshopstreamcr` (lowercase, globally unique; add digits if taken) |
| | Region | Central India |
| | Primary service | Azure Blob Storage or Azure Data Lake Storage Gen2 |
| | Performance / Redundancy | Standard / **LRS** (cheapest) |
| Advanced | **Enable hierarchical namespace** | **Ticked** — this is what makes it ADLS Gen2 |
| | Access tier | Hot |
| Networking | Public network access | Enabled from all networks (dev) |
| Tags | `project` | `shopstream` |

Then: storage account → **Containers** → create `bronze`, `silver`, `gold` (private access).

## 3. Data Factory (5 min)

Portal → Data factories → Create: resource group `rg-shopstream-dev`, name **`adf-shopstream-cr`**, region Central India, version V2.
Git configuration tab: **Configure Git later**. Tag `project=shopstream`.

## 4. Give the factory's identity access (5 min)

1. **Lake:** storage account → Access control (IAM) → Add role assignment → **Storage Blob Data Contributor** → Members: Managed identity → Data factory → `adf-shopstream-cr` → Review + assign.
2. **SQL:** database → Query editor → sign in with **Microsoft Entra authentication** ("Continue as …") → run `sql/source/05_grant_adf_managed_identity.sql`.
   If Entra sign-in is refused: server `sql-shopstream-cr` → Microsoft Entra ID → Set admin → yourself → Save.

## 5. Connect ADF to GitHub (5 min)

Push today's repo changes first (GitHub Desktop). Then Data Factory → **Launch Studio** → Manage → **Git configuration** → Configure:

| Field | Value |
| --- | --- |
| Repository type | GitHub (authorize the Azure Data Factory app) |
| Repository owner / name | `Ch955` / `shopstream` |
| Collaboration branch | `main` |
| Publish branch | `adf_publish` |
| **Root folder** | `/ingestion/adf` |
| Import existing resources | Unticked |

ADF now shows the two datasets and the pipeline from the repo (with warnings until the linked services exist).

## 6. Linked services (5 min)

Manage → Linked services → New. **Names must match exactly** — the datasets reference them.

| Name | Type | Settings |
| --- | --- | --- |
| `ls_azuresql_shopstream` | Azure SQL Database | Server `sql-shopstream-cr`, database `sqldb-shopstream-oltp`, Authentication **System-assigned managed identity** |
| `ls_adls_shopstream` | Azure Data Lake Storage Gen2 | Authentication **System-assigned managed identity**, storage account `stshopstreamcr` |

**Test connection** on each (Successful = permissions are right), then Create. Saving commits JSON to GitHub.
If the SQL test times out once, the DB is resuming from pause — test again.

## 7. First run = full load (5 min)

Author → pipeline `pl_ingest_sql_to_bronze` → **Debug**. Watch Output: 9 iterations, each Lookup → Copy → SP_IngestSuccess.
Expected `rowsCopied` per table = Day 1 row counts (first run starts from 1900-01-01).

Check:
- Storage account → Storage browser → `bronze/olist/orders/load_date=…/orders_<runId>.parquet`
- SQL: `SELECT * FROM etl.ingest_control ORDER BY load_order;` (watermarks moved) and `SELECT * FROM etl.ingest_run_log ORDER BY log_id DESC;`

## 8. Prove it's incremental (5 min)

Run `sql/source/06_simulate_changes.sql` (SQL auth), then **Debug** again.
Expected: orders **50** rows, customers **10**, every other table **0**. Run log shows the second run with tiny counts.

## 9. Close out

- Leave the Query editor; in GitHub Desktop **Fetch/Pull** (ADF committed the linked services), commit anything local, push.
- Don't publish or add triggers yet — debug runs are enough, and no schedule means no surprise runs.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Linked service test: *Login failed for user '<token-identified principal>'* | Step 4.2 not run, or run with SQL auth instead of Entra |
| ADLS test: *403 / AuthorizationPermissionMismatch* | Role assignment missing or still propagating (wait 5 min) |
| *Cannot connect … client IP* in the Query editor | Allowlist IP again (home IP changed) |
| Copy error on `datetime2` in Parquet | Re-run; report the column here |
| Dataset shows "linked service not found" | Name typo — must be exactly `ls_azuresql_shopstream` / `ls_adls_shopstream` |

## Cost

ADF bills per activity run and per copy minute: a full 9-table run costs roughly ₹10–15 from the free credit; incremental runs less. Storage for ~60 MB of Parquet is a fraction of a rupee per month.
