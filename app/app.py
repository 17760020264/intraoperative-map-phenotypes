from __future__ import annotations

import io
import math
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel


ROOT = Path(__file__).resolve().parent
MODEL_DIR = ROOT / "model"
STATIC_DIR = ROOT / "static"

PHENOTYPE_NAMES = {
    1: "Labile Hypotension",
    2: "Stable Hemodynamics",
    3: "Labile Hypertension",
}
PHENOTYPE_COLORS = {1: "#D95B64", 2: "#5878B9", 3: "#2F8F83"}

OBSERVED_RISKS = {
    "MOVER": {
        1: {"MACE": 5.13, "AKI": 21.92, "Severe acute liver injury": 2.03, "Pulmonary complications": 4.23, "In-hospital death": 3.66, "ICU admission": 79.66, "Non-routine discharge": 36.78},
        2: {"MACE": 1.61, "AKI": 13.81, "Severe acute liver injury": 0.58, "Pulmonary complications": 2.32, "In-hospital death": 1.28, "ICU admission": 68.38, "Non-routine discharge": 26.99},
        3: {"MACE": 1.93, "AKI": 17.53, "Severe acute liver injury": 0.22, "Pulmonary complications": 2.48, "In-hospital death": 0.86, "ICU admission": 70.90, "Non-routine discharge": 26.57},
    },
    "INSPIRE": {
        1: {"MACE": 4.05, "AKI": 10.61, "Severe acute liver injury": 4.24, "Pulmonary complications": 2.92, "In-hospital death": 2.57, "ICU admission": 13.44},
        2: {"MACE": 0.97, "AKI": 4.31, "Severe acute liver injury": 1.41, "Pulmonary complications": 0.83, "In-hospital death": 0.49, "ICU admission": 9.79},
        3: {"MACE": 0.61, "AKI": 3.80, "Severe acute liver injury": 0.45, "Pulmonary complications": 0.32, "In-hospital death": 0.18, "ICU admission": 3.75},
    },
}


def _load_model() -> tuple[pd.DataFrame, np.ndarray, np.ndarray]:
    spec = pd.read_csv(MODEL_DIR / "FULL_MODEL_FEATURE_SPECIFICATION.csv")
    raw_loadings = pd.read_csv(MODEL_DIR / "FULL_MODEL_PCA_LOADINGS.csv")
    loadings = (
        raw_loadings.pivot(index="PC", columns="Feature", values="Loading")
        .reindex(index=[f"PC{i}" for i in range(1, 6)], columns=spec["Feature"])
        .to_numpy(float)
    )
    centroids = (
        pd.read_csv(MODEL_DIR / "FULL_MODEL_CLUSTER_CENTROIDS.csv")
        .set_index("Cluster")
        .reindex([1, 2, 3])[[f"PC{i}" for i in range(1, 6)]]
        .to_numpy(float)
    )
    return spec, loadings, centroids


SPEC, LOADINGS, CENTROIDS = _load_model()


class TracePayload(BaseModel):
    time: list[float]
    map: list[float]
    source: str = "manual"


def _episodes(mask: np.ndarray) -> int:
    if len(mask) == 0:
        return 0
    return int(mask[0]) + int(np.sum(mask[1:] & ~mask[:-1]))


def _prepare_trace(time_values: list[Any], map_values: list[Any]) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    frame = pd.DataFrame({"time": time_values, "map": map_values})
    frame["map"] = pd.to_numeric(frame["map"], errors="coerce")

    numeric_time = pd.to_numeric(frame["time"], errors="coerce")
    if numeric_time.notna().sum() == len(frame):
        frame["minute"] = numeric_time
    else:
        parsed = pd.to_datetime(frame["time"], errors="coerce")
        if parsed.notna().sum() < 2:
            raise ValueError("时间列无法识别；请使用分钟数或标准日期时间。")
        frame["minute"] = (parsed - parsed.min()).dt.total_seconds() / 60

    original_n = len(frame)
    frame = frame.dropna(subset=["minute", "map"])
    invalid_range = int(((frame["map"] < 30) | (frame["map"] > 200)).sum())
    frame = frame[(frame["map"] >= 30) & (frame["map"] <= 200)]
    frame = frame.groupby("minute", as_index=False)["map"].median().sort_values("minute")
    if len(frame) < 2:
        raise ValueError("至少需要两个有效且时间不同的MAP记录。")
    time = frame["minute"].to_numpy(float)
    time -= time[0]
    values = frame["map"].to_numpy(float)
    gaps = np.diff(time)
    duration = float(time[-1])
    if duration <= 0:
        raise ValueError("有效记录时长必须大于0分钟。")
    audit = {
        "original_records": original_n,
        "valid_records": int(len(frame)),
        "out_of_range_removed": invalid_range,
        "duration_min": round(duration, 2),
        "maximum_gap_min": round(float(gaps.max()), 2),
        "gap_over_15min": bool(np.any(gaps > 15)),
        "duration_over_60min": bool(duration > 60),
    }
    return time, values, audit


def _threshold_metrics(values: np.ndarray, intervals: np.ndarray, threshold: float, below: bool) -> tuple[float, int, float]:
    mask = values < threshold if below else values > threshold
    duration = float(intervals[mask].sum())
    area = float((((threshold - values) if below else (values - threshold)) * intervals * mask).sum())
    return duration, _episodes(mask), area


def _calculate_features(time: np.ndarray, values: np.ndarray) -> tuple[dict[str, float], dict[str, float]]:
    intervals = np.r_[0.0, np.diff(time)]
    duration = float(intervals.sum())
    if duration == 0:
        intervals = np.ones(len(values), dtype=float)
        duration = float(len(values))
    baseline = float(values[0])
    mean_map = float(np.mean(values))
    twa = float(np.sum(values * intervals) / duration)
    arv = float(np.sum(np.abs(np.diff(values)) * intervals[1:]) / duration)
    sd = float(np.std(values, ddof=1)) if len(values) > 1 else 0.0
    low65, ep_low65, aut65 = _threshold_metrics(values, intervals, 65, True)
    low55, _, _ = _threshold_metrics(values, intervals, 55, True)
    high120, ep_high120, aat120 = _threshold_metrics(values, intervals, 120, False)
    high140, _, _ = _threshold_metrics(values, intervals, 140, False)
    raw = {
        "baseline_map": baseline,
        "mean_map": mean_map,
        "min_map": float(values.min()),
        "max_map": float(values.max()),
        "time_weighted_avg_map": twa,
        "delta_map": mean_map - baseline,
        "max_decrease": baseline - float(values.min()),
        "arv": arv,
        "map_sd": sd,
        "map_cv": sd / mean_map * 100 if mean_map else 0.0,
        "map_range": float(values.max() - values.min()),
        "measurement_rate_per_min": float(len(values) / duration),
        "fraction_time_below_65": low65 / duration,
        "fraction_time_below_55": low55 / duration,
        "aut_65_per_min": aut65 / duration,
        "episodes_below_65_per_hour": 60 * ep_low65 / duration,
        "fraction_time_above_120": high120 / duration,
        "fraction_time_above_140": high140 / duration,
        "aat_120_per_min": aat120 / duration,
        "episodes_above_120_per_hour": 60 * ep_high120 / duration,
    }
    display = {
        "Monitoring duration, min": duration,
        "Measurements": float(len(values)),
        "Baseline MAP": baseline,
        "Mean MAP": mean_map,
        "Minimum MAP": float(values.min()),
        "Maximum MAP": float(values.max()),
        "Time-weighted MAP": twa,
        "MAP SD": sd,
        "ARV": arv,
        "Time MAP <65, min": low65,
        "Time MAP <55, min": low55,
        "Time MAP >120, min": high120,
        "Episodes MAP <65": float(ep_low65),
        "Episodes MAP >120": float(ep_high120),
    }
    return raw, display


def _classify(time_values: list[Any], map_values: list[Any], source: str) -> dict[str, Any]:
    time, values, audit = _prepare_trace(time_values, map_values)
    raw, display = _calculate_features(time, values)
    transformed = []
    feature_rows = []
    for row in SPEC.itertuples(index=False):
        value = float(raw[row.Feature])
        if str(row.Transformation).startswith("log1p"):
            value = math.log1p(max(value, 0.0))
        if not math.isfinite(value):
            value = float(row.Development_median)
        z = (value - float(row.Development_median)) / float(row.Development_IQR)
        transformed.append(z)
        feature_rows.append({
            "feature": row.Feature,
            "domain": row.Domain,
            "raw": round(float(raw[row.Feature]), 5),
            "standardized": round(float(z), 4),
        })
    scaled = np.asarray(transformed) - SPEC["PCA_center"].to_numpy(float)
    pcs = scaled @ LOADINGS.T
    distances = np.sqrt(np.sum((CENTROIDS - pcs[None, :]) ** 2, axis=1))
    cluster = int(np.argmin(distances) + 1)

    # Distance-derived similarity, not a calibrated posterior probability.
    logits = -(distances - distances.min())
    similarities = np.exp(logits) / np.exp(logits).sum()
    ordered = np.sort(similarities)[::-1]
    margin = float(ordered[0] - ordered[1])
    confidence = "High" if margin >= 0.45 else "Moderate" if margin >= 0.20 else "Low / borderline"

    warnings = []
    if not audit["duration_over_60min"]:
        warnings.append("记录时长未超过60分钟，不符合当前研究主要队列条件。")
    if audit["gap_over_15min"]:
        warnings.append("存在超过15分钟的相邻记录间隔，分类可靠性可能下降。")
    if audit["out_of_range_removed"]:
        warnings.append(f"已移除{audit['out_of_range_removed']}个超出30–200 mmHg的数据点。")
    if source == "draw":
        warnings.append("手绘曲线用于教学或探索，正式分析请上传原始分钟级MAP记录。")

    return {
        "cluster": cluster,
        "phenotype": PHENOTYPE_NAMES[cluster],
        "color": PHENOTYPE_COLORS[cluster],
        "confidence_label": confidence,
        "similarities": [
            {"cluster": k, "phenotype": PHENOTYPE_NAMES[k], "value": round(float(similarities[k - 1]) * 100, 1), "distance": round(float(distances[k - 1]), 3), "color": PHENOTYPE_COLORS[k]}
            for k in (1, 2, 3)
        ],
        "audit": audit,
        "warnings": warnings,
        "summary": {k: round(v, 2) for k, v in display.items()},
        "features": feature_rows,
        "principal_components": [round(float(x), 4) for x in pcs],
        "observed_risks": {center: values_by_cluster[cluster] for center, values_by_cluster in OBSERVED_RISKS.items()},
        "trace": {"time": time.round(3).tolist(), "map": values.round(2).tolist()},
    }


def _read_uploaded_file(upload: UploadFile, content: bytes) -> tuple[list[Any], list[Any]]:
    suffix = Path(upload.filename or "data.csv").suffix.lower()
    if suffix in {".xlsx", ".xls"}:
        frame = pd.read_excel(io.BytesIO(content))
    else:
        try:
            frame = pd.read_csv(io.BytesIO(content), encoding="utf-8-sig")
        except UnicodeDecodeError:
            frame = pd.read_csv(io.BytesIO(content), encoding="gb18030")
    normalized = {str(c).strip().lower(): c for c in frame.columns}
    time_aliases = ["time", "minute", "minutes", "recorded_time", "recorded time", "时间", "分钟"]
    map_aliases = ["map", "meas_value", "meas value", "mean arterial pressure", "平均动脉压"]
    time_col = next((normalized[x] for x in time_aliases if x in normalized), None)
    map_col = next((normalized[x] for x in map_aliases if x in normalized), None)
    if time_col is None or map_col is None:
        if len(frame.columns) >= 2:
            time_col, map_col = frame.columns[:2]
        else:
            raise ValueError("文件至少需要时间和MAP两列。")
    return frame[time_col].tolist(), frame[map_col].tolist()


app = FastAPI(title="Hemodynamic Phenotype Classifier", version="1.0.0")


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "model": "frozen-20-feature-pca-kmeans-k3"}


@app.post("/api/classify")
def classify(payload: TracePayload) -> dict[str, Any]:
    try:
        return _classify(payload.time, payload.map, payload.source)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.post("/api/classify-file")
async def classify_file(file: UploadFile = File(...)) -> dict[str, Any]:
    try:
        content = await file.read()
        time, values = _read_uploaded_file(file, content)
        return _classify(time, values, "upload")
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
