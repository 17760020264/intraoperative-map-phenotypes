from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


LOW_THRESHOLDS = (70, 65, 60, 55, 50)
HIGH_THRESHOLDS = (100, 110, 120, 130, 140)

FINAL_FEATURES = (
    "baseline_map", "mean_map", "min_map", "max_map",
    "time_weighted_avg_map", "delta_map", "max_decrease", "arv",
    "map_sd", "map_cv", "map_range", "measurement_rate_per_min",
    "fraction_time_below_65", "fraction_time_below_55",
    "aut_65_per_min", "episodes_below_65_per_hour",
    "fraction_time_above_120", "fraction_time_above_140",
    "aat_120_per_min", "episodes_above_120_per_hour",
)

LOG_FEATURES = {
    "max_decrease", "arv", "map_sd", "map_cv", "map_range",
    "measurement_rate_per_min", "fraction_time_below_65",
    "fraction_time_below_55", "aut_65_per_min",
    "episodes_below_65_per_hour", "fraction_time_above_120",
    "fraction_time_above_140", "aat_120_per_min",
    "episodes_above_120_per_hour",
}

PHENOTYPE_NAMES = {
    1: "Labile Hypotension",
    2: "Stable Hemodynamics",
    3: "Labile Hypertension",
}


def candidate_columns() -> list[str]:
    """Return the ordered 91 outcome-blind candidate MAP descriptors."""
    names = [
        "baseline_map", "mean_map", "max_map", "min_map",
        "time_weighted_avg_map", "delta_map", "max_decrease", "arv",
        "map_sd", "map_cv", "map_range",
    ]
    for threshold in LOW_THRESHOLDS:
        names.extend([
            f"time_below_{threshold}", f"episodes_below_{threshold}",
            f"mean_duration_below_{threshold}", f"max_duration_below_{threshold}",
            f"mean_interval_below_{threshold}", f"aut_{threshold}",
            f"mean_aut_{threshold}", f"mean_map_under_{threshold}",
        ])
    for threshold in HIGH_THRESHOLDS:
        names.extend([
            f"time_above_{threshold}", f"episodes_above_{threshold}",
            f"mean_duration_above_{threshold}", f"max_duration_above_{threshold}",
            f"mean_interval_above_{threshold}", f"aat_{threshold}",
            f"mean_aat_{threshold}", f"mean_map_above_{threshold}",
        ])
    assert len(names) == 91
    return names


def _episodes_and_durations(
    values: np.ndarray,
    times: np.ndarray,
    intervals: np.ndarray,
    threshold: float,
    below: bool,
) -> dict[str, float]:
    condition = values < threshold if below else values > threshold
    event_durations: list[float] = []
    event_starts: list[float] = []
    event_ends: list[float] = []
    current = 0.0
    in_event = False
    current_end = math.nan

    for index, matches in enumerate(condition):
        if matches:
            if not in_event:
                in_event = True
                current = 0.0
                event_starts.append(float(times[index]))
            current += float(intervals[index])
            current_end = float(times[index])
        elif in_event:
            event_durations.append(current)
            event_ends.append(current_end)
            in_event = False
    if in_event:
        event_durations.append(current)
        event_ends.append(current_end)

    event_intervals = [
        event_starts[index] - event_ends[index - 1]
        for index in range(1, len(event_starts))
    ]
    total_time = float(intervals[condition].sum())
    departures = threshold - values if below else values - threshold
    area = float((departures * intervals * condition).sum())
    selected_values = values[condition]

    return {
        "time": total_time,
        "episodes": float(len(event_durations)),
        "mean_duration": float(np.mean(event_durations)) if event_durations else math.nan,
        "max_duration": float(np.max(event_durations)) if event_durations else math.nan,
        "mean_interval": float(np.mean(event_intervals)) if event_intervals else math.nan,
        "area": area,
        "mean_area": area / len(event_durations) if event_durations else math.nan,
        "mean_map": float(np.mean(selected_values)) if len(selected_values) else math.nan,
    }


def prepare_trace(times: np.ndarray, values: np.ndarray) -> tuple[np.ndarray, np.ndarray, int]:
    """Clean one operation while preserving the submitted analysis conventions."""
    frame = pd.DataFrame({"time": times, "map": values})
    frame["map"] = pd.to_numeric(frame["map"], errors="coerce")
    numeric_time = pd.to_numeric(frame["time"], errors="coerce")
    if numeric_time.notna().sum() == len(frame):
        frame["minute"] = numeric_time
    else:
        parsed = pd.to_datetime(frame["time"], errors="coerce")
        frame["minute"] = (parsed - parsed.min()).dt.total_seconds() / 60.0

    frame = frame.dropna(subset=["minute", "map"])
    removed = int(((frame["map"] < 30) | (frame["map"] > 200)).sum())
    frame = frame[frame["map"].between(30, 200)]
    frame = frame.groupby("minute", as_index=False)["map"].median().sort_values("minute")
    if len(frame) < 2:
        raise ValueError("At least 2 valid MAP measurements at distinct times are required.")
    time = frame["minute"].to_numpy(float)
    time -= time[0]
    return time, frame["map"].to_numpy(float), removed


def calculate_descriptors(times: np.ndarray, values: np.ndarray) -> dict[str, float]:
    """Calculate the 91 candidate descriptors for one sorted MAP trajectory.

    The interval convention matches the submitted analysis: the first value has
    zero elapsed time and each later value is weighted by time since the preceding
    measurement.
    """
    times, values, removed = prepare_trace(times, values)
    intervals = np.r_[0.0, np.diff(times)]
    if np.any(intervals < 0):
        raise ValueError("MAP timestamps must be sortable in ascending order.")
    duration = float(intervals.sum())
    if duration <= 0:
        raise ValueError("The analyzable MAP interval must exceed 0 minutes.")

    baseline = float(values[0])
    mean_map = float(values.mean())
    map_sd = float(values.std(ddof=1)) if len(values) > 1 else math.nan
    result: dict[str, float] = {
        "n_measurements": float(len(values)),
        "start_min": float(times[0]),
        "end_min": float(times[-1]),
        "total_duration_min": duration,
        "max_gap_min": float(np.diff(times).max()),
        "out_of_range_removed": float(removed),
        "baseline_map": baseline,
        "mean_map": mean_map,
        "max_map": float(values.max()),
        "min_map": float(values.min()),
        "time_weighted_avg_map": float((values * intervals).sum() / duration),
        "delta_map": mean_map - baseline,
        "max_decrease": baseline - float(values.min()),
        "arv": float((np.abs(np.diff(values)) * intervals[1:]).sum() / duration),
        "map_sd": map_sd,
        "map_cv": 100.0 * map_sd / mean_map if mean_map and np.isfinite(map_sd) else math.nan,
        "map_range": float(values.max() - values.min()),
    }

    for threshold in LOW_THRESHOLDS:
        metric = _episodes_and_durations(values, times, intervals, threshold, True)
        result.update({
            f"time_below_{threshold}": metric["time"],
            f"episodes_below_{threshold}": metric["episodes"],
            f"mean_duration_below_{threshold}": metric["mean_duration"],
            f"max_duration_below_{threshold}": metric["max_duration"],
            f"mean_interval_below_{threshold}": metric["mean_interval"],
            f"aut_{threshold}": metric["area"],
            f"mean_aut_{threshold}": metric["mean_area"],
            f"mean_map_under_{threshold}": metric["mean_map"],
        })
    for threshold in HIGH_THRESHOLDS:
        metric = _episodes_and_durations(values, times, intervals, threshold, False)
        result.update({
            f"time_above_{threshold}": metric["time"],
            f"episodes_above_{threshold}": metric["episodes"],
            f"mean_duration_above_{threshold}": metric["mean_duration"],
            f"max_duration_above_{threshold}": metric["max_duration"],
            f"mean_interval_above_{threshold}": metric["mean_interval"],
            f"aat_{threshold}": metric["area"],
            f"mean_aat_{threshold}": metric["mean_area"],
            f"mean_map_above_{threshold}": metric["mean_map"],
        })
    return result


def final_feature_frame(descriptors: pd.DataFrame) -> pd.DataFrame:
    """Convert the 91-descriptor table to the frozen 20-feature representation."""
    duration = pd.to_numeric(descriptors["total_duration_min"], errors="coerce").clip(lower=1e-9)
    frame = pd.DataFrame(index=descriptors.index)
    for name in FINAL_FEATURES[:11]:
        frame[name] = pd.to_numeric(descriptors[name], errors="coerce")
    frame["measurement_rate_per_min"] = pd.to_numeric(descriptors["n_measurements"], errors="coerce") / duration
    frame["fraction_time_below_65"] = pd.to_numeric(descriptors["time_below_65"], errors="coerce") / duration
    frame["fraction_time_below_55"] = pd.to_numeric(descriptors["time_below_55"], errors="coerce") / duration
    frame["aut_65_per_min"] = pd.to_numeric(descriptors["aut_65"], errors="coerce") / duration
    frame["episodes_below_65_per_hour"] = 60.0 * pd.to_numeric(descriptors["episodes_below_65"], errors="coerce") / duration
    frame["fraction_time_above_120"] = pd.to_numeric(descriptors["time_above_120"], errors="coerce") / duration
    frame["fraction_time_above_140"] = pd.to_numeric(descriptors["time_above_140"], errors="coerce") / duration
    frame["aat_120_per_min"] = pd.to_numeric(descriptors["aat_120"], errors="coerce") / duration
    frame["episodes_above_120_per_hour"] = 60.0 * pd.to_numeric(descriptors["episodes_above_120"], errors="coerce") / duration
    return frame.loc[:, FINAL_FEATURES]


def transform_feature_frame(frame: pd.DataFrame) -> pd.DataFrame:
    transformed = frame.copy()
    for name in LOG_FEATURES:
        transformed[name] = np.log1p(pd.to_numeric(transformed[name], errors="coerce").clip(lower=0))
    return transformed


@dataclass(frozen=True)
class FrozenModel:
    specification: pd.DataFrame
    loadings: np.ndarray
    centroids: np.ndarray

    @classmethod
    def load(cls, model_dir: str | Path) -> "FrozenModel":
        model_dir = Path(model_dir)
        specification = pd.read_csv(model_dir / "FULL_MODEL_FEATURE_SPECIFICATION.csv").sort_values("Order")
        raw_loadings = pd.read_csv(model_dir / "FULL_MODEL_PCA_LOADINGS.csv")
        loadings = (
            raw_loadings.pivot(index="PC", columns="Feature", values="Loading")
            .reindex(index=[f"PC{i}" for i in range(1, 6)], columns=specification["Feature"])
            .to_numpy(float)
        )
        centroids = (
            pd.read_csv(model_dir / "FULL_MODEL_CLUSTER_CENTROIDS.csv")
            .set_index("Cluster").reindex([1, 2, 3])[[f"PC{i}" for i in range(1, 6)]]
            .to_numpy(float)
        )
        return cls(specification, loadings, centroids)

    def assign(self, descriptors: pd.DataFrame) -> pd.DataFrame:
        raw = final_feature_frame(descriptors)
        transformed = transform_feature_frame(raw)
        spec = self.specification.set_index("Feature").reindex(FINAL_FEATURES)
        for column in FINAL_FEATURES:
            transformed[column] = transformed[column].fillna(float(spec.loc[column, "Development_median"]))
        scaled = (
            (transformed.to_numpy(float) - spec["Development_median"].to_numpy(float))
            / spec["Development_IQR"].to_numpy(float)
            - spec["PCA_center"].to_numpy(float)
        )
        pcs = scaled @ self.loadings.T
        distances = np.sqrt(((pcs[:, None, :] - self.centroids[None, :, :]) ** 2).sum(axis=2))
        clusters = distances.argmin(axis=1) + 1
        result = pd.DataFrame({
            "Cluster_GT60": clusters,
            "Phenotype": [PHENOTYPE_NAMES[int(value)] for value in clusters],
            "nearest_centroid_distance": distances.min(axis=1),
        }, index=descriptors.index)
        for index in range(5):
            result[f"PC{index + 1}"] = pcs[:, index]
        for index in range(3):
            result[f"distance_to_cluster_{index + 1}"] = distances[:, index]
        return result
