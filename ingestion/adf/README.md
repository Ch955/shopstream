# Azure Data Factory (Day 2)

ADF Studio → Manage → Git configuration → this repo, collaboration branch `main`, root folder `/ingestion/adf`.
ADF then writes pipeline, dataset and linked-service JSON here on every save.

Planned: `pl_ingest_sql_to_bronze` — Lookup over a control table (`dbo.ingest_control`: table, watermark column,
last watermark) → ForEach → Copy (query `WHERE updated_at > @last`) → Parquet in `bronze/olist/<table>/load_date=...`
→ Stored procedure updates the watermark and writes to `dbo.load_audit`.
