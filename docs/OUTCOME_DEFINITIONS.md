# Final Outcome Definitions and Source Mapping

This document describes the outcome logic frozen for release `v1.0.0`. The two databases have different structures, so the same clinical outcome was ascertained from all prespecified sources available within each database. A qualifying finding from any component source classified the operation as having the outcome.

## Major adverse cardiac events

MACE comprised documented postoperative myocardial infarction, cardiac arrest, or stroke, or an acute myocardial-injury proxy identified from perioperative troponin measurements. The laboratory component used an assay-specific postoperative elevation together with a dynamic increase from the last available preoperative value within the prespecified 72-hour window. MOVER additionally used structured postoperative complication records; INSPIRE additionally used postoperative ICD-10 diagnoses recorded between operating-room exit and hospital discharge. The myocardial-injury component was treated as part of MACE and not as a separate primary outcome.

## Acute kidney injury

AKI was identified using creatinine-based KDIGO laboratory criteria: an increase of at least 0.3 mg/dL within 48 hours or at least 1.5 times the preoperative baseline within 7 days. MOVER structured postoperative complication records and INSPIRE postoperative ICD-10 code N17 supplemented the laboratory definition. Urine-output criteria were not used because comparable urine-output ascertainment was unavailable.

## Severe acute liver injury

Severe acute liver injury required the prespecified stringent biochemical pattern or a qualifying structured/diagnostic record. MOVER combined postoperative liver laboratory results with structured postoperative complication records. INSPIRE combined laboratory results with postoperative ICD-10 codes K71 or K72; these code groups were required to be absent during the preceding 365 days. This definition was designed to identify marked acute liver injury and should not be interpreted as capturing mild postoperative aminotransferase elevation.

## Pulmonary complications

Pulmonary complications were identified from the prespecified postoperative pulmonary criteria available in each database, supplemented by MOVER structured postoperative complication records or INSPIRE postoperative ICD-10 diagnoses. Because source detail differs between databases, center-specific counts and association estimates are reported separately.

## In-hospital death

In-hospital death was derived from the discharge disposition and death information available within the index hospitalization.

## Classification when a component source was unavailable

Laboratory nonmeasurement alone did not define the absence of an outcome. An operation was classified as positive when any qualifying available component was positive. If no qualifying evidence was found in the available laboratory, structured-complication, diagnostic, or disposition sources, it was classified as having no documented event. Laboratory-evaluable sensitivity analyses restricted selected analyses to operations with measurements sufficient to apply the relevant laboratory definition.

The executable code and aggregate audits in `analysis/10_build_harmonized_mace_72h.py` and `results/` are authoritative for the frozen release. No patient-level results are included in this repository.
