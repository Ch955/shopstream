# Order simulator (Day 3)

Python process that makes the source behave like a live shop:
- inserts new orders/items/payments into Azure SQL (sampled from historical patterns, shifted to today)
- moves existing orders through statuses (approved → shipped → delivered), bumping `updated_at`
- emits each change as a JSON event to Fabric Eventstream (custom endpoint)

Runs on demand in short bursts to stay inside the SQL free vCore-seconds.
