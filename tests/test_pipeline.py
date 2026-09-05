from pathlib import Path
import sys

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pipeline"))

from map_features import (  # noqa: E402
    FINAL_FEATURES,
    FrozenModel,
    calculate_descriptors,
    candidate_columns,
    final_feature_frame,
)


def test_candidate_inventory_and_final_features():
    assert len(candidate_columns()) == 91
    assert len(set(candidate_columns())) == 91
    assert len(FINAL_FEATURES) == 20


def test_descriptor_calculation_and_frozen_assignment():
    times = np.arange(0, 121, 5)
    values = np.array([92, 88, 83, 76, 69, 61, 56, 63, 72, 81, 87, 91, 96, 101, 108, 116, 124, 132, 119, 105, 93, 86, 78, 72, 68])
    descriptors = pd.DataFrame([calculate_descriptors(times, values)])
    assert descriptors.loc[0, "total_duration_min"] == 120
    assert descriptors.loc[0, "max_gap_min"] == 5
    assert final_feature_frame(descriptors).shape == (1, 20)
    assigned = FrozenModel.load(ROOT / "model").assign(descriptors)
    assert assigned.loc[0, "Cluster_GT60"] in {1, 2, 3}
    assert assigned.loc[0, "Phenotype"] in {"Labile Hypotension", "Stable Hemodynamics", "Labile Hypertension"}
