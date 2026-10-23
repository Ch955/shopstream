-- ShopStream | Day 2 | Ingestion control framework (Azure SQL)
-- Creates schema etl: control table, run log, two logging procedures.
-- The ADF pipeline reads etl.ingest_control, copies rows where
-- last_watermark < updated_at <= MAX(updated_at), then calls
-- etl.usp_ingest_success (moves watermark + logs) or
-- etl.usp_ingest_failure (logs only; watermark stays put).
-- Written for the portal Query editor: no batch separators, procedures
-- are created through EXEC(). Safe to re-run.

IF SCHEMA_ID(N'etl') IS NULL
    EXEC (N'CREATE SCHEMA etl AUTHORIZATION dbo;');

DROP TABLE IF EXISTS etl.ingest_run_log;
DROP TABLE IF EXISTS etl.ingest_control;

CREATE TABLE etl.ingest_control (
    control_id            INT IDENTITY(1,1) NOT NULL CONSTRAINT pk_ingest_control PRIMARY KEY,
    schema_name           SYSNAME       NOT NULL,
    table_name            SYSNAME       NOT NULL,
    watermark_column      SYSNAME       NOT NULL,
    last_watermark        DATETIME2(3)  NOT NULL CONSTRAINT df_ic_last_wm DEFAULT ('1900-01-01'),
    is_active             BIT           NOT NULL CONSTRAINT df_ic_active  DEFAULT (1),
    load_order            INT           NOT NULL,
    last_run_at           DATETIME2(3)  NULL,
    last_rows_copied      BIGINT        NULL,
    last_pipeline_run_id  VARCHAR(64)   NULL,
    CONSTRAINT uq_ingest_control UNIQUE (schema_name, table_name)
);

CREATE TABLE etl.ingest_run_log (
    log_id           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_ingest_run_log PRIMARY KEY,
    pipeline_run_id  VARCHAR(64)    NOT NULL,
    schema_name      SYSNAME        NOT NULL,
    table_name       SYSNAME        NOT NULL,
    old_watermark    DATETIME2(3)   NULL,
    new_watermark    DATETIME2(3)   NULL,
    rows_copied      BIGINT         NULL,
    bronze_path      NVARCHAR(400)  NULL,
    status           VARCHAR(16)    NOT NULL,   -- SUCCEEDED | FAILED
    error_message    NVARCHAR(4000) NULL,
    logged_at        DATETIME2(3)   NOT NULL CONSTRAINT df_irl_logged DEFAULT (SYSUTCDATETIME())
);

-- Seed: every source table, watermark on updated_at, small tables first
INSERT INTO etl.ingest_control (schema_name, table_name, watermark_column, load_order) VALUES
    ('olist', 'product_category_translation', 'updated_at', 1),
    ('olist', 'sellers',                      'updated_at', 2),
    ('olist', 'products',                     'updated_at', 3),
    ('olist', 'customers',                    'updated_at', 4),
    ('olist', 'orders',                       'updated_at', 5),
    ('olist', 'order_items',                  'updated_at', 6),
    ('olist', 'order_payments',               'updated_at', 7),
    ('olist', 'order_reviews',                'updated_at', 8),
    ('olist', 'geolocation',                  'updated_at', 9);

EXEC (N'
CREATE OR ALTER PROCEDURE etl.usp_ingest_success
    @schema_name      SYSNAME,
    @table_name       SYSNAME,
    @old_watermark    VARCHAR(30),
    @new_watermark    VARCHAR(30),
    @rows_copied      BIGINT,
    @bronze_path      NVARCHAR(400),
    @pipeline_run_id  VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRAN;
        UPDATE etl.ingest_control
           SET last_watermark       = CONVERT(DATETIME2(3), @new_watermark, 121),
               last_run_at          = SYSUTCDATETIME(),
               last_rows_copied     = @rows_copied,
               last_pipeline_run_id = @pipeline_run_id
         WHERE schema_name = @schema_name AND table_name = @table_name;

        INSERT INTO etl.ingest_run_log
            (pipeline_run_id, schema_name, table_name, old_watermark, new_watermark, rows_copied, bronze_path, status)
        VALUES
            (@pipeline_run_id, @schema_name, @table_name,
             CONVERT(DATETIME2(3), @old_watermark, 121), CONVERT(DATETIME2(3), @new_watermark, 121),
             @rows_copied, @bronze_path, ''SUCCEEDED'');
    COMMIT;
END;
');

EXEC (N'
CREATE OR ALTER PROCEDURE etl.usp_ingest_failure
    @schema_name      SYSNAME,
    @table_name       SYSNAME,
    @old_watermark    VARCHAR(30),
    @pipeline_run_id  VARCHAR(64),
    @error_message    NVARCHAR(4000)
AS
BEGIN
    SET NOCOUNT ON;
    -- Watermark deliberately NOT moved: the next run retries the same window.
    INSERT INTO etl.ingest_run_log
        (pipeline_run_id, schema_name, table_name, old_watermark, status, error_message)
    VALUES
        (@pipeline_run_id, @schema_name, @table_name,
         CONVERT(DATETIME2(3), @old_watermark, 121), ''FAILED'', LEFT(@error_message, 4000));
END;
');

SELECT * FROM etl.ingest_control ORDER BY load_order;
