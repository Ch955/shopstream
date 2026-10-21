"""Unit tests for the Olist loader's parsing (no database needed). Runs in CI."""
import importlib.util
import sys
from pathlib import Path

LOADER = Path(__file__).parents[1] / "scripts/load_olist_to_azuresql.py"
spec = importlib.util.spec_from_file_location("loader", LOADER)
loader = importlib.util.module_from_spec(spec)
sys.modules["loader"] = loader
spec.loader.exec_module(loader)


def _write(tmp: Path, name: str, text: str, bom: bool = False) -> None:
    (tmp / name).write_bytes(("﻿" if bom else "").encode() + text.encode("utf-8"))


def test_zip_prefix_keeps_leading_zeros(tmp_path):
    _write(tmp_path, "olist_customers_dataset.csv",
           "customer_id,customer_unique_id,customer_zip_code_prefix,customer_city,customer_state\n"
           + "a" * 32 + "," + "b" * 32 + ",1151,sao paulo,SP\n")
    df = loader.read_typed(loader.SPEC_BY_NAME["customers"], tmp_path)
    assert df.loc[0, "customer_zip_code_prefix"] == "01151"


def test_bom_header_and_typo_renames(tmp_path):
    _write(tmp_path, "product_category_name_translation.csv",
           "product_category_name,product_category_name_english\nbeleza_saude,health_beauty\n", bom=True)
    df = loader.read_typed(loader.SPEC_BY_NAME["product_category_translation"], tmp_path)
    assert list(df.columns) == ["product_category_name", "product_category_name_english"]

    _write(tmp_path, "olist_products_dataset.csv",
           "product_id,product_category_name,product_name_lenght,product_description_lenght,product_photos_qty,"
           "product_weight_g,product_length_cm,product_height_cm,product_width_cm\n"
           + "p" * 32 + ",,,,,225,16,10,14\n")
    df = loader.read_typed(loader.SPEC_BY_NAME["products"], tmp_path)
    assert "product_name_length" in df.columns
    row = loader.to_python_rows(df)[0]
    assert row[1] is None and row[2] is None and row[5] == 225 and isinstance(row[5], int)


def test_timestamps_nulls_and_multiline_text(tmp_path):
    _write(tmp_path, "olist_order_reviews_dataset.csv",
           "review_id,order_id,review_score,review_comment_title,review_comment_message,"
           "review_creation_date,review_answer_timestamp\n"
           + "r" * 32 + "," + "o" * 32 + ',5,,"linha um\nlinha dois",2018-01-18 00:00:00,2018-01-18 21:46:59\n')
    df = loader.read_typed(loader.SPEC_BY_NAME["order_reviews"], tmp_path)
    row = loader.to_python_rows(df)[0]
    assert row[3] is None
    assert "\n" in row[4]
    assert row[6].hour == 21 and row[2] == 5


def test_load_order_is_parents_first():
    names = [s.name for s in loader.SPECS]
    assert names.index("customers") < names.index("orders") < names.index("order_items")
    assert names.index("products") < names.index("order_items")
