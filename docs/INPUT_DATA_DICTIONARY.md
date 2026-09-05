# Input Data Dictionary and Local Handoff Contract

The public repository does not contain patient-level data. The analysis scripts expect locally prepared operation-level tables and source-specific evidence tables. Column names below are the executable handoff contract; database-native extraction may use different source names before harmonization.

## Long-form MAP trajectory handoff

The generic pipeline expects one row per eligible MAP measurement:

| Field | Meaning |
|---|---|
| `operation_id` | Unique operation identifier |
| `patient_id` | Patient identifier; used only for local repeated-operation analyses |
| `time` | Numeric minutes or a parseable date-time |
| `map` | Numeric MAP in mm Hg |
| `or_duration_min` | Operating-room duration in minutes |

The pipeline sets values outside 30-200 mm Hg aside, combines duplicate timestamps by their median, orders observations, calculates the largest adjacent gap, and calculates MAP-to-OR coverage.

## Common operation-level fields

- Operation identifier: `LOG_ID` in MOVER; `op_id` in INSPIRE.
- Patient identifier for repeated-operation sensitivity: `MRN` in MOVER; `subject_id` in INSPIRE.
- Frozen phenotype: `Cluster_GT60` coded 1, 2, or 3.
- Preoperative covariates: age, sex, BMI, ASA physical status, surgical type, primary hypertension, RCRI, and the 4 antihypertensive drug-class flags.
- Outcomes: final MACE, AKI, severe acute liver injury, pulmonary complications, and in-hospital death.
- The 20 frozen MAP features listed in `model/FULL_MODEL_FEATURE_SPECIFICATION.csv`.

The final operation-level input must also retain operating-room entry and exit times and hospital discharge time for postoperative-window construction.

## BMI source fields

- MOVER: `Height_m`, `Weight_kg`, `BMI`, `Cluster_GT60`.
- INSPIRE: raw `height`, raw `weight`, recorded `BMI`, and `Cluster_GT60`.

## MACE laboratory fields

- MOVER laboratory file: `LOG_ID`, `MRN`, `Lab Name`, `Observation Value`, `Measurement Units`, `Reference Range`, and `Collection Datetime`.
- INSPIRE laboratory file: `subject_id`, `chart_time`, `item_name`, and `value`.
- Operation timing: operating-room entry, operating-room exit, and discharge time.
- Documented-event component: MOVER structured postoperative complications; INSPIRE postoperative ICD-10 diagnoses for myocardial infarction, cardiac arrest, or stroke.

For INSPIRE version 1.0, laboratory values are read from `labs.csv`; operation timing and patient linkage are provided by the locally harmonized operation-level input. Troponin I and T values are converted from micrograms/L to ng/L inside the executable MACE script.

## Antihypertensive evidence files

The primary models use 4 binary indicators for recorded administration between hospital admission and operating-room entry: ACE inhibitor or ARB, beta-blocker, calcium channel blocker, and diuretic. The environment variables `MOVER_MEDICATION_INPUT` and `INSPIRE_MEDICATION_INPUT` should point to the prepared evidence files.

## Early-recognition files

The 15-, 30-, and 60-minute analyses require source-specific early MAP summary tables. They must contain the operation identifier, an evaluability flag for each landmark, and the prefixed early MAP features expected by `analysis/05_phenotype_recognition.R`.

## Files intentionally not published

Do not publish any table containing operation or patient identifiers, raw timestamps, raw laboratory rows, diagnosis rows, medication rows, or model predictions at the operation level. The repository's `results/` directory is restricted to aggregate, nonidentifiable summaries.
