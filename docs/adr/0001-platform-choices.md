# ADR 0001 — Platform choices and free-tier strategy

Date: 2026-10-21 · Status: accepted

## Decision
- **Source:** Azure SQL Database free offer (lifetime, 100k vCore-s + 32 GB per DB per month, auto-pause at limit).
- **Batch ingestion:** Azure Data Factory, Copy activity only (no Mapping Data Flows), on-demand runs.
- **Transform:** Azure Databricks, Premium 14-day trial workspace, single-node cluster, Unity Catalog over ADLS Gen2.
  Databricks Free Edition is used only as a dev sandbox: its outbound access is limited to trusted domains, so it
  can't read our ADLS account.
- **Serving + streaming:** Microsoft Fabric trial (60 days) — OneLake shortcut to Gold, Eventstream/Eventhouse, Power BI Direct Lake.

## Why
Shows the Azure-native stack most DE job descriptions in India ask for (ADF + Databricks + ADLS), plus Fabric,
at zero out-of-pocket cost, by sequencing the trials so their clocks don't overlap wastefully.

## Consequences
- The Databricks phase must finish inside the $200 / 30-day credit window.
- Fabric items go inactive 60 days after activation; the demo video and screenshots must be captured before then.
- After the Azure free account is upgraded to pay-as-you-go (~day 28) only the free SQL DB stays running.
