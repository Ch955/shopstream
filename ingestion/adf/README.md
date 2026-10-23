# Azure Data Factory (Git-integrated)

ADF Studio → Manage → Git configuration: GitHub `Ch955/shopstream`, collaboration branch `main`,
publish branch `adf_publish`, root folder `/ingestion/adf`. ADF reads and writes the JSON in this folder.

| Resource | Purpose |
| --- | --- |
| `linkedService/ls_azuresql_shopstream` | Azure SQL, system-assigned managed identity (created in Studio) |
| `linkedService/ls_adls_shopstream` | ADLS Gen2, system-assigned managed identity (created in Studio) |
| `dataset/ds_azuresql_query` | Generic SQL dataset; activities supply the query |
| `dataset/ds_adls_parquet` | Parameterised Parquet location (container / folder / file) |
| `pipeline/pl_ingest_sql_to_bronze` | Metadata-driven incremental copy to Bronze |

Pipeline flow: `LKP_ActiveTables` (etl.ingest_control) → `FE_Tables` (4 parallel) →
`LKP_NewWatermark` → `CP_SqlToBronze` → `SP_IngestSuccess` | (`SP_IngestFailure` → `FAIL_Table`).

Walkthrough: [docs/02-adf-incremental-to-bronze.md](../../docs/02-adf-incremental-to-bronze.md).
