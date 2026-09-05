suppressPackageStartupMessages({
  library(data.table)
  library(sandwich)
  library(lmtest)
  library(mice)
})

root <- normalizePath(".", winslash="/", mustWork=TRUE)
indir <- Sys.getenv("HARMONIZED_MACE_DIR", unset=file.path(root, "derived", "harmonized_mace_72h"))
base <- file.path(root, "outputs", "OR_GT60_TWO_CENTER")
out <- Sys.getenv("ANALYSIS_OUT", unset=file.path(root, "work", "reviewer_requested_sensitivities"))
dir.create(out, recursive=TRUE, showWarnings=FALSE)

num <- function(x) suppressWarnings(as.numeric(x))
to_male <- function(x) {
  if (is.numeric(x)) return(num(x))
  z <- toupper(trimws(as.character(x)))
  fifelse(z %chin% c("M", "MALE", "1"), 1,
          fifelse(z %chin% c("F", "FEMALE", "0"), 0, NA_real_))
}
to_asa <- function(x) {
  z <- toupper(trimws(gsub("ASA", "", as.character(x), fixed=TRUE)))
  ans <- unname(c("I"=1,"II"=2,"III"=3,"IV"=4,"1"=1,"2"=2,"3"=3,"4"=4)[z])
  as.numeric(ans)
}

m0 <- fread(Sys.getenv("MOVER_INPUT", unset=file.path(indir, "MOVER_MODEL_INPUT_REVISED_MACE.csv")), showProgress=FALSE)
i0 <- fread(Sys.getenv("INSPIRE_INPUT", unset=file.path(indir, "INSPIRE_MODEL_INPUT_REVISED_MACE.csv")), showProgress=FALSE)
mmed <- fread(Sys.getenv("MOVER_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv")), showProgress=FALSE)
imed <- fread(Sys.getenv("INSPIRE_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv")), showProgress=FALSE)

mmed <- unique(mmed[, .(
  ID=as.character(LOG_ID), ACEI_ARB=num(ACEI_ARB_given_admission_to_or),
  Beta_blocker=num(Beta_blocker_given_admission_to_or),
  CCB=num(Calcium_channel_blocker_given_admission_to_or),
  Diuretic=num(Diuretic_given_admission_to_or)
)], by="ID")
imed <- unique(imed[, .(
  ID=as.character(op_id), ACEI_ARB=num(ACEI_ARB), Beta_blocker=num(Beta_blocker),
  CCB=num(CCB), Diuretic=num(Diuretic)
)], by="ID")

m <- m0[, .(
  ID=as.character(LOG_ID), PatientID=as.character(MRN), Time=as.character(IN_OR_DTTM), Center="MOVER",
  Cluster=num(Cluster_GT60), Age=num(Age), Male=to_male(Sex), BMI=num(BMI), ASA=to_asa(ASA),
  Surgical_type=as.character(Surgical_type), Hypertension=num(Essential_hypertension_flag), RCRI=num(RCRI_score_0_6),
  MACE=num(MACE_harmonized_72h_flag), AKI=num(SA_AKI), Severe_ALI=num(SA_ALI),
  Pulmonary=num(Pulmonary_enhanced_flag), Inhospital_death=num(SA_Inhospital_death)
)]
i <- i0[, .(
  ID=as.character(op_id), PatientID=as.character(subject_id), Time=num(orin_time), Center="INSPIRE",
  Cluster=num(Cluster_GT60), Age=num(Common_Age), Male=num(Common_Male), BMI=num(Common_BMI), ASA=to_asa(Common_ASA),
  Surgical_type=as.character(Common_Surgical_type), Hypertension=num(Common_Hypertension), RCRI=num(RCRI_score_0_6),
  MACE=num(MACE_harmonized_72h_flag), AKI=num(SA_AKI), Severe_ALI=num(SA_ALI),
  Pulmonary=num(Pulmonary_enhanced_flag), Inhospital_death=num(SA_Inhospital_death)
)]
m <- merge(m, mmed, by="ID", all.x=TRUE, sort=FALSE)
i <- merge(i, imed, by="ID", all.x=TRUE, sort=FALSE)

outcomes <- c("MACE", "AKI", "Severe_ALI", "Pulmonary", "Inhospital_death")
labels <- c(MACE="Major adverse cardiac events", AKI="Acute kidney injury",
            Severe_ALI="Severe acute liver injury", Pulmonary="Pulmonary complications",
            Inhospital_death="In-hospital death")
main_cov <- c("RCRI","Age","Male","BMI","ASA","Surgical_type","Hypertension","ACEI_ARB","Beta_blocker","CCB","Diuretic")
reduced_cov <- setdiff(main_cov, "RCRI")

for (dn in c("m", "i")) {
  d <- get(dn)
  for (v in c("ACEI_ARB","Beta_blocker","CCB","Diuretic")) d[is.na(get(v)), (v):=0]
  for (y in outcomes) d[is.na(get(y)), (y):=0]
  d[, Surgical_type := factor(trimws(Surgical_type))]
  d[, ClusterF := relevel(factor(Cluster, levels=c(1,2,3),
      labels=c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")),
      ref="Stable Hemodynamics")]
  assign(dn, d)
}

extract_terms <- function(fit, ct, center, outcome, analysis, n, events, patients) {
  rbindlist(lapply(c("Labile Hypotension", "Labile Hypertension"), function(lab) {
    term <- paste0("ClusterF", lab)
    b <- ct[term, 1]; se <- ct[term, 2]; p <- ct[term, 4]
    data.table(Center=center, Outcome=labels[[outcome]], Analysis=analysis,
               Comparison=paste0(lab, " vs Stable Hemodynamics"), Analysis_N=n,
               Events=events, Unique_patients=patients, OR=exp(b),
               CI_low=exp(b-1.96*se), CI_high=exp(b+1.96*se), P_value=p,
               OR_95CI=sprintf("%.2f (%.2f-%.2f)", exp(b), exp(b-1.96*se), exp(b+1.96*se)))
  }))
}

fit_model <- function(d, y, covs, analysis, patient_cluster=FALSE) {
  vars <- c(y, "ClusterF", covs, "PatientID")
  z <- d[complete.cases(d[, ..vars]) & get(y) %in% c(0,1)]
  f <- as.formula(paste(y, "~", paste(c("ClusterF", covs), collapse="+")))
  fit <- glm(f, data=z, family=binomial())
  if (patient_cluster) {
    V <- vcovCL(fit, cluster=z$PatientID, type="HC0")
    ct <- coeftest(fit, vcov.=V)
  } else {
    ct <- coef(summary(fit))
  }
  extract_terms(fit, ct, unique(d$Center), y, analysis, nrow(z), sum(z[[y]]==1), uniqueN(z$PatientID))
}

first_operation <- function(d) {
  z <- copy(d)
  if (unique(z$Center)=="MOVER") {
    z[, OrderTime := as.POSIXct(Time, tz="UTC")]
  } else {
    z[, OrderTime := num(Time)]
  }
  setorder(z, PatientID, OrderTime, ID, na.last=TRUE)
  z[, .SD[1], by=PatientID]
}

rows <- list(); k <- 1L
for (d in list(m, i)) {
  first <- first_operation(d)
  for (y in outcomes) {
    rows[[k]] <- fit_model(d, y, main_cov, "Primary complete-case; model-based SE", FALSE); k <- k+1L
    rows[[k]] <- fit_model(d, y, main_cov, "Primary complete-case; patient-clustered robust SE", TRUE); k <- k+1L
    rows[[k]] <- fit_model(first, y, main_cov, "First eligible operation per patient", FALSE); k <- k+1L
    rows[[k]] <- fit_model(d, y, reduced_cov, "Reduced adjustment excluding RCRI", FALSE); k <- k+1L
  }
}
sens <- rbindlist(rows)
fwrite(sens, file.path(out, "PATIENT_CLUSTER_AND_REDUCED_MODEL_SENSITIVITY.csv"), bom=TRUE)

# Multiple imputation sensitivity for MOVER, the cohort with substantial RCRI/BMI missingness.
imp_cols <- c("ClusterF", "RCRI", "Age", "Male", "BMI", "ASA", "Surgical_type", "Hypertension",
              "ACEI_ARB", "Beta_blocker", "CCB", "Diuretic", outcomes)
impdat <- as.data.frame(m[, ..imp_cols])
impdat$Surgical_type <- droplevels(factor(impdat$Surgical_type))
impdat$ClusterF <- droplevels(factor(impdat$ClusterF))
method <- make.method(impdat)
method[] <- ""
method["RCRI"] <- "pmm"
method["BMI"] <- "pmm"
method["ASA"] <- "pmm"
pred <- make.predictorMatrix(impdat)
diag(pred) <- 0
pred[, setdiff(names(impdat), c("RCRI", "BMI", "ASA"))] <- 0
pred[c("RCRI", "BMI", "ASA"), ] <- 1
pred[c("RCRI", "BMI", "ASA"), c("RCRI", "BMI", "ASA")] <- 0
set.seed(20260825)
imp <- mice(impdat, m=20, maxit=5, method=method, predictorMatrix=pred, printFlag=FALSE, seed=20260825)

mi_rows <- list(); j <- 1L
for (y in outcomes) {
  f <- as.formula(paste(y, "~", paste(c("ClusterF", main_cov), collapse="+")))
  fits <- lapply(seq_len(imp$m), function(ii) glm(f, data=complete(imp, ii), family=binomial()))
  pooled <- summary(pool(as.mira(fits)), conf.int=TRUE, exponentiate=TRUE)
  for (lab in c("Labile Hypotension", "Labile Hypertension")) {
    term <- paste0("ClusterF", lab)
    rr <- pooled[pooled$term==term, ]
    mi_rows[[j]] <- data.table(Center="MOVER", Outcome=labels[[y]],
      Analysis="Multiple imputation (20 datasets)", Comparison=paste0(lab, " vs Stable Hemodynamics"),
      Analysis_N=nrow(m), Events=sum(m[[y]]==1), Unique_patients=uniqueN(m$PatientID),
      OR=rr$estimate, CI_low=rr$`2.5 %`, CI_high=rr$`97.5 %`, P_value=rr$p.value,
      OR_95CI=sprintf("%.2f (%.2f-%.2f)", rr$estimate, rr$`2.5 %`, rr$`97.5 %`))
    j <- j+1L
  }
}
mi <- rbindlist(mi_rows)
fwrite(mi, file.path(out, "MOVER_MULTIPLE_IMPUTATION_SENSITIVITY.csv"), bom=TRUE)

patient_summary <- rbindlist(lapply(list(m,i), function(d) {
  tab <- d[, .N, by=PatientID]
  data.table(Center=unique(d$Center), Operations=nrow(d), Unique_patients=nrow(tab),
             Patients_with_multiple_operations=sum(tab$N>1),
             Percent_patients_with_multiple_operations=100*mean(tab$N>1),
             Operations_from_repeat_patients=sum(tab[N>1, N]),
             Percent_operations_from_repeat_patients=100*sum(tab[N>1, N])/nrow(d),
             Maximum_operations_per_patient=max(tab$N))
}))
fwrite(patient_summary, file.path(out, "REPEATED_OPERATION_AUDIT.csv"), bom=TRUE)

miss <- rbindlist(lapply(list(m,i), function(d) rbindlist(lapply(main_cov, function(v) {
  data.table(Center=unique(d$Center), Variable=v, Missing_N=sum(is.na(d[[v]])), Missing_percent=100*mean(is.na(d[[v]])))
}))))
fwrite(miss, file.path(out, "COVARIATE_MISSINGNESS_AUDIT.csv"), bom=TRUE)

cat("\nRepeated-operation audit\n"); print(patient_summary)
cat("\nMOVER multiple-imputation phenotype results\n"); print(mi)
cat("\nPatient-clustered and first-operation sensitivity results\n");
print(sens[Analysis %chin% c("Primary complete-case; patient-clustered robust SE", "First eligible operation per patient")])
