suppressPackageStartupMessages(library(data.table))

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
source_dir <- Sys.getenv("HARMONIZED_MACE_DIR", unset=file.path(root, "derived", "harmonized_mace_72h"))
audit_dir <- Sys.getenv("BMI_AUDIT_DIR", unset=file.path(root, "derived", "bmi_audit"))
out_dir <- Sys.getenv(
  "BMI_CORRECTED_OUT",
  unset = file.path(root, "derived", "bmi_corrected")
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

num <- function(x) suppressWarnings(as.numeric(as.character(x)))

m <- fread(file.path(source_dir, "MOVER_MODEL_INPUT_REVISED_MACE.csv"), showProgress = FALSE)
i <- fread(file.path(source_dir, "INSPIRE_MODEL_INPUT_REVISED_MACE.csv"), showProgress = FALSE)
ma <- fread(file.path(audit_dir, "MOVER_BMI_CORRECTION_AUDIT.csv"), showProgress = FALSE)
ia <- fread(file.path(audit_dir, "INSPIRE_BMI_CORRECTION_AUDIT.csv"), showProgress = FALSE)

m[, LOG_ID := as.character(LOG_ID)]
i[, op_id := as.character(op_id)]
ma[, LOG_ID := as.character(LOG_ID)]
ia[, op_id := as.character(op_id)]

ma <- unique(ma[, .(LOG_ID, BMI_corrected = num(BMI_recalculated))], by = "LOG_ID")
ia <- unique(ia[, .(op_id, BMI_corrected = num(BMI_recalculated))], by = "op_id")

m <- merge(m, ma, by = "LOG_ID", all.x = TRUE, sort = FALSE)
i <- merge(i, ia, by = "op_id", all.x = TRUE, sort = FALSE)

m[, BMI_original_analysis := num(BMI)]
i[, BMI_original_analysis := num(Common_BMI)]

m[, BMI := BMI_corrected]
i[, `:=`(BMI = BMI_corrected, Common_BMI = BMI_corrected)]

# Preserve the finalized 72-hour harmonized MACE definition for every downstream script.
m[, Final_MACE_enhanced := num(MACE_harmonized_72h_flag)]
i[, MACE_final_flag := num(MACE_harmonized_72h_flag)]

m[, BMI_corrected := NULL]
i[, BMI_corrected := NULL]

m_out <- file.path(out_dir, "MOVER_MODEL_INPUT_BMI_CORRECTED.csv")
i_out <- file.path(out_dir, "INSPIRE_MODEL_INPUT_BMI_CORRECTED.csv")
fwrite(m, m_out, bom = TRUE)
fwrite(i, i_out, bom = TRUE)

audit <- rbindlist(list(
  data.table(
    Center = "MOVER", N = nrow(m),
    BMI_nonmissing_before = sum(!is.na(m$BMI_original_analysis)),
    BMI_nonmissing_after = sum(!is.na(m$BMI)),
    BMI_changed = sum(abs(m$BMI - m$BMI_original_analysis) > 1e-10, na.rm = TRUE),
    BMI_newly_missing = sum(!is.na(m$BMI_original_analysis) & is.na(m$BMI)),
    BMI_newly_recovered = sum(is.na(m$BMI_original_analysis) & !is.na(m$BMI))
  ),
  data.table(
    Center = "INSPIRE", N = nrow(i),
    BMI_nonmissing_before = sum(!is.na(i$BMI_original_analysis)),
    BMI_nonmissing_after = sum(!is.na(i$BMI)),
    BMI_changed = sum(abs(i$BMI - i$BMI_original_analysis) > 1e-10, na.rm = TRUE),
    BMI_newly_missing = sum(!is.na(i$BMI_original_analysis) & is.na(i$BMI)),
    BMI_newly_recovered = sum(is.na(i$BMI_original_analysis) & !is.na(i$BMI))
  )
), use.names = TRUE)
fwrite(audit, file.path(out_dir, "BMI_INPUT_CASCADE_AUDIT.csv"), bom = TRUE)

cat("Wrote BMI-corrected analysis inputs to:", out_dir, "\n")
print(audit)
