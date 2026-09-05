# Reproducibility Guide

## Scope

The repository separates 3 reproducibility layers:

1. **Trajectory layer:** create the 91 outcome-blind MAP descriptors from a harmonized long-form trajectory table and derive the frozen 20-feature phenotype model.
2. **Analysis layer:** reconstruct the harmonized MACE component, apply BMI quality control, fit the primary and supplementary models, and evaluate phenotype recognition.
3. **Reference layer:** verify the dimensions of the frozen model and the nonidentifiable aggregate outputs distributed with release `v1.0.0`.

The source repositories cannot be redistributed. Source-specific extraction and terminology harmonization must therefore be performed locally under the MOVER and INSPIRE data-use terms. The expected handoff files are documented in `INPUT_DATA_DICTIONARY.md`.

## Frozen study version

- Derivation: MOVER.
- External validation: **INSPIRE version 1.0**.
- Final cohorts: 21,164 MOVER operations and 85,064 INSPIRE operations.
- Representation: 20 MAP features, 5 principal components, 3 k-means centroids.
- External transport: MOVER transformations and centroids applied without refitting, rescaling, or reclustering.

See `INSPIRE_VERSION_RATIONALE.md` for the release decision.

## Software

- Python 3.11 or later.
- R 4.4.1.
- Python packages in `requirements.txt`.
- R packages in `requirements-r.txt`.

Install once:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements-dev.txt
Rscript scripts\install_r_packages.R
```

## Layer 1: MAP trajectory and frozen phenotype workflow

Prepare one long-form CSV per cohort with at least:

```text
operation_id,patient_id,time,map,or_duration_min
```

Generate the 91 descriptors and temporal-quality audit:

```powershell
python pipeline\01_compute_map_descriptors.py `
  --input "D:\local_data\mover_map_long.csv" `
  --output "D:\local_analysis\mover_91_descriptors.csv"

python pipeline\01_compute_map_descriptors.py `
  --input "D:\local_data\inspire_1_0_map_long.csv" `
  --output "D:\local_analysis\inspire_1_0_91_descriptors.csv"
```

Reproduce the MOVER derivation model:

```powershell
python pipeline\02_fit_derivation_model.py `
  --input "D:\local_analysis\mover_91_descriptors.csv" `
  --output-dir "D:\local_analysis\derived_model"
```

For the submitted analysis, external validation must use the already frozen model in `model/`:

```powershell
python pipeline\03_apply_frozen_model.py `
  --input "D:\local_analysis\inspire_1_0_91_descriptors.csv" `
  --output "D:\local_analysis\inspire_1_0_frozen_assignments.csv" `
  --model-dir model
```

Do not fit a new PCA or k-means model in INSPIRE.

## Layer 2: final outcome and statistical workflow

Copy the example configuration:

```powershell
Copy-Item config.example.json config.local.json
```

Edit only `config.local.json`; it is ignored by Git. Point each entry to the locally prepared files described in `INPUT_DATA_DICTIONARY.md`.

Check the configuration:

```powershell
python run_all.py --config config.local.json --check-only
```

Run the locked sequence:

```powershell
python run_all.py --config config.local.json
```

Execution order:

1. Harmonized 72-hour MACE construction.
2. BMI unit correction and plausibility filtering.
3. Construction of BMI-corrected model inputs.
4. Unadjusted, primary preoperatively adjusted, and frailty sensitivity models.
5. Per-1-SD associations for the 20 MAP features with MACE and AKI.
6. Hypertension and antihypertensive-treatment analyses.
7. Preoperative and 15-, 30-, and 60-minute phenotype-recognition analyses.
8. Repeated-operation, clustered-SE, reduced-adjustment, and missing-data sensitivity analyses.
9. The 91-to-20 feature audit.

All patient-level outputs are written below the configured output root, whose default is `derived/final_analysis`; that directory is ignored by Git.

## Layer 3: public reference checks

These checks require no patient-level data:

```powershell
python -m pytest tests -q
python scripts\verify_reference_outputs.py
python scripts\audit_public_release.py
```

Expected cohort and phenotype counts:

| Cohort | Total | Labile Hypotension | Stable Hemodynamics | Labile Hypertension |
|---|---:|---:|---:|---:|
| MOVER | 21,164 | 1,775 | 15,767 | 3,622 |
| INSPIRE 1.0 | 85,064 | 6,814 | 62,418 | 15,832 |

Expected primary complete-case denominators after the final BMI rule are 13,724 for MOVER and 83,437 for INSPIRE.

## Reproducibility boundaries

- The public package does not redistribute source or patient-level derived data.
- `results/` contains aggregate reference summaries only.
- MOVER and INSPIRE source schemas differ; local source extraction precedes the common workflow.
- The frozen classifier reproduces phenotype assignment. It does not produce individualized outcome probabilities or treatment advice.
