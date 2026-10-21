/* =====================================================================
   02 - foreign keys + indexes. Run AFTER scripts/load_olist_to_azuresql.py
   WITH CHECK validates every existing row: if this fails, a load is
   incomplete or out of order. Re-run the loader, then this script.
   ===================================================================== */

ALTER TABLE olist.orders         WITH CHECK ADD CONSTRAINT fk_orders_customers       FOREIGN KEY (customer_id) REFERENCES olist.customers (customer_id);
ALTER TABLE olist.order_items    WITH CHECK ADD CONSTRAINT fk_order_items_orders     FOREIGN KEY (order_id)    REFERENCES olist.orders (order_id);
ALTER TABLE olist.order_items    WITH CHECK ADD CONSTRAINT fk_order_items_products   FOREIGN KEY (product_id)  REFERENCES olist.products (product_id);
ALTER TABLE olist.order_items    WITH CHECK ADD CONSTRAINT fk_order_items_sellers    FOREIGN KEY (seller_id)   REFERENCES olist.sellers (seller_id);
ALTER TABLE olist.order_payments WITH CHECK ADD CONSTRAINT fk_order_payments_orders  FOREIGN KEY (order_id)    REFERENCES olist.orders (order_id);
ALTER TABLE olist.order_reviews  WITH CHECK ADD CONSTRAINT fk_order_reviews_orders   FOREIGN KEY (order_id)    REFERENCES olist.orders (order_id);
GO

-- Watermark indexes for incremental extraction (Day 2: ADF)
CREATE INDEX ix_orders_updated_at         ON olist.orders (updated_at);
CREATE INDEX ix_order_items_updated_at    ON olist.order_items (updated_at);
CREATE INDEX ix_order_payments_updated_at ON olist.order_payments (updated_at);
CREATE INDEX ix_order_reviews_updated_at  ON olist.order_reviews (updated_at);
CREATE INDEX ix_customers_updated_at      ON olist.customers (updated_at);

-- Common join / filter paths
CREATE INDEX ix_orders_customer_id        ON olist.orders (customer_id);
CREATE INDEX ix_orders_purchase_ts        ON olist.orders (order_purchase_timestamp) INCLUDE (order_status);
CREATE INDEX ix_order_items_product_id    ON olist.order_items (product_id);
CREATE INDEX ix_order_items_seller_id     ON olist.order_items (seller_id);
CREATE INDEX ix_geolocation_zip           ON olist.geolocation (geolocation_zip_code_prefix);
GO
