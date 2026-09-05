from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent

REQUIRED_HEADERS = {
    "mover_outcome_input": {
        "LOG_ID", "MRN", "IN_OR_DTTM", "OR_out_datetime", "HOSP_DISCH_TIME",
        "Cluster_GT60", "MACE_structured_flag", "Final_MACE_enhanced",
        "Age", "Sex", "BMI", "ASA", "Surgical_type", "Essential_hypertension_flag",
        "RCRI_score_0_6", "Modified_frailty_score_0_5", "AKI_combined_flag",
        "ALI_combined_strict_flag", "Pulmonary_enhanced_flag", "In_hospital_death_flag",
        "Height_m", "Weight_kg",
    },
    "inspire_outcome_input": {
        "op_id", "subject_id", "orin_time", "orout_time", "discharge_time",
        "Cluster_GT60", "MACE_ICD_strict_flag", "MACE_final_flag",
        "Common_Age", "Common_Male", "Common_BMI", "Common_ASA", "Common_Surgical_type",
        "Common_Hypertension", "RCRI_score_0_6", "Modified_frailty_score_0_5",
        "SA_AKI", "SA_ALI", "Pulmonary_enhanced_flag", "SA_Inhospital_death",
        "height", "weight", "BMI",
    },
    "mover_labs_input": {
        "LOG_ID", "MRN", "Lab Name", "Observation Value", "Measurement Units",
        "Reference Range", "Collection Datetime",
    },
    "inspire_labs_input": {"subject_id", "chart_time", "item_name", "value"},
    "mover_medication_input": {
        "LOG_ID", "ACEI_ARB_given_admission_to_or", "Beta_blocker_given_admission_to_or",
        "Calcium_channel_blocker_given_admission_to_or", "Diuretic_given_admission_to_or",
    },
    "inspire_medication_input": {"op_id", "ACEI_ARB", "Beta_blocker", "CCB", "Diuretic"},
    "mover_pre_bmi_input": {"LOG_ID", "Cluster_GT60", "Height_m", "Weight_kg", "BMI"},
    "inspire_pre_bmi_input": {"op_id", "Cluster_GT60", "height", "weight", "BMI"},
    "mover_early_feature_input": {"ID", "early15_evaluable", "early30_evaluable", "early60_evaluable"},
    "inspire_early_feature_input": {"ID", "early15_evaluable", "early30_evaluable", "early60_evaluable"},
}


def resolved(path_value: str, root: Path = ROOT) -> Path:
    path = Path(path_value)
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def run(command: list[str], environment: dict[str, str]) -> None:
    print("\n>", " ".join(command), flush=True)
    subprocess.run(command, cwd=ROOT, env=environment, check=True)


def csv_header(path: Path) -> set[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return set(next(csv.reader(handle)))


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the frozen two-cohort analysis in the submitted order.")
    parser.add_argument("--config", default="config.local.json")
    parser.add_argument("--check-only", action="store_true", help="Check files and software without analyzing patient data")
    args = parser.parse_args()

    config_path = resolved(args.config)
    if not config_path.exists():
        raise SystemExit(f"Configuration file not found: {config_path}\nCopy config.example.json to config.local.json and edit it first.")
    config = json.loads(config_path.read_text(encoding="utf-8"))
    inspire_version = str(config.get("study", {}).get("inspire_version", ""))
    if inspire_version != "1.0":
        raise SystemExit("The submitted public workflow is locked to INSPIRE version 1.0. Set study.inspire_version to '1.0'.")
    inputs = config.get("inputs", {})
    optional = config.get("optional_stages", {})
    output_root = resolved(config.get("outputs", {}).get("root", "derived/final_analysis"))

    required = [
        "mover_outcome_input", "inspire_outcome_input", "mover_labs_input",
        "inspire_labs_input", "mover_pre_bmi_input", "inspire_pre_bmi_input",
        "mover_medication_input", "inspire_medication_input",
    ]
    if optional.get("phenotype_recognition", True):
        required.extend(["mover_early_feature_input", "inspire_early_feature_input"])
    if optional.get("rcri_recovery_sensitivity", False):
        required.append("mover_rcri_recovery_input")

    missing_configuration = [key for key in required if not str(inputs.get(key, "")).strip()]
    missing_files = [
        (key, resolved(str(inputs[key]))) for key in required
        if str(inputs.get(key, "")).strip() and not resolved(str(inputs[key])).exists()
    ]
    print("Repository:", ROOT)
    print("INSPIRE release: 1.0")
    print("Output root:", output_root)
    if missing_configuration:
        print("Unset required entries:", ", ".join(missing_configuration))
    for key, path in missing_files:
        print(f"Missing file for {key}: {path}")
    header_problems: list[str] = []
    for key, expected in REQUIRED_HEADERS.items():
        value = str(inputs.get(key, "")).strip()
        if not value:
            continue
        path = resolved(value)
        if not path.exists():
            continue
        absent = sorted(expected.difference(csv_header(path)))
        if absent:
            header_problems.append(f"{key}: missing columns {', '.join(absent)}")
    for problem in header_problems:
        print("Header problem:", problem)
    if args.check_only:
        if missing_configuration or missing_files or header_problems:
            raise SystemExit("Configuration check failed. Correct the items above before running the analysis.")
        print("PASS: configuration, input files, and required CSV headers are present.")
        return
    if missing_configuration or missing_files or header_problems:
        raise SystemExit("Configuration is incomplete. No analysis was started.")

    python = config.get("software", {}).get("python", sys.executable)
    rscript = config.get("software", {}).get("rscript", "Rscript")
    mace_dir = output_root / "01_harmonized_mace"
    bmi_audit_dir = output_root / "02_bmi_audit"
    bmi_corrected_dir = output_root / "03_bmi_corrected_inputs"
    analysis_dir = output_root / "04_models_and_supplementary_analyses"
    figure_dir = output_root / "05_figures"
    for path in (mace_dir, bmi_audit_dir, bmi_corrected_dir, analysis_dir, figure_dir):
        path.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment.update({
        "PROJECT_ROOT": str(ROOT),
        "MOVER_OUTCOME_INPUT": str(resolved(inputs["mover_outcome_input"])),
        "INSPIRE_OUTCOME_INPUT": str(resolved(inputs["inspire_outcome_input"])),
        "MOVER_LABS_INPUT": str(resolved(inputs["mover_labs_input"])),
        "INSPIRE_LABS_INPUT": str(resolved(inputs["inspire_labs_input"])),
        "MACE_OUTPUT_DIR": str(mace_dir),
        "MOVER_PRE_BMI_INPUT": str(resolved(inputs["mover_pre_bmi_input"])),
        "INSPIRE_PRE_BMI_INPUT": str(resolved(inputs["inspire_pre_bmi_input"])),
        "BMI_AUDIT_OUT": str(bmi_audit_dir),
        "HARMONIZED_MACE_DIR": str(mace_dir),
        "BMI_AUDIT_DIR": str(bmi_audit_dir),
        "BMI_CORRECTED_OUT": str(bmi_corrected_dir),
        "MOVER_MEDICATION_INPUT": str(resolved(inputs["mover_medication_input"])),
        "INSPIRE_MEDICATION_INPUT": str(resolved(inputs["inspire_medication_input"])),
        "ANALYSIS_OUT": str(analysis_dir),
        "FEATURE_SPEC_INPUT": str(ROOT / "model" / "FULL_MODEL_FEATURE_SPECIFICATION.csv"),
        "FIGURE_OUT": str(figure_dir),
    })

    run([python, "analysis/10_build_harmonized_mace_72h.py"], environment)
    run([rscript, "analysis/00_bmi_quality_control.R"], environment)
    run([rscript, "analysis/01_build_bmi_corrected_inputs.R"], environment)

    environment["MOVER_INPUT"] = str(bmi_corrected_dir / "MOVER_MODEL_INPUT_BMI_CORRECTED.csv")
    environment["INSPIRE_INPUT"] = str(bmi_corrected_dir / "INSPIRE_MODEL_INPUT_BMI_CORRECTED.csv")
    run([rscript, "analysis/02_primary_outcome_models.R"], environment)
    run([rscript, "analysis/03_continuous_map_models.R"], environment)
    run([rscript, "analysis/04_hypertension_medication_analysis.R"], environment)

    if optional.get("phenotype_recognition", True):
        environment["MOVER_EARLY_FEATURE_INPUT"] = str(resolved(inputs["mover_early_feature_input"]))
        environment["INSPIRE_EARLY_FEATURE_INPUT"] = str(resolved(inputs["inspire_early_feature_input"]))
        run([rscript, "analysis/05_phenotype_recognition.R"], environment)
        environment["RECOGNITION_INPUT"] = str(analysis_dir / "recognition" / "FOLD_SAFE_RECOGNITION_PERFORMANCE.csv")
        if optional.get("figures", True):
            run([rscript, "analysis/08_plot_early_recognition.R"], environment)

    if optional.get("rcri_recovery_sensitivity", False):
        environment["MOVER_RCRI_RECOVERY_INPUT"] = str(resolved(inputs["mover_rcri_recovery_input"]))
        run([rscript, "analysis/06_lab_evaluable_sensitivity.R"], environment)
    if optional.get("repeated_operation_and_missing_data_sensitivity", True):
        run([rscript, "analysis/07_repeated_operation_and_missing_data_sensitivity.R"], environment)
    run([rscript, "analysis/09_feature_reduction_audit.R"], environment)
    print("\nAnalysis complete:", output_root)


if __name__ == "__main__":
    main()
