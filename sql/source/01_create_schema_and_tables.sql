/* =====================================================================
   ShopStream | Source OLTP | Azure SQL Database (free offer)
   01 - schema + tables for the Olist Brazilian e-commerce dataset

   Design notes
   - Schema `olist` holds the 9 source tables, typed (not all-NVARCHAR).
   - Primary keys are created here; foreign keys are added AFTER the load
     (03_constraints.sql) so a bad row can't abort a 1M-row insert.
   - Every table gets `updated_at` (UTC). Day 2's ADF pipeline uses it as
     the incremental watermark; the order simulator bumps it on change.
   - Two Olist quirks handled:
       * order_reviews.review_id is NOT unique  -> PK (review_id, order_id)
       * geolocation has no key + duplicates    -> surrogate IDENTITY PK
   - Source typos "lenght" are fixed to "length" (mapping in the loader).
   Re-runnable: drops and recreates the tables.
   ===================================================================== */

IF SCHEMA_ID(N'olist') IS NULL
    EXEC (N'CREATE SCHEMA olist AUTHORIZATION dbo;');
GO

-- Drop in FK-safe order (children first)
DROP TABLE IF EXISTS olist.order_reviews;
DROP TABLE IF EXISTS olist.order_payments;
DROP TABLE IF EXISTS olist.order_items;
DROP TABLE IF EXISTS olist.orders;
DROP TABLE IF EXISTS olist.customers;
DROP TABLE IF EXISTS olist.products;
DROP TABLE IF EXISTS olist.sellers;
DROP TABLE IF EXISTS olist.product_category_translation;
DROP TABLE IF EXISTS olist.geolocation;
GO

CREATE TABLE olist.customers (
    customer_id               CHAR(32)      NOT NULL,
    customer_unique_id        CHAR(32)      NOT NULL,
    customer_zip_code_prefix  CHAR(5)       NOT NULL,
    customer_city             NVARCHAR(64)  NOT NULL,
    customer_state            CHAR(2)       NOT NULL,
    updated_at                DATETIME2(3)  NOT NULL CONSTRAINT df_customers_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_customers PRIMARY KEY (customer_id)
);

CREATE TABLE olist.sellers (
    seller_id                 CHAR(32)      NOT NULL,
    seller_zip_code_prefix    CHAR(5)       NOT NULL,
    seller_city               NVARCHAR(64)  NOT NULL,
    seller_state              CHAR(2)       NOT NULL,
    updated_at                DATETIME2(3)  NOT NULL CONSTRAINT df_sellers_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_sellers PRIMARY KEY (seller_id)
);

CREATE TABLE olist.product_category_translation (
    product_category_name          NVARCHAR(64) NOT NULL,
    product_category_name_english  NVARCHAR(64) NOT NULL,
    updated_at                     DATETIME2(3) NOT NULL CONSTRAINT df_pct_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_product_category_translation PRIMARY KEY (product_category_name)
);

CREATE TABLE olist.products (
    product_id                  CHAR(32)      NOT NULL,
    product_category_name       NVARCHAR(64)  NULL,   -- 2 categories have no English translation: no FK
    product_name_length         SMALLINT      NULL,   -- source: product_name_lenght
    product_description_length  SMALLINT      NULL,   -- source: product_description_lenght
    product_photos_qty          SMALLINT      NULL,
    product_weight_g            INT           NULL,
    product_length_cm           SMALLINT      NULL,
    product_height_cm           SMALLINT      NULL,
    product_width_cm            SMALLINT      NULL,
    updated_at                  DATETIME2(3)  NOT NULL CONSTRAINT df_products_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_products PRIMARY KEY (product_id)
);

CREATE TABLE olist.orders (
    order_id                       CHAR(32)      NOT NULL,
    customer_id                    CHAR(32)      NOT NULL,
    order_status                   VARCHAR(16)   NOT NULL,
    order_purchase_timestamp       DATETIME2(0)  NOT NULL,
    order_approved_at              DATETIME2(0)  NULL,
    order_delivered_carrier_date   DATETIME2(0)  NULL,
    order_delivered_customer_date  DATETIME2(0)  NULL,
    order_estimated_delivery_date  DATETIME2(0)  NOT NULL,
    updated_at                     DATETIME2(3)  NOT NULL CONSTRAINT df_orders_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_orders PRIMARY KEY (order_id)
);

CREATE TABLE olist.order_items (
    order_id             CHAR(32)       NOT NULL,
    order_item_id        SMALLINT       NOT NULL,
    product_id           CHAR(32)       NOT NULL,
    seller_id            CHAR(32)       NOT NULL,
    shipping_limit_date  DATETIME2(0)   NOT NULL,
    price                DECIMAL(10,2)  NOT NULL,
    freight_value        DECIMAL(10,2)  NOT NULL,
    updated_at           DATETIME2(3)   NOT NULL CONSTRAINT df_order_items_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE olist.order_payments (
    order_id              CHAR(32)       NOT NULL,
    payment_sequential    SMALLINT       NOT NULL,
    payment_type          VARCHAR(16)    NOT NULL,
    payment_installments  SMALLINT       NOT NULL,
    payment_value         DECIMAL(10,2)  NOT NULL,
    updated_at            DATETIME2(3)   NOT NULL CONSTRAINT df_order_payments_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_order_payments PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE olist.order_reviews (
    review_id                CHAR(32)       NOT NULL,
    order_id                 CHAR(32)       NOT NULL,
    review_score             TINYINT        NOT NULL,
    review_comment_title     NVARCHAR(100)  NULL,
    review_comment_message   NVARCHAR(1000) NULL,  -- longest in source is ~210 chars; avoids the (max) slow path
    review_creation_date     DATETIME2(0)   NOT NULL,
    review_answer_timestamp  DATETIME2(0)   NOT NULL,
    updated_at               DATETIME2(3)   NOT NULL CONSTRAINT df_order_reviews_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_order_reviews PRIMARY KEY (review_id, order_id)
);

CREATE TABLE olist.geolocation (
    geolocation_sk               INT IDENTITY(1,1) NOT NULL,
    geolocation_zip_code_prefix  CHAR(5)       NOT NULL,
    geolocation_lat              FLOAT         NOT NULL,
    geolocation_lng              FLOAT         NOT NULL,
    geolocation_city             NVARCHAR(100) NOT NULL,
    geolocation_state            CHAR(2)       NOT NULL,
    updated_at                   DATETIME2(3)  NOT NULL CONSTRAINT df_geolocation_updated_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_geolocation PRIMARY KEY (geolocation_sk)
);
GO

-- Ingestion/watermark log used by the loader (and later by ADF)
IF OBJECT_ID(N'dbo.load_audit') IS NULL
CREATE TABLE dbo.load_audit (
    load_id      INT IDENTITY(1,1) PRIMARY KEY,
    table_name   SYSNAME       NOT NULL,
    source_file  NVARCHAR(260) NOT NULL,
    rows_in_file INT           NOT NULL,
    rows_loaded  INT           NOT NULL,
    started_at   DATETIME2(3)  NOT NULL,
    finished_at  DATETIME2(3)  NOT NULL,
    status       VARCHAR(16)   NOT NULL
);
GO
