"""Download the Olist dataset from Kaggle into data/raw/ (gitignored).

Auth (kaggle>=2.x uses API tokens, not kaggle.json). Pick one:
  - Browser sign-in:  kaggle auth login
  - Token file:       save the token string from kaggle.com/settings/api to ~/.kaggle/access_token
                      (Windows: %USERPROFILE%\\.kaggle\\access_token), no newline
  - Env var:          KAGGLE_API_TOKEN=<token>
Fallback: download the zip from the dataset page and extract the 9 CSVs into data/raw/.
Equivalent CLI:  kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
"""
from pathlib import Path

DATASET = "olistbr/brazilian-ecommerce"
EXPECTED = [
    "olist_customers_dataset.csv", "olist_geolocation_dataset.csv", "olist_order_items_dataset.csv",
    "olist_order_payments_dataset.csv", "olist_order_reviews_dataset.csv", "olist_orders_dataset.csv",
    "olist_products_dataset.csv", "olist_sellers_dataset.csv", "product_category_name_translation.csv",
]


def main(dest: str = "data/raw") -> None:
    from kaggle.api.kaggle_api_extended import KaggleApi

    out = Path(dest)
    out.mkdir(parents=True, exist_ok=True)
    api = KaggleApi()
    api.authenticate()
    api.dataset_download_files(DATASET, path=str(out), unzip=True, quiet=False)

    missing = [f for f in EXPECTED if not (out / f).exists()]
    if missing:
        raise SystemExit(f"Download finished but these files are missing: {missing}")
    for f in EXPECTED:
        print(f"{(out / f).stat().st_size / 1_048_576:7.1f} MB  {f}")


if __name__ == "__main__":
    main()
