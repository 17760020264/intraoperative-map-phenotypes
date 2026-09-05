from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from map_features import FrozenModel


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply the frozen MOVER phenotype model without external refitting.")
    parser.add_argument("--input", required=True, help="External operation-level 91-descriptor table")
    parser.add_argument("--output", required=True)
    parser.add_argument("--model-dir", default="model")
    parser.add_argument("--eligible-column", default="temporal_quality_eligible")
    args = parser.parse_args()

    data = pd.read_csv(args.input, low_memory=False)
    if args.eligible_column in data:
        data = data[pd.to_numeric(data[args.eligible_column], errors="coerce").eq(1)].copy()
    model = FrozenModel.load(args.model_dir)
    assignment = model.assign(data)
    output = pd.concat([data.reset_index(drop=True), assignment.reset_index(drop=True)], axis=1)
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False, encoding="utf-8-sig")
    print(output["Phenotype"].value_counts().to_string())


if __name__ == "__main__":
    main()
