from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def read_csv(name: str) -> list[dict[str, str]]:
    with (ROOT / name).open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    spec = read_csv("model/FULL_MODEL_FEATURE_SPECIFICATION.csv")
    loadings = read_csv("model/FULL_MODEL_PCA_LOADINGS.csv")
    centroids = read_csv("model/FULL_MODEL_CLUSTER_CENTROIDS.csv")

    require(len(spec) == 20, "Frozen specification must contain exactly 20 features.")
    require([int(row["Order"]) for row in spec] == list(range(1, 21)), "Feature order is not 1-20.")
    require({row["PC"] for row in loadings} == {f"PC{i}" for i in range(1, 6)}, "PCA file must contain PC1-PC5.")
    require(len(loadings) == 100, "PCA loadings must contain 20 x 5 rows.")
    require(len(centroids) == 3 and all(len(row) == 6 for row in centroids), "Centroid file must contain 3 clusters and 5 PC coordinates.")
    require([int(row["Cluster"]) for row in centroids] == [1, 2, 3], "Centroids must be ordered as clusters 1, 2, and 3.")

    for filename in (
        "FULL_MODEL_FEATURE_SPECIFICATION.csv",
        "FULL_MODEL_PCA_LOADINGS.csv",
        "FULL_MODEL_CLUSTER_CENTROIDS.csv",
    ):
        require(
            sha256(ROOT / "model" / filename) == sha256(ROOT / "app" / "model" / filename),
            f"App model differs from frozen model: {filename}",
        )

    denominators = read_csv("results/FINAL_MODEL_DENOMINATORS.csv")
    expected_counts = {
        "MOVER": (21164, 1775, 15767, 3622, 13724),
        "INSPIRE": (85064, 6814, 62418, 15832, 83437),
    }
    for center, (total, low, stable, high, adjusted_n) in expected_counts.items():
        unadjusted = next(row for row in denominators if row["Center"] == center and row["Outcome"] == "Major adverse cardiac events" and row["Model"] == "Unadjusted")
        primary = next(row for row in denominators if row["Center"] == center and row["Outcome"] == "Major adverse cardiac events" and row["Model"] == "Preoperatively adjusted (primary)")
        require(int(unadjusted["Analysis_N"]) == total, f"Unexpected {center} cohort N.")
        require(int(unadjusted["Labile_Hypotension_N"]) == low, f"Unexpected {center} low phenotype N.")
        require(int(unadjusted["Stable_Hemodynamics_N"]) == stable, f"Unexpected {center} stable phenotype N.")
        require(int(unadjusted["Labile_Hypertension_N"]) == high, f"Unexpected {center} high phenotype N.")
        require(int(primary["Analysis_N"]) == adjusted_n, f"Unexpected {center} adjusted N.")

    table2 = read_csv("results/TABLE_2_PRIMARY_PREOPERATIVE_ADJUSTED_OR.csv")
    for center, events in {"MOVER": 415, "INSPIRE": 980}.items():
        rows = [row for row in table2 if row["Center"] == center and row["Outcome"] == "Major adverse cardiac events"]
        require(len(rows) == 2, f"Expected 2 MACE comparisons for {center}.")
        require({int(row["Events_Unadjusted"]) for row in rows} == {events}, f"Unexpected {center} MACE event count.")

    recognition = read_csv("results/FOLD_SAFE_RECOGNITION_PERFORMANCE.csv")
    expected_auc = {
        ("MOVER 10-fold cross-validation", "Preoperative model"): 0.6607646927,
        ("INSPIRE frozen external validation", "Preoperative model"): 0.5868005911,
        ("MOVER 10-fold cross-validation", "Preoperative + first 30 min MAP"): 0.8672319857,
        ("INSPIRE frozen external validation", "Preoperative + first 30 min MAP"): 0.8345047634,
    }
    for key, expected in expected_auc.items():
        row = [item for item in recognition if item["Center"] == key[0] and item["Scenario"] == key[1]]
        require(len(row) == 1, f"Missing recognition reference row: {key}")
        require(math.isclose(float(row[0]["Macro_AUC"]), expected, abs_tol=1e-10), f"Unexpected recognition AUC: {key}")

    metadata = json.loads((ROOT / "results" / "FINAL_ANALYSIS_METADATA.json").read_text(encoding="utf-8"))
    require(metadata.get("inspire_version") == "1.0", "Metadata must lock INSPIRE version 1.0.")
    print("PASS: frozen model and aggregate reference outputs match release v1.0.0.")


if __name__ == "__main__":
    main()
