from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd

from map_features import FINAL_FEATURES, LOG_FEATURES, PHENOTYPE_NAMES, final_feature_frame, transform_feature_frame


DOMAINS = (
    ["BP level"] * 7 + ["BP variability / sampling"] * 5
    + ["Hypotension burden"] * 4 + ["Hypertension burden"] * 4
)


def squared_distances(x: np.ndarray, centers: np.ndarray) -> np.ndarray:
    return np.maximum((x * x).sum(1)[:, None] + (centers * centers).sum(1)[None, :] - 2 * x @ centers.T, 0)


def kmeans_once(x: np.ndarray, seed: int) -> tuple[np.ndarray, np.ndarray, float]:
    rng = np.random.default_rng(seed)
    centers = [x[rng.integers(len(x))]]
    for _ in range(2):
        distance = squared_distances(x, np.asarray(centers)).min(1)
        centers.append(x[rng.choice(len(x), p=distance / distance.sum())])
    centers_array = np.asarray(centers).copy()
    previous = None
    for _ in range(300):
        labels = squared_distances(x, centers_array).argmin(1)
        if previous is not None and np.array_equal(labels, previous):
            break
        previous = labels.copy()
        for index in range(3):
            centers_array[index] = x[labels == index].mean(0)
    distance = squared_distances(x, centers_array)
    labels = distance.argmin(1)
    return labels, centers_array, float(distance[np.arange(len(x)), labels].sum())


def main() -> None:
    parser = argparse.ArgumentParser(description="Reproduce MOVER robust scaling, PCA, and 3-cluster derivation.")
    parser.add_argument("--input", required=True, help="MOVER operation-level 91-descriptor table")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--id-column", default="operation_id")
    parser.add_argument("--eligible-column", default="temporal_quality_eligible")
    args = parser.parse_args()

    data = pd.read_csv(args.input, low_memory=False)
    if args.eligible_column in data:
        data = data[pd.to_numeric(data[args.eligible_column], errors="coerce").eq(1)].copy()
    features = final_feature_frame(data)
    transformed = transform_feature_frame(features)
    matrix = transformed.to_numpy(float)
    imputation = np.nanmedian(matrix, axis=0)
    missing = np.where(np.isnan(matrix))
    matrix[missing] = imputation[missing[1]]
    median = np.median(matrix, axis=0)
    iqr = np.quantile(matrix, 0.75, axis=0) - np.quantile(matrix, 0.25, axis=0)
    iqr[iqr == 0] = 1.0
    scaled = (matrix - median) / iqr
    pca_center = scaled.mean(axis=0)
    centered = scaled - pca_center
    _, singular_values, vt = np.linalg.svd(centered, full_matrices=False)
    loadings = vt[:5]
    pcs = centered @ loadings.T

    fits = [kmeans_once(pcs, seed) for seed in (11, 22, 33, 44, 55, 66, 77, 88, 99, 111)]
    raw_labels, _, within_ss = min(fits, key=lambda value: value[2])
    order = (
        pd.DataFrame({"raw": raw_labels, "twa": features["time_weighted_avg_map"].to_numpy()})
        .groupby("raw")["twa"].median().sort_values().index
    )
    mapping = {int(raw): index + 1 for index, raw in enumerate(order)}
    labels = np.asarray([mapping[int(value)] for value in raw_labels])
    centroids = np.vstack([pcs[labels == cluster].mean(axis=0) for cluster in (1, 2, 3)])

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    specification = pd.DataFrame({
        "Order": np.arange(1, 21),
        "Feature": FINAL_FEATURES,
        "Domain": DOMAINS,
        "Transformation": ["log1p(max(x,0))" if name in LOG_FEATURES else "identity" for name in FINAL_FEATURES],
        "Development_median": median,
        "Development_IQR": iqr,
        "PCA_center": pca_center,
    })
    specification.to_csv(output_dir / "FULL_MODEL_FEATURE_SPECIFICATION.csv", index=False)
    pd.DataFrame([
        {"PC": f"PC{pc + 1}", "Feature": feature, "Loading": loadings[pc, column]}
        for pc in range(5) for column, feature in enumerate(FINAL_FEATURES)
    ]).to_csv(output_dir / "FULL_MODEL_PCA_LOADINGS.csv", index=False)
    pd.DataFrame(centroids, columns=[f"PC{i}" for i in range(1, 6)]).assign(Cluster=[1, 2, 3]).loc[:, ["Cluster", "PC1", "PC2", "PC3", "PC4", "PC5"]].to_csv(output_dir / "FULL_MODEL_CLUSTER_CENTROIDS.csv", index=False)
    assignments = pd.DataFrame({
        args.id_column: data[args.id_column] if args.id_column in data else np.arange(len(data)),
        "Cluster_GT60": labels,
        "Phenotype": [PHENOTYPE_NAMES[int(value)] for value in labels],
    })
    assignments.to_csv(output_dir / "MOVER_DERIVATION_ASSIGNMENTS.csv", index=False)
    variance = singular_values ** 2 / np.sum(singular_values ** 2)
    audit = {
        "operations": int(len(data)),
        "features": 20,
        "principal_components": 5,
        "cumulative_variance_5": float(variance[:5].sum()),
        "within_cluster_sum_of_squares": within_ss,
        "cluster_counts": {str(k): int((labels == k).sum()) for k in (1, 2, 3)},
    }
    (output_dir / "MODEL_DERIVATION_AUDIT.json").write_text(json.dumps(audit, indent=2), encoding="utf-8")
    print(json.dumps(audit, indent=2))


if __name__ == "__main__":
    main()
