from __future__ import annotations

import json
import os
import re
from collections import defaultdict
from pathlib import Path

import numpy as np
import pandas as pd


ROOT = Path(os.environ.get("PROJECT_ROOT", ".")).resolve()
OUT = Path(os.environ.get("MACE_OUTPUT_DIR", ROOT / "derived" / "harmonized_mace_72h")).resolve()
OUT.mkdir(parents=True, exist_ok=True)

MOVER_INPUT = Path(os.environ.get("MOVER_OUTCOME_INPUT", ROOT / "data" / "MOVER_GT60_UPDATED_RCRI7D_FULL_OUTCOMES.csv"))
INSPIRE_INPUT = Path(os.environ.get("INSPIRE_OUTCOME_INPUT", ROOT / "data" / "INSPIRE_GT60_UPDATED_FULL_OUTCOMES.csv"))
MOVER_LABS = Path(os.environ.get("MOVER_LABS_INPUT", ROOT / "data" / "mover" / "patient_labs.csv"))
INSPIRE_LABS = Path(os.environ.get("INSPIRE_LABS_INPUT", ROOT / "data" / "inspire" / "labs.csv"))


def parse_uln(value: object) -> float | None:
    if pd.isna(value):
        return None
    text = str(value).strip()
    if not text or text.lower() in {"unknown", "nan", "none"}:
        return None
    nums = [float(x) for x in re.findall(r"\d+(?:\.\d+)?", text)]
    if not nums:
        return None
    return max(nums)


def evaluate_series(pre: pd.DataFrame, post: pd.DataFrame) -> dict[str, object]:
    """Apply the prespecified acute myocardial-injury proxy to one analyte.

    With a baseline, the postoperative peak must exceed its URL and rise by at
    least one postoperative assay URL. Without a baseline, at least two
    postoperative values are required and their range must be at least one peak
    assay URL. The latter captures a postoperative rise/fall pattern.
    """
    empty = {
        "assessed": 0,
        "positive": 0,
        "pre_value_ng_L": np.nan,
        "pre_url_ng_L": np.nan,
        "post_peak_value_ng_L": np.nan,
        "post_peak_url_ng_L": np.nan,
        "post_peak_x_url": np.nan,
        "post_n": 0,
        "delta_ng_L": np.nan,
        "assessment_route": "not evaluable",
    }
    if post.empty:
        return empty

    post = post.sort_values("time").copy()
    # Peak is defined relative to its assay-specific URL, which is robust to
    # changes between conventional and high-sensitivity assays.
    peak_idx = (post["value_ng_L"] / post["url_ng_L"]).idxmax()
    peak = post.loc[peak_idx]
    last_pre = pre.sort_values("time").iloc[-1] if not pre.empty else None
    out = dict(empty)
    out.update({
        "post_peak_value_ng_L": float(peak.value_ng_L),
        "post_peak_url_ng_L": float(peak.url_ng_L),
        "post_peak_x_url": float(peak.value_ng_L / peak.url_ng_L),
        "post_n": int(len(post)),
    })

    if last_pre is not None:
        delta = float(peak.value_ng_L - last_pre.value_ng_L)
        out.update({
            "assessed": 1,
            "pre_value_ng_L": float(last_pre.value_ng_L),
            "pre_url_ng_L": float(last_pre.url_ng_L),
            "delta_ng_L": delta,
            "assessment_route": "preoperative baseline plus postoperative peak",
            "positive": int(peak.value_ng_L > peak.url_ng_L and delta >= peak.url_ng_L),
        })
        return out

    if len(post) >= 2:
        serial_delta = float(post.value_ng_L.max() - post.value_ng_L.min())
        out.update({
            "assessed": 1,
            "delta_ng_L": serial_delta,
            "assessment_route": "serial postoperative change without preoperative baseline",
            "positive": int(peak.value_ng_L > peak.url_ng_L and serial_delta >= peak.url_ng_L),
        })
    return out


def mover_flags(m: pd.DataFrame) -> pd.DataFrame:
    keys = set(zip(m.LOG_ID.astype(str), m.MRN.astype(str)))
    by_key: dict[tuple[str, str], list[tuple]] = defaultdict(list)
    rows_read = 0
    rows_eligible = 0
    use = ["LOG_ID", "MRN", "Lab Name", "Observation Value", "Measurement Units", "Reference Range", "Collection Datetime"]
    for ch in pd.read_csv(MOVER_LABS, usecols=use, dtype=str, chunksize=500_000, low_memory=False):
        rows_read += len(ch)
        ch = ch[ch["Lab Name"].eq("Troponin I.cardiac")].copy()
        if ch.empty:
            continue
        ch = ch.loc[[pair in keys for pair in zip(ch.LOG_ID.astype(str), ch.MRN.astype(str))]].copy()
        ch["value"] = pd.to_numeric(ch["Observation Value"], errors="coerce")
        ch["time"] = pd.to_datetime(ch["Collection Datetime"], errors="coerce", utc=True)
        ch["unit"] = ch["Measurement Units"].astype(str).str.strip()
        ch["url_raw"] = ch["Reference Range"].map(parse_uln)
        ch = ch[
            ch.value.between(0, 999998)
            & ch.time.notna()
            & ch.unit.isin(["ng/L", "ng/mL"])
            & pd.to_numeric(ch.url_raw, errors="coerce").gt(0)
        ].copy()
        if ch.empty:
            continue
        factor = np.where(ch.unit.eq("ng/mL"), 1000.0, 1.0)
        ch["value_ng_L"] = ch.value * factor
        ch["url_ng_L"] = pd.to_numeric(ch.url_raw) * factor
        rows_eligible += len(ch)
        for row in ch[["LOG_ID", "MRN", "time", "value_ng_L", "url_ng_L", "unit"]].itertuples(index=False, name=None):
            log_id, mrn, *vals = row
            by_key[(str(log_id), str(mrn))].append(tuple(vals))

    records = []
    for r in m[["LOG_ID", "MRN", "IN_OR_DTTM", "OR_out_datetime", "HOSP_DISCH_TIME"]].itertuples(index=False):
        key = (str(r.LOG_ID), str(r.MRN))
        op_in = pd.to_datetime(r.IN_OR_DTTM, errors="coerce", utc=True)
        op_out = pd.to_datetime(r.OR_out_datetime, errors="coerce", utc=True)
        discharge = pd.to_datetime(r.HOSP_DISCH_TIME, errors="coerce", utc=True)
        vals = pd.DataFrame(by_key.get(key, []), columns=["time", "value_ng_L", "url_ng_L", "unit"])
        if vals.empty or pd.isna(op_in) or pd.isna(op_out):
            res = evaluate_series(vals.iloc[0:0], vals.iloc[0:0])
        else:
            end = op_out + pd.Timedelta(hours=72)
            if pd.notna(discharge):
                end = min(end, discharge)
            pre = vals[(vals.time >= op_in - pd.Timedelta(days=30)) & (vals.time < op_in)]
            post = vals[(vals.time >= op_out) & (vals.time <= end)]
            res = evaluate_series(pre, post)
        res.update({"Center": "MOVER", "ID": str(r.LOG_ID), "Secondary_ID": str(r.MRN), "Analyte": "cTnI"})
        records.append(res)
    out = pd.DataFrame(records)
    out.attrs["audit"] = {"lab_rows_read": rows_read, "eligible_troponin_rows": rows_eligible}
    return out


def inspire_flags(i: pd.DataFrame) -> pd.DataFrame:
    subjects = set(i.subject_id.astype("Int64").astype(str))
    parts = []
    rows_read = 0
    for ch in pd.read_csv(INSPIRE_LABS, usecols=["subject_id", "chart_time", "item_name", "value"], chunksize=1_000_000, low_memory=False):
        rows_read += len(ch)
        names = ch.item_name.astype(str).str.lower()
        mask = names.isin(["troponin_i", "troponin_t"]) & ch.subject_id.astype("Int64").astype(str).isin(subjects)
        if mask.any():
            x = ch.loc[mask].copy()
            x["item_name"] = names.loc[mask]
            parts.append(x)
    lab = pd.concat(parts, ignore_index=True) if parts else pd.DataFrame(columns=["subject_id", "chart_time", "item_name", "value"])
    lab["subject_key"] = lab.subject_id.astype("Int64").astype(str)
    lab["time"] = pd.to_numeric(lab.chart_time, errors="coerce")
    lab["value_ug_L"] = pd.to_numeric(lab.value, errors="coerce")
    lab = lab[lab.time.notna() & lab.value_ug_L.ge(0) & lab.value_ug_L.lt(999998)].copy()
    lab["value_ng_L"] = lab.value_ug_L * 1000.0
    lab["url_ng_L"] = lab.item_name.map({"troponin_i": 40.0, "troponin_t": 14.0})
    groups = {k: g[["time", "item_name", "value_ng_L", "url_ng_L"]].sort_values("time") for k, g in lab.groupby("subject_key", sort=False)}

    records = []
    for r in i[["op_id", "subject_id", "orin_time", "orout_time", "discharge_time"]].itertuples(index=False):
        subject_key = str(int(r.subject_id)) if pd.notna(r.subject_id) else ""
        g = groups.get(subject_key)
        analyte_results = []
        if g is not None and pd.notna(r.orin_time) and pd.notna(r.orout_time):
            end = float(r.orout_time) + 72 * 60
            if pd.notna(r.discharge_time):
                end = min(end, float(r.discharge_time))
            for analyte in ["troponin_i", "troponin_t"]:
                z = g[g.item_name.eq(analyte)][["time", "value_ng_L", "url_ng_L"]]
                pre = z[(z.time >= float(r.orin_time) - 30 * 1440) & (z.time < float(r.orin_time))]
                post = z[(z.time >= float(r.orout_time)) & (z.time <= end)]
                res = evaluate_series(pre, post)
                res["analyte"] = analyte
                analyte_results.append(res)
        if not analyte_results:
            analyte_results = [dict(evaluate_series(pd.DataFrame(columns=["time", "value_ng_L", "url_ng_L"]), pd.DataFrame(columns=["time", "value_ng_L", "url_ng_L"])), analyte="none")]
        positive = int(any(x["positive"] == 1 for x in analyte_results))
        assessed = int(any(x["assessed"] == 1 for x in analyte_results))
        # Preserve the most abnormal/evaluable analyte for transparent operation-level audit.
        chosen = max(analyte_results, key=lambda x: (x["positive"], x["assessed"], -np.inf if pd.isna(x["post_peak_x_url"]) else x["post_peak_x_url"]))
        records.append({
            "Center": "INSPIRE", "ID": str(r.op_id), "Secondary_ID": subject_key,
            "Analyte": chosen["analyte"], "assessed": assessed, "positive": positive,
            "pre_value_ng_L": chosen["pre_value_ng_L"], "pre_url_ng_L": chosen["pre_url_ng_L"],
            "post_peak_value_ng_L": chosen["post_peak_value_ng_L"], "post_peak_url_ng_L": chosen["post_peak_url_ng_L"],
            "post_peak_x_url": chosen["post_peak_x_url"], "post_n": chosen["post_n"],
            "delta_ng_L": chosen["delta_ng_L"], "assessment_route": chosen["assessment_route"],
        })
    out = pd.DataFrame(records)
    out.attrs["audit"] = {"lab_rows_read": rows_read, "eligible_troponin_rows": int(len(lab))}
    return out


def source_summary(center: str, cohort: pd.DataFrame, flags: pd.DataFrame, id_col: str, documented_col: str, old_col: str, cluster_col: str) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    z = cohort[[id_col, documented_col, old_col, cluster_col]].copy()
    z[id_col] = z[id_col].astype(str)
    f = flags.copy().rename(columns={"ID": id_col, "positive": "Lab_proxy_flag", "assessed": "Lab_proxy_assessed_flag"})
    z = z.merge(f, on=id_col, how="left", validate="one_to_one")
    z["Documented_event_flag"] = pd.to_numeric(z[documented_col], errors="coerce").fillna(0).eq(1).astype(int)
    z["Old_MACE_flag"] = pd.to_numeric(z[old_col], errors="coerce").fillna(0).eq(1).astype(int)
    z["Lab_proxy_flag"] = pd.to_numeric(z.Lab_proxy_flag, errors="coerce").fillna(0).astype(int)
    z["Lab_proxy_assessed_flag"] = pd.to_numeric(z.Lab_proxy_assessed_flag, errors="coerce").fillna(0).astype(int)
    z["MACE_harmonized_72h_flag"] = ((z.Documented_event_flag == 1) | (z.Lab_proxy_flag == 1)).astype(int)
    z["MACE_source"] = np.select(
        [(z.Documented_event_flag == 1) & (z.Lab_proxy_flag == 1), z.Documented_event_flag == 1, z.Lab_proxy_flag == 1],
        ["documented event + laboratory proxy", "documented event only", "laboratory proxy only"], default="no recorded event"
    )
    z["Center"] = center
    z = z.rename(columns={cluster_col: "Cluster"})
    phen = {1: "Labile Hypotension", 2: "Stable Hemodynamics", 3: "Labile Hypertension"}
    z["Phenotype"] = pd.to_numeric(z.Cluster, errors="coerce").map(phen)

    n = len(z)
    summary = pd.DataFrame([{
        "Center": center, "Cohort_N": n,
        "Laboratory_evaluable_N": int(z.Lab_proxy_assessed_flag.sum()),
        "Laboratory_evaluable_percent": 100 * z.Lab_proxy_assessed_flag.mean(),
        "Laboratory_proxy_events": int(z.Lab_proxy_flag.sum()),
        "Documented_events": int(z.Documented_event_flag.sum()),
        "Laboratory_documented_overlap": int(((z.Lab_proxy_flag == 1) & (z.Documented_event_flag == 1)).sum()),
        "Final_harmonized_MACE_events": int(z.MACE_harmonized_72h_flag.sum()),
        "Final_harmonized_MACE_percent": 100 * z.MACE_harmonized_72h_flag.mean(),
        "Previous_MACE_events": int(z.Old_MACE_flag.sum()),
        "Previous_MACE_percent": 100 * z.Old_MACE_flag.mean(),
        "Absolute_event_change": int(z.MACE_harmonized_72h_flag.sum() - z.Old_MACE_flag.sum()),
    }])
    rates = z.groupby(["Center", "Cluster", "Phenotype"], dropna=False).agg(
        Cohort_N=(id_col, "size"), Events=("MACE_harmonized_72h_flag", "sum"),
        Lab_evaluable_N=("Lab_proxy_assessed_flag", "sum"), Lab_proxy_events=("Lab_proxy_flag", "sum"),
        Documented_events=("Documented_event_flag", "sum")
    ).reset_index()
    rates["Percent"] = 100 * rates.Events / rates.Cohort_N
    return z, summary, rates


def main() -> None:
    m = pd.read_csv(MOVER_INPUT, low_memory=False, dtype={"LOG_ID": str, "MRN": str})
    i = pd.read_csv(INSPIRE_INPUT, low_memory=False)
    mf = mover_flags(m)
    mover_audit = dict(mf.attrs.get("audit", {}))
    inf = inspire_flags(i)
    inspire_audit = dict(inf.attrs.get("audit", {}))

    mz, ms, mr = source_summary("MOVER", m, mf, "LOG_ID", "MACE_structured_flag", "Final_MACE_enhanced", "Cluster_GT60")
    iz, ins, ir = source_summary("INSPIRE", i, inf, "op_id", "MACE_ICD_strict_flag", "MACE_final_flag", "Cluster_GT60")
    operation = pd.concat([
        mz[["Center", "LOG_ID", "Secondary_ID", "Cluster", "Phenotype", "Lab_proxy_assessed_flag", "Lab_proxy_flag", "Documented_event_flag", "MACE_harmonized_72h_flag", "MACE_source", "Analyte", "pre_value_ng_L", "pre_url_ng_L", "post_peak_value_ng_L", "post_peak_url_ng_L", "post_peak_x_url", "post_n", "delta_ng_L", "assessment_route"]].rename(columns={"LOG_ID": "Operation_ID"}),
        iz[["Center", "op_id", "Secondary_ID", "Cluster", "Phenotype", "Lab_proxy_assessed_flag", "Lab_proxy_flag", "Documented_event_flag", "MACE_harmonized_72h_flag", "MACE_source", "Analyte", "pre_value_ng_L", "pre_url_ng_L", "post_peak_value_ng_L", "post_peak_url_ng_L", "post_peak_x_url", "post_n", "delta_ng_L", "assessment_route"]].rename(columns={"op_id": "Operation_ID"}),
    ], ignore_index=True)
    source = pd.concat([ms, ins], ignore_index=True)
    rates = pd.concat([mr, ir], ignore_index=True)

    operation.to_csv(OUT / "MACE_HARMONIZED_72H_BY_OPERATION.csv", index=False, encoding="utf-8-sig")
    source.to_csv(OUT / "MACE_HARMONIZED_72H_SOURCE_COUNTS.csv", index=False, encoding="utf-8-sig")
    rates.to_csv(OUT / "MACE_HARMONIZED_72H_RATES_BY_PHENOTYPE.csv", index=False, encoding="utf-8-sig")

    # Model-ready cohorts keep the exact preoperative covariates used in the
    # current manuscript analysis; only the MACE flag is replaced.
    mover_model = m.merge(mz[["LOG_ID", "MACE_harmonized_72h_flag"]], on="LOG_ID", how="left", validate="one_to_one")
    inspire_model = i.copy()
    inspire_model["op_id"] = inspire_model.op_id.astype(str)
    iz2 = iz[["op_id", "MACE_harmonized_72h_flag"]].copy(); iz2["op_id"] = iz2.op_id.astype(str)
    inspire_model = inspire_model.merge(iz2, on="op_id", how="left", validate="one_to_one")
    mover_model.to_csv(OUT / "MOVER_MODEL_INPUT_REVISED_MACE.csv", index=False, encoding="utf-8-sig")
    inspire_model.to_csv(OUT / "INSPIRE_MODEL_INPUT_REVISED_MACE.csv", index=False, encoding="utf-8-sig")

    audit = {
        "definition": {
            "preoperative_baseline": "last same-analyte troponin within 30 days before OR entry",
            "postoperative_window": "OR exit through 72 hours or hospital discharge, whichever occurred first",
            "with_baseline": "postoperative peak > assay URL and postoperative peak - baseline >= 1 postoperative assay URL",
            "without_baseline": "at least 2 postoperative same-analyte measurements, peak > URL, and maximum-minimum >= 1 peak assay URL",
            "MOVER_URL": "row-specific cTnI upper reference limit after ng/L unit harmonization",
            "INSPIRE_URL": "cTnI 0.04 micrograms/L (40 ng/L); cTnT 0.014 micrograms/L (14 ng/L)",
            "final_MACE": "laboratory-defined acute myocardial injury proxy OR documented MI, cardiac arrest, or stroke",
            "interpretation": "laboratory proxy; not adjudicated MINS or PMI",
        },
        "MOVER": mover_audit,
        "INSPIRE": inspire_audit,
        "source_counts": source.to_dict(orient="records"),
    }
    (OUT / "MACE_HARMONIZED_72H_AUDIT.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8")
    print(source.to_string(index=False))
    print(rates.to_string(index=False))


if __name__ == "__main__":
    main()
