from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from map_features import calculate_descriptors, candidate_columns


def main() -> None:
    parser = argparse.ArgumentParser(description="Calculate the 91 MAP candidate descriptors from a long-form trajectory file.")
    parser.add_argument("--input", required=True, help="CSV with one row per MAP measurement")
    parser.add_argument("--output", required=True)
    parser.add_argument("--id-column", default="operation_id")
    parser.add_argument("--patient-column", default="patient_id")
    parser.add_argument("--time-column", default="time")
    parser.add_argument("--map-column", default="map")
    parser.add_argument("--or-duration-column", default="or_duration_min")
    parser.add_argument("--min-or-duration", type=float, default=60.0, help="Strict lower bound in minutes; default reproduces OR duration >60 min")
    args = parser.parse_args()

    source = pd.read_csv(args.input, low_memory=False)
    required = {args.id_column, args.time_column, args.map_column}
    missing = required.difference(source.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    rows: list[dict[str, object]] = []
    for operation_id, group in source.groupby(args.id_column, sort=False):
        base: dict[str, object] = {args.id_column: operation_id}
        if args.patient_column in group:
            base[args.patient_column] = group[args.patient_column].iloc[0]
        if args.or_duration_column in group:
            base[args.or_duration_column] = pd.to_numeric(group[args.or_duration_column], errors="coerce").iloc[0]
        try:
            metrics = calculate_descriptors(group[args.time_column].to_numpy(), group[args.map_column].to_numpy())
            duration = float(base.get(args.or_duration_column, metrics["total_duration_min"]))
            coverage = metrics["total_duration_min"] / duration if duration > 0 else float("nan")
            metrics["map_or_coverage"] = coverage
            metrics["or_duration_eligible"] = int(duration > args.min_or_duration)
            metrics["temporal_quality_eligible"] = int(
                metrics["or_duration_eligible"] == 1
                and metrics["max_gap_min"] <= 15
                and coverage >= 0.70
            )
            reasons = []
            if metrics["or_duration_eligible"] == 0:
                reasons.append(f"OR duration <={args.min_or_duration:g} min")
            if metrics["max_gap_min"] > 15:
                reasons.append("adjacent MAP gap >15 min")
            if not coverage >= 0.70:
                reasons.append("MAP-OR coverage <70%")
            rows.append({**base, **metrics, "exclusion_reason": "; ".join(reasons)})
        except ValueError as error:
            rows.append({**base, "temporal_quality_eligible": 0, "exclusion_reason": str(error)})

    output = pd.DataFrame(rows)
    expected = [name for name in candidate_columns() if name not in output.columns]
    for name in expected:
        output[name] = pd.NA
    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    output.to_csv(args.output, index=False, encoding="utf-8-sig")
    print(f"Wrote {len(output):,} operation rows to {args.output}")


if __name__ == "__main__":
    main()
