/* =====================================================================
   03 - validation. Every row should say PASS.
   Expected counts are the published Kaggle row counts (v2 of the dataset).
   ===================================================================== */

WITH expected AS (
    SELECT * FROM (VALUES
        ('customers',                      99441),
        ('geolocation',                  1000163),
        ('order_items',                   112650),
        ('order_payments',                103886),
        ('order_reviews',                  99224),
        ('orders',                         99441),
        ('products',                       32951),
        ('sellers',                         3095),
        ('product_category_translation',      71)
    ) v(table_name, expected_rows)
),
actual AS (
    SELECT t.name AS table_name, SUM(p.rows) AS actual_rows
    FROM sys.tables t
    JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
    WHERE t.schema_id = SCHEMA_ID('olist')
    GROUP BY t.name
)
SELECT e.table_name, e.expected_rows, a.actual_rows,
       CASE WHEN a.actual_rows = e.expected_rows THEN 'PASS' ELSE 'FAIL' END AS result
FROM expected e
LEFT JOIN actual a ON a.table_name = e.table_name
ORDER BY e.table_name;

-- Business sanity checks
SELECT 'orders date range' AS check_name,
       CONVERT(varchar(10), MIN(order_purchase_timestamp), 120) + ' .. ' +
       CONVERT(varchar(10), MAX(order_purchase_timestamp), 120) AS value
FROM olist.orders
UNION ALL
SELECT 'order statuses', STRING_AGG(order_status, ', ') WITHIN GROUP (ORDER BY order_status)
FROM (SELECT DISTINCT order_status FROM olist.orders) s
UNION ALL
SELECT 'orders without items', CAST(COUNT(*) AS varchar(20))
FROM olist.orders o WHERE NOT EXISTS (SELECT 1 FROM olist.order_items i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'zip prefixes kept leading zeros', CAST(COUNT(*) AS varchar(20))
FROM olist.customers WHERE customer_zip_code_prefix LIKE '0%'
UNION ALL
SELECT 'GMV (price + freight, BRL)', FORMAT(SUM(price + freight_value), 'N2')
FROM olist.order_items;

SELECT TOP (20) * FROM dbo.load_audit ORDER BY load_id DESC;
