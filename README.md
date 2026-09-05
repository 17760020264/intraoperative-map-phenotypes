# Intraoperative Hemodynamic Phenotypes

Reproducible code and frozen model for the study **“Intraoperative Hemodynamic Phenotypes and Postoperative Outcomes in Noncardiac Surgery.”**

The analysis used the Medical Informatics Operating Room Vitals and Events Repository (MOVER) as the derivation cohort and **INSPIRE version 1.0** as the external-validation cohort. The phenotype model was developed without using postoperative outcomes and was transported to INSPIRE without refitting, rescaling, or reclustering.

## Frozen primary analysis

- Adults undergoing inpatient noncardiac, non-major-vascular surgery under general anesthesia.
- ASA physical status I-IV, hospital length of stay greater than 1 day, and operating-room duration greater than 60 minutes.
- Numeric intraoperative MAP restricted to 30-200 mm Hg.
- No interval greater than 15 minutes between adjacent MAP measurements.
- Analyzable MAP interval covering at least 70% of operating-room duration.
- Outcome-blind reduction of 91 MAP descriptors to 20 complementary features.
- MOVER median/interquartile-range scaling, 5 principal components (90.84% cumulative variance), and k-means with 3 clusters.
- Frozen transport to INSPIRE version 1.0 by nearest-centroid assignment.
- Phenotype labels: Labile Hypotension, Stable Hemodynamics, and Labile Hypertension.

## Repository contents

| Path | Purpose |
|---|---|
| `pipeline/` | Generic MAP quality control, 91-descriptor calculation, model derivation, and frozen external assignment |
| `analysis/` | BMI quality control, outcome construction, primary models, continuous-feature analyses, treatment analyses, recognition analyses, and sensitivity analyses |
| `model/` | Frozen 20-feature specification, MOVER scaling parameters, PCA loadings, and 3 centroids |
| `app/` | Dockerized bilingual research classifier |
| `results/` | Nonidentifiable reference summaries from the submitted analysis |
| `examples/` | Synthetic trajectory examples only; no patient records |
| `docs/` | Input specifications, outcome definitions, version rationale, reproducibility guide, and Chinese GitHub upload tutorial |
| `run_phenotype_pipeline.py` | One-command 91-descriptor calculation and frozen phenotype assignment for harmonized MAP trajectories |
| `run_all.py` | Configuration check and ordered execution of final outcome/statistical analysis stages |

## Data access and privacy

Patient-level data are **not** included and must never be committed to this repository. Researchers must obtain each database under its own access and data-use terms:

- [MOVER](https://mover.ics.uci.edu/), DOI: [10.24432/C5VS5G](https://doi.org/10.24432/C5VS5G)
- [INSPIRE version 1.0](https://physionet.org/content/inspire/1.0/), DOI: [10.13026/jyzb-ez61](https://doi.org/10.13026/jyzb-ez61)

The public workflow starts from locally stored source files or source-specific harmonized tables. See `docs/INPUT_DATA_DICTIONARY.md`. The `.gitignore` file blocks the usual raw-data, derived-data, secret, log, and model-object locations.

## Quick start

### 1. Install software

- Python 3.11 or later
- R 4.4.1
- Git
- Docker Desktop only if the local web classifier is required

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements-dev.txt
Rscript scripts/install_r_packages.R
```

### 2. Create a local configuration

```powershell
Copy-Item config.example.json config.local.json
```

Open `config.local.json` and replace every placeholder path with a local path. `config.local.json` is ignored by Git.

### 3. Validate the public package

This step does not need patient data:

```powershell
python -m pytest tests -q
python scripts/verify_reference_outputs.py
python scripts/audit_public_release.py
```

### 4. Run the final analysis

```powershell
python run_all.py --config config.local.json --check-only
python run_all.py --config config.local.json
```

The first command checks every required local input and CSV header before execution. Full preparation and execution instructions are in `docs/REPRODUCIBILITY_GUIDE.md`.

To reproduce MAP descriptor calculation and frozen phenotype assignment from harmonized long-form trajectories, use:

```powershell
python run_phenotype_pipeline.py `
  --mover-map "D:\local_data\mover_map_long.csv" `
  --inspire-map "D:\local_data\inspire_1_0_map_long.csv" `
  --output-dir "D:\local_analysis\phenotype_outputs"
```

## Research classifier

```powershell
cd app
docker build -t intraoperative-map-phenotype .
docker run --rm -p 7860:7860 intraoperative-map-phenotype
```

Open `http://localhost:7860`. The public bilingual implementation is available at [Hugging Face Spaces](https://huggingface.co/spaces/1449648578Zyc/intraoperative-map-phenotype). It is for research, education, and method reproduction; it is not a medical device or treatment recommendation system.

## Reference checks

| Cohort | Total | Labile Hypotension | Stable Hemodynamics | Labile Hypertension |
|---|---:|---:|---:|---:|
| MOVER | 21,164 | 1,775 | 15,767 | 3,622 |
| INSPIRE 1.0 | 85,064 | 6,814 | 62,418 | 15,832 |

After the final BMI quality-control rule, the primary complete-case adjusted denominators were 13,724 for MOVER and 83,437 for INSPIRE. Reference aggregate outputs are stored in `results/`.

## Versioning and citation

Use GitHub release tag `v1.0.0` for the submitted analysis. Do not overwrite a published release; publish corrections as a new semantic version. Replace the owner and DOI placeholders in `CITATION.cff` only after the GitHub repository and archived release exist.

Code is released under the MIT License. Dataset-specific terms continue to govern the source data.
