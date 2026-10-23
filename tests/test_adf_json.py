"""Static checks on the ADF resources in ingestion/adf (runs in CI, no Azure needed)."""
import json
from pathlib import Path

ADF = Path(__file__).parents[1] / "ingestion" / "adf"


def _load(kind: str) -> dict[str, dict]:
    folder = ADF / kind
    return {p.stem: json.loads(p.read_text(encoding="utf-8")) for p in folder.glob("*.json")} if folder.exists() else {}


def _walk(obj, key):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key:
                yield v
            yield from _walk(v, key)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk(v, key)


def test_json_files_parse_and_names_match_filenames():
    for kind in ("dataset", "pipeline", "linkedService"):
        for stem, obj in _load(kind).items():
            assert obj["name"] == stem, f"{kind}/{stem}.json has name {obj['name']}"


def test_pipeline_references_existing_datasets():
    datasets = set(_load("dataset"))
    for pl in _load("pipeline").values():
        for ref in _walk(pl, "outputs"):
            for r in ref:
                assert r["referenceName"] in datasets
        for ref in _walk(pl, "dataset"):
            assert ref["referenceName"] in datasets


def test_failure_path_does_not_move_watermark():
    pl = _load("pipeline")["pl_ingest_sql_to_bronze"]
    inner = pl["properties"]["activities"][1]["typeProperties"]["activities"]
    by_name = {a["name"]: a for a in inner}
    assert by_name["SP_IngestSuccess"]["dependsOn"][0]["dependencyConditions"] == ["Succeeded"]
    assert by_name["SP_IngestFailure"]["dependsOn"][0]["dependencyConditions"] == ["Failed"]
    assert "new_watermark" not in by_name["SP_IngestFailure"]["typeProperties"]["storedProcedureParameters"]
    assert by_name["FAIL_Table"]["type"] == "Fail"
