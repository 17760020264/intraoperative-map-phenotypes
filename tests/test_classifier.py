from pathlib import Path
import sys

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "app"))
import app  # noqa: E402


def test_synthetic_trace_classifies():
    trace = pd.read_csv(ROOT / "examples" / "sample_map.csv")
    result = app._classify(trace.iloc[:, 0].tolist(), trace.iloc[:, 1].tolist(), "synthetic-test")
    assert result["phenotype"] in app.PHENOTYPE_NAMES.values()
    assert len(result["features"]) == 20
    assert result["audit"]["valid_records"] >= 2
