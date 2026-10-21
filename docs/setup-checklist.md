# Setup checklist (summary)

Full version with links: the "ShopStream — Day 1: Architecture & Setup" doc.

| Account | Clock | Start |
| --- | --- | --- |
| GitHub | none | Day 1 |
| Kaggle (API token) | none | Day 1 |
| Azure free account | $200 / 30 days | Day 1 |
| Azure SQL DB free offer | none, renews monthly | Day 1 |
| Databricks Free Edition | none | Day 1 (dev sandbox) |
| Azure Databricks Premium trial | 14 days free DBUs (VMs still billed) | ~Day 5 |
| Fabric trial (via an Entra user in your Azure tenant) | 60 days | ~Day 18 |

Guardrails: ₹500 budget alert · one resource group · SQL "auto-pause until next month" · close SSMS sessions ·
ADF Copy only, triggers off · Databricks single node, 10-min auto-terminate, SCC/No-Public-IP off ·
never buy Fabric capacity · delete compute before upgrading to pay-as-you-go on ~day 28.
