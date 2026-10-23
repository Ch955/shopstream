/* =====================================================================
   ShopStream | Day 2 | Prove the pipeline is incremental
   06 - change a few rows, re-run the pipeline, and only these rows
        should land in Bronze. (Day 3's simulator automates this.)
   ===================================================================== */

-- 50 shipped orders get delivered today
UPDATE TOP (50) olist.orders
   SET order_status                  = 'delivered',
       order_delivered_customer_date = SYSUTCDATETIME(),
       updated_at                    = SYSUTCDATETIME()
 WHERE order_status = 'shipped';

-- 10 customers move city
UPDATE TOP (10) olist.customers
   SET customer_city = N'sao paulo',
       updated_at    = SYSUTCDATETIME()
 WHERE customer_state = 'RJ';

-- Expect: orders 50 rows, customers 10 rows, every other table 0 rows
SELECT schema_name, table_name, last_watermark FROM etl.ingest_control ORDER BY load_order;
