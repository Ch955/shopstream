# Databricks

- `src/shopstream/` — PySpark transforms as plain functions (unit-testable with local Spark)
- `notebooks/` — thin notebooks that call `src/` (bronze_to_silver, silver_to_gold)
- `tests/` — pytest for transforms
- `databricks.yml` (added later) — Databricks Asset Bundle for deploys from GitHub Actions

Cluster: single node, auto-terminate 10 min. Unity Catalog: catalog `shopstream`, schemas `bronze`, `silver`, `gold`.
