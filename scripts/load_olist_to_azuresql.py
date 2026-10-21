"""Load the Olist Brazilian e-commerce CSVs into Azure SQL Database (schema `olist`).

Usage
-----
    python scripts/load_olist_to_azuresql.py                 # load all 9 tables
    python scripts/load_olist_to_azuresql.py --dry-run       # parse + validate CSVs only, no DB
    python scripts/load_olist_to_azuresql.py --tables orders order_items

Prereqs: run sql/source/01_create_schema_and_tables.sql first; fill .env (see .env.example).
After loading, run 02_constraints_and_indexes.sql, then 03_validate_load.sql.

Why a script instead of the SSMS import wizard: it is repeatable, typed, idempotent
(truncate + reload), logs to dbo.load_audit, and survives the serverless DB waking
up from auto-pause (error 40613) with retries.
"""
from __future__ import annotations

import argparse
import logging
import math
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

log = logging.getLogger("olist_loader")

# --------------------------------------------------------------------------------------
# Table specs: source file -> target table, column renames, types. Load order = list order
# (parents before children, so 02_constraints_and_indexes.sql validates cleanly).
# --------------------------------------------------------------------------------------
STR, INT, FLOAT, DEC, TS = "str", "int", "float", "dec", "ts"


@dataclass(frozen=True)
class TableSpec:
    name: str
    file: str
    columns: dict[str, str]                      # target column -> type
    renames: dict[str, str] = field(default_factory=dict)  # source column -> target column
    expected_rows: int | None = None
    zero_pad: tuple[str, ...] = ()               # zip prefixes: restore leading zeros


SPECS: list[TableSpec] = [
    TableSpec("product_category_translation", "product_category_name_translation.csv",
              {"product_category_name": STR, "product_category_name_english": STR}, expected_rows=71),
    TableSpec("customers", "olist_customers_dataset.csv",
              {"customer_id": STR, "customer_unique_id": STR, "customer_zip_code_prefix": STR,
               "customer_city": STR, "customer_state": STR},
              expected_rows=99_441, zero_pad=("customer_zip_code_prefix",)),
    TableSpec("sellers", "olist_sellers_dataset.csv",
              {"seller_id": STR, "seller_zip_code_prefix": STR, "seller_city": STR, "seller_state": STR},
              expected_rows=3_095, zero_pad=("seller_zip_code_prefix",)),
    TableSpec("products", "olist_products_dataset.csv",
              {"product_id": STR, "product_category_name": STR, "product_name_length": INT,
               "product_description_length": INT, "product_photos_qty": INT, "product_weight_g": INT,
               "product_length_cm": INT, "product_height_cm": INT, "product_width_cm": INT},
              renames={"product_name_lenght": "product_name_length",
                       "product_description_lenght": "product_description_length"},
              expected_rows=32_951),
    TableSpec("orders", "olist_orders_dataset.csv",
              {"order_id": STR, "customer_id": STR, "order_status": STR, "order_purchase_timestamp": TS,
               "order_approved_at": TS, "order_delivered_carrier_date": TS,
               "order_delivered_customer_date": TS, "order_estimated_delivery_date": TS},
              expected_rows=99_441),
    TableSpec("order_items", "olist_order_items_dataset.csv",
              {"order_id": STR, "order_item_id": INT, "product_id": STR, "seller_id": STR,
               "shipping_limit_date": TS, "price": DEC, "freight_value": DEC},
              expected_rows=112_650),
    TableSpec("order_payments", "olist_order_payments_dataset.csv",
              {"order_id": STR, "payment_sequential": INT, "payment_type": STR,
               "payment_installments": INT, "payment_value": DEC},
              expected_rows=103_886),
    TableSpec("order_reviews", "olist_order_reviews_dataset.csv",
              {"review_id": STR, "order_id": STR, "review_score": INT, "review_comment_title": STR,
               "review_comment_message": STR, "review_creation_date": TS, "review_answer_timestamp": TS},
              expected_rows=99_224),
    TableSpec("geolocation", "olist_geolocation_dataset.csv",
              {"geolocation_zip_code_prefix": STR, "geolocation_lat": FLOAT, "geolocation_lng": FLOAT,
               "geolocation_city": STR, "geolocation_state": STR},
              expected_rows=1_000_163, zero_pad=("geolocation_zip_code_prefix",)),
]
SPEC_BY_NAME = {s.name: s for s in SPECS}


# --------------------------------------------------------------------------------------
# Read + type a CSV
# --------------------------------------------------------------------------------------
def read_typed(spec: TableSpec, data_dir: Path) -> pd.DataFrame:
    path = data_dir / spec.file
    if not path.exists():
        raise FileNotFoundError(f"{path} not found. Run scripts/download_olist.py first.")

    # dtype=str keeps zip prefixes as text; utf-8-sig strips the BOM in the translation file
    df = pd.read_csv(path, dtype=str, encoding="utf-8-sig", keep_default_na=False, na_values=[""])
    df = df.rename(columns=spec.renames)

    missing = set(spec.columns) - set(df.columns)
    if missing:
        raise ValueError(f"{spec.file}: missing columns {sorted(missing)}; found {list(df.columns)}")
    df = df[list(spec.columns)]

    for col in spec.zero_pad:
        df[col] = df[col].str.zfill(5)

    for col, typ in spec.columns.items():
        if typ == INT:
            df[col] = pd.to_numeric(df[col], errors="raise").astype("Int64")
        elif typ in (FLOAT, DEC):
            df[col] = pd.to_numeric(df[col], errors="raise").astype("float64")
        elif typ == TS:
            df[col] = pd.to_datetime(df[col], format="%Y-%m-%d %H:%M:%S", errors="raise")
        else:
            df[col] = df[col].str.strip()

    if spec.expected_rows is not None and len(df) != spec.expected_rows:
        log.warning("%s: %s rows in file, expected %s", spec.file, f"{len(df):,}", f"{spec.expected_rows:,}")
    return df


def to_python_rows(df: pd.DataFrame) -> list[tuple]:
    """DataFrame -> list of tuples with None for nulls and native Python types (what pyodbc wants)."""
    out: list[tuple] = []
    cols = [df[c] for c in df.columns]
    for row in zip(*cols, strict=True):
        clean = []
        for v in row:
            if v is None or v is pd.NA or v is pd.NaT or (isinstance(v, float) and math.isnan(v)):
                clean.append(None)
            elif isinstance(v, pd.Timestamp):
                clean.append(v.to_pydatetime())
            elif hasattr(v, "item"):          # numpy / pandas scalar -> Python scalar
                clean.append(v.item())
            else:
                clean.append(v)
        out.append(tuple(clean))
    return out


# --------------------------------------------------------------------------------------
# Database
# --------------------------------------------------------------------------------------
def connect(retries: int = 6):
    import pyodbc  # imported lazily so --dry-run works without the ODBC driver

    server = os.environ["AZURE_SQL_SERVER"]          # e.g. sql-shopstream-ce.database.windows.net
    database = os.environ["AZURE_SQL_DATABASE"]      # e.g. sqldb-shopstream-oltp
    driver = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")
    auth = os.getenv("AZURE_SQL_AUTH", "sql").lower()

    conn_str = (f"Driver={{{driver}}};Server=tcp:{server},1433;Database={database};"
                "Encrypt=yes;TrustServerCertificate=no;Connection Timeout=60;")
    if auth == "sql":
        conn_str += f"Uid={os.environ['AZURE_SQL_USER']};Pwd={os.environ['AZURE_SQL_PASSWORD']};"
    elif auth == "entra-interactive":                # browser sign-in with your Entra account
        conn_str += f"Authentication=ActiveDirectoryInteractive;Uid={os.environ['AZURE_SQL_USER']};"
    else:
        raise ValueError("AZURE_SQL_AUTH must be 'sql' or 'entra-interactive'")

    # A serverless DB that auto-paused takes ~1 minute to resume; first attempts fail with 40613.
    for attempt in range(1, retries + 1):
        try:
            conn = pyodbc.connect(conn_str, autocommit=False)
            log.info("Connected to %s/%s", server, database)
            return conn
        except pyodbc.Error as exc:
            if attempt == retries:
                raise
            wait = min(10 * attempt, 45)
            log.warning("Connect attempt %d failed (%s). DB may be resuming; retrying in %ss",
                        attempt, str(exc).split("\n")[0][:160], wait)
            time.sleep(wait)


def load_table(conn, spec: TableSpec, df: pd.DataFrame, batch_size: int) -> int:
    cur = conn.cursor()
    cur.fast_executemany = True
    target = f"olist.{spec.name}"
    cols = list(spec.columns)
    insert_sql = f"INSERT INTO {target} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})"

    # Idempotent: clear then reload. DELETE (not TRUNCATE) works even once FKs exist.
    cur.execute(f"DELETE FROM {target};")
    if spec.name == "geolocation":
        cur.execute("DBCC CHECKIDENT ('olist.geolocation', RESEED, 0);")

    loaded = 0
    for start in range(0, len(df), batch_size):
        chunk = to_python_rows(df.iloc[start:start + batch_size])
        cur.executemany(insert_sql, chunk)
        loaded += len(chunk)
        log.info("  %-30s %9s / %s", target, f"{loaded:,}", f"{len(df):,}")
    conn.commit()
    return loaded


def write_audit(conn, spec: TableSpec, rows_in: int, rows_loaded: int, started: datetime, status: str) -> None:
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO dbo.load_audit"
        " (table_name, source_file, rows_in_file, rows_loaded, started_at, finished_at, status)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        f"olist.{spec.name}", spec.file, rows_in, rows_loaded, started,
        datetime.now(timezone.utc).replace(tzinfo=None), status,
    )
    conn.commit()


# --------------------------------------------------------------------------------------
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data-dir", default="data/raw", type=Path)
    ap.add_argument("--tables", nargs="*", choices=list(SPEC_BY_NAME), help="subset to load (default: all)")
    ap.add_argument("--batch-size", type=int, default=20_000)
    ap.add_argument("--dry-run", action="store_true", help="parse and validate CSVs only; no database")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-7s %(message)s", datefmt="%H:%M:%S")
    try:
        from dotenv import load_dotenv
        load_dotenv()
    except ImportError:
        pass

    specs = [SPEC_BY_NAME[t] for t in args.tables] if args.tables else SPECS
    specs = sorted(specs, key=SPECS.index)  # always parents first

    conn = None if args.dry_run else connect()
    failures = 0
    t0 = time.time()
    for spec in specs:
        started = datetime.now(timezone.utc).replace(tzinfo=None)
        try:
            df = read_typed(spec, args.data_dir)
            if args.dry_run:
                log.info("OK  %-30s %9s rows  nulls=%s", spec.name, f"{len(df):,}",
                         {c: int(n) for c, n in df.isna().sum().items() if n})
                continue
            log.info("Loading olist.%s (%s rows)", spec.name, f"{len(df):,}")
            n = load_table(conn, spec, df, args.batch_size)
            write_audit(conn, spec, len(df), n, started, "SUCCEEDED")
        except Exception as exc:  # noqa: BLE001 - keep going; report at the end
            failures += 1
            log.error("FAILED %s: %s", spec.name, exc)
            if conn is not None:
                conn.rollback()
                try:
                    write_audit(conn, spec, 0, 0, started, "FAILED")
                except Exception as audit_exc:  # noqa: BLE001 - audit is best-effort
                    log.warning("Could not write FAILED audit row: %s", audit_exc)

    if conn is not None:
        conn.close()  # close promptly so the serverless DB can auto-pause
    log.info("Done in %.0fs with %d failure(s)", time.time() - t0, failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
