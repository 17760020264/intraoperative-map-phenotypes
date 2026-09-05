# Rationale for INSPIRE Version 1.0

The external-validation cohort in the submitted analysis was constructed from **INSPIRE version 1.0** (PhysioNet DOI: 10.13026/jyzb-ez61). The MOVER-derived preprocessing parameters, principal-component loadings, cluster centroids, source mappings, cohort counts, and reference results in release `v1.0.0` are therefore locked to that database release.

INSPIRE releases are not treated as interchangeable snapshots. Later releases may contain changes in file organization, variable availability, preprocessing, or the distribution of recorded vital signs. Replacing the validation source after model locking could alter cohort construction and the availability of threshold-based MAP descriptors, and would constitute a version-specific revalidation rather than a clerical update.

Version 1.0 was retained for 3 reasons:

1. It is the release on which the external cohort, 20-feature transport, outcome harmonization, and manuscript results were executed.
2. It preserves the exact data representation required by the frozen validation workflow, including the observed range needed for the prespecified hypotension and hypertension descriptors.
3. Its accession and DOI allow the analyzed source version to be identified and retrieved independently, subject to PhysioNet access requirements.

Exploratory code-migration checks performed with later INSPIRE releases were not part of the external-validation analysis and are not reported as study results. Any future use of another release should be labeled with that exact version and should repeat the cohort, feature-availability, transportability, and outcome audits before comparison with the locked version 1.0 results.
