suppressPackageStartupMessages(library(data.table))

root <- normalizePath(".", winslash = "/", mustWork = TRUE)
base <- file.path(root, "outputs", "OR_GT60_TWO_CENTER")
out <- Sys.getenv("ANALYSIS_OUT", unset=file.path(root, "work", "updated_results_analysis"))
audit <- Sys.getenv("RCRI_AUDIT_DIR", unset=file.path(root, "derived", "rcri_audit"))
num <- function(x) suppressWarnings(as.numeric(as.character(x)))
to_male <- function(x) {
  z <- toupper(trimws(as.character(x)))
  fifelse(z %chin% c("M", "MALE", "1"), 1, fifelse(z %chin% c("F", "FEMALE", "0"), 0, NA_real_))
}
to_asa <- function(x) {
  z <- toupper(trimws(gsub("ASA", "", as.character(x), fixed = TRUE)))
  as.numeric(unname(c("I"=1,"II"=2,"III"=3,"IV"=4,"1"=1,"2"=2,"3"=3,"4"=4)[z]))
}
fmtp <- function(p) ifelse(is.na(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))

m0 <- fread(Sys.getenv("MOVER_INPUT", unset=file.path(base, "MOVER_GT60_FINAL_OUTCOMES_V2.csv")), showProgress = FALSE)
i0 <- fread(Sys.getenv("INSPIRE_INPUT", unset=file.path(base, "INSPIRE_GT60_FINAL_OUTCOMES_V4_RCRI_FRAILTY.csv")), showProgress = FALSE)
rec <- fread(Sys.getenv("MOVER_RCRI_RECOVERY_INPUT", unset=file.path(audit, "MOVER_RCRI_7day_recovered_operations.csv")), showProgress = FALSE)
m0[, LOG_ID := as.character(LOG_ID)]
rec[, LOG_ID := as.character(LOG_ID)]
rec <- unique(rec[, .(LOG_ID, recovered_renal_flag = num(recovered_renal_flag))], by = "LOG_ID")
if ("recovered_renal_flag" %in% names(m0)) m0[, recovered_renal_flag := NULL]
m0 <- merge(m0, rec, by = "LOG_ID", all.x = TRUE, sort = FALSE)
m0[is.na(num(RCRI_preop_creatinine_gt2_flag)) & !is.na(recovered_renal_flag), RCRI_preop_creatinine_gt2_flag := recovered_renal_flag]
components <- c("RCRI_high_risk_surgery_flag", "RCRI_ischemic_heart_disease_flag", "RCRI_heart_failure_flag", "RCRI_cerebrovascular_disease_flag", "RCRI_insulin_therapy_flag", "RCRI_preop_creatinine_gt2_flag")
m0[, RCRI_score_0_6 := {mat <- as.matrix(.SD); storage.mode(mat) <- "numeric"; as.numeric(rowSums(mat, na.rm = FALSE))}, .SDcols = components]

mmed <- fread(Sys.getenv("MOVER_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv")), showProgress = FALSE)
imed <- fread(Sys.getenv("INSPIRE_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv")), showProgress = FALSE)
mmed <- unique(mmed[, .(ID=as.character(LOG_ID), ACEI_ARB=num(ACEI_ARB_given_admission_to_or), Beta_blocker=num(Beta_blocker_given_admission_to_or), CCB=num(Calcium_channel_blocker_given_admission_to_or), Diuretic=num(Diuretic_given_admission_to_or))], by="ID")
imed <- unique(imed[, .(ID=as.character(op_id), ACEI_ARB=num(ACEI_ARB), Beta_blocker=num(Beta_blocker), CCB=num(CCB), Diuretic=num(Diuretic))], by="ID")

m <- m0[, .(ID=as.character(LOG_ID), Center="MOVER", Cluster=num(Cluster_GT60), Age=num(Age), Male=to_male(Sex), BMI=num(BMI), ASA=to_asa(ASA), Surgical_type=as.character(Surgical_type), Hypertension=num(Essential_hypertension_flag), RCRI=num(RCRI_score_0_6), AKI=num(AKI_combined_flag), ALI=num(ALI_combined_strict_flag))]
i <- i0[, .(ID=as.character(op_id), Center="INSPIRE", Cluster=num(Cluster_GT60), Age=num(Common_Age), Male=num(Common_Male), BMI=num(Common_BMI), ASA=to_asa(Common_ASA), Surgical_type=as.character(Common_Surgical_type), Hypertension=num(Common_Hypertension), RCRI=num(RCRI_score_0_6), AKI=num(SA_AKI), ALI=num(SA_ALI))]
m <- merge(m, mmed, by="ID", all.x=TRUE, sort=FALSE)
i <- merge(i, imed, by="ID", all.x=TRUE, sort=FALSE)

for (nm in c("m", "i")) {
  d <- get(nm)
  for (v in c("ACEI_ARB", "Beta_blocker", "CCB", "Diuretic")) d[is.na(get(v)), (v) := 0]
  d[, Surgical_type := factor(trimws(Surgical_type))]
  d[, ClusterF := relevel(factor(Cluster, levels=c(1,2,3), labels=c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")), ref="Stable Hemodynamics")]
  assign(nm, d)
}

covs <- c("RCRI","Age","Male","BMI","ASA","Surgical_type","Hypertension","ACEI_ARB","Beta_blocker","CCB","Diuretic")
labels <- c(AKI="Acute kidney injury", ALI="Severe acute liver injury")
rows <- list(); ix <- 1
for (d in list(m, i)) for (y in c("AKI", "ALI")) {
  vars <- c(y, "ClusterF", covs)
  z <- d[complete.cases(d[, ..vars]) & get(y) %in% c(0,1)]
  fit <- glm(as.formula(paste(y, "~ ClusterF +", paste(covs, collapse="+"))), data=z, family=binomial())
  sm <- coef(summary(fit))
  for (lab in c("Labile Hypotension", "Labile Hypertension")) {
    term <- paste0("ClusterF", lab)
    est <- sm[term, "Estimate"]; se <- sm[term, "Std. Error"]; p <- sm[term, "Pr(>|z|)"]
    rows[[ix]] <- data.table(
      Center=unique(z$Center), Outcome=unname(labels[y]), Comparison=paste0(lab, " vs Stable Hemodynamics"),
      Analysis_N=nrow(z), Events=sum(z[[y]] == 1), OR=exp(est), CI_low=exp(est-1.96*se), CI_high=exp(est+1.96*se),
      P_value=p, OR_95CI=sprintf("%.2f (%.2f-%.2f)", exp(est), exp(est-1.96*se), exp(est+1.96*se)), P_formatted=fmtp(p)
    )
    ix <- ix + 1
  }
}
ans <- rbindlist(rows)
fwrite(ans, file.path(out, "SUPPLEMENTARY_TABLE_S5E_LAB_EVALUABLE_OUTCOME_SENSITIVITY.csv"), bom=TRUE)
print(ans)
