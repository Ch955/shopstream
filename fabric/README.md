# Microsoft Fabric (activate the trial ~day 18)

- Workspace `ws-shopstream` on the trial capacity
- Lakehouse `lh_shopstream` with a OneLake shortcut to ADLS `gold/` (no data copy)
- Eventstream `es_orders` → Eventhouse `eh_shopstream` (KQL) for live order events
- Semantic model (Direct Lake) + Power BI reports: executive KPIs, delivery performance, live orders
- Workspace Git integration → this folder
