from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAX_PUBLIC_FILE_BYTES = 50 * 1024 * 1024
TEXT_SUFFIXES = {".py", ".r", ".R", ".md", ".txt", ".json", ".yml", ".yaml", ".cff", ".csv", ".html", ".js", ".css", ".toml"}
FORBIDDEN_PATH_PARTS = {"data", "raw_data", "private_data", "derived", "work", "outputs", "__pycache__", ".venv"}
FORBIDDEN_TEXT = {
    r"INSPIRE\s+(?:version\s+)?1\.3": "stale INSPIRE 1.3 reference",
    r"INSPIRE\s+(?:version\s+)?1\.4(?:\.2)?": "stale INSPIRE 1.4.x reference",
    r"C:\\Users\\Zhu YC": "author workstation path",
    r"D:\\MOVER": "author MOVER data path",
    r"D:\\INSPIRE": "author INSPIRE data path",
    r"\bbiyaodan\b": "download account name",
    r"(?:password|passwd|api[_-]?key|access[_-]?token)\s*[:=]\s*['\"][^'\"]+": "possible credential",
}
ALLOWED_CSV = {
    "model/FULL_MODEL_FEATURE_SPECIFICATION.csv",
    "model/FULL_MODEL_PCA_LOADINGS.csv",
    "model/FULL_MODEL_CLUSTER_CENTROIDS.csv",
    "app/model/FULL_MODEL_FEATURE_SPECIFICATION.csv",
    "app/model/FULL_MODEL_PCA_LOADINGS.csv",
    "app/model/FULL_MODEL_CLUSTER_CENTROIDS.csv",
    "examples/sample_map.csv",
    "examples/sample_map_long.csv",
    "results/BMI_RECALCULATED_SUMMARY_AND_SMD.csv",
    "results/FINAL_MODEL_COVARIATE_MISSINGNESS.csv",
    "results/FINAL_MODEL_DENOMINATORS.csv",
    "results/FINAL_OUTCOME_RATES_BY_PHENOTYPE.csv",
    "results/FOLD_SAFE_RECOGNITION_CLASS_PERFORMANCE.csv",
    "results/FOLD_SAFE_RECOGNITION_PERFORMANCE.csv",
    "results/MACE_HARMONIZED_72H_RATES_BY_PHENOTYPE.csv",
    "results/MACE_HARMONIZED_72H_SOURCE_COUNTS.csv",
    "results/MOVER_MULTIPLE_IMPUTATION_SENSITIVITY.csv",
    "results/PATIENT_CLUSTER_AND_REDUCED_MODEL_SENSITIVITY.csv",
    "results/SUPPLEMENTARY_TABLE_S5E_LAB_EVALUABLE_OUTCOME_SENSITIVITY.csv",
    "results/SUPPLEMENTARY_TABLE_S6_ALL_20_FEATURES_PER_SD_ASSOCIATIONS.csv",
    "results/SUPPLEMENTARY_TABLE_S7C_ADJUSTED_HYPERTENSION_MEDICATION_ASSOCIATIONS.csv",
    "results/TABLE_2_PRIMARY_PREOPERATIVE_ADJUSTED_OR.csv",
}


def main() -> None:
    problems: list[str] = []
    files = [path for path in ROOT.rglob("*") if path.is_file() and ".git" not in path.parts]
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if path.stat().st_size > MAX_PUBLIC_FILE_BYTES:
            problems.append(f"file exceeds 50 MiB: {relative}")
        if any(part.lower() in FORBIDDEN_PATH_PARTS for part in path.relative_to(ROOT).parts):
            problems.append(f"private/intermediate directory present: {relative}")
        if path.suffix.lower() == ".csv" and relative not in ALLOWED_CSV:
            problems.append(f"unapproved CSV file: {relative}")
        if relative == "scripts/audit_public_release.py":
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in {"LICENSE", ".gitignore", "VERSION"}:
            try:
                text = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue
            for pattern, label in FORBIDDEN_TEXT.items():
                if re.search(pattern, text, flags=re.IGNORECASE):
                    problems.append(f"{label}: {relative}")

    if problems:
        print("PUBLIC RELEASE AUDIT FAILED")
        for problem in sorted(set(problems)):
            print("-", problem)
        raise SystemExit(1)
    print(f"PASS: audited {len(files)} public files; no blocked data paths, stale INSPIRE versions, or obvious credentials found.")


if __name__ == "__main__":
    main()
