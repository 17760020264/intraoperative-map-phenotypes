suppressPackageStartupMessages({
  library(data.table)
})

root <- normalizePath(".", winslash="/", mustWork=TRUE)
base <- file.path(root, "outputs", "OR_GT60_TWO_CENTER")
out <- Sys.getenv("ANALYSIS_OUT", unset=file.path(root, "work", "final_submission_analysis"))
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

m0 <- fread(Sys.getenv("MOVER_INPUT", unset=file.path(base, "MOVER_GT60_FINAL_OUTCOMES_V2.csv")), showProgress=FALSE)
i0 <- fread(Sys.getenv("INSPIRE_INPUT", unset=file.path(base, "INSPIRE_GT60_FINAL_OUTCOMES_V4_RCRI_FRAILTY.csv")), showProgress=FALSE)
mmed <- fread(Sys.getenv("MOVER_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv")), showProgress=FALSE)
imed <- fread(Sys.getenv("INSPIRE_MEDICATION_INPUT", unset=file.path(base, "PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE", "INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv")), showProgress=FALSE)

mmed <- unique(mmed[, .(
  ID=as.character(LOG_ID),
  ACEI_ARB=num(ACEI_ARB_given_admission_to_or),
  Beta_blocker=num(Beta_blocker_given_admission_to_or),
  CCB=num(Calcium_channel_blocker_given_admission_to_or),
  Diuretic=num(Diuretic_given_admission_to_or)
)], by="ID")
imed <- unique(imed[, .(
  ID=as.character(op_id),
  ACEI_ARB=num(ACEI_ARB),
  Beta_blocker=num(Beta_blocker),
  CCB=num(CCB),
  Diuretic=num(Diuretic)
)], by="ID")

m <- m0[, .(
  ID=as.character(LOG_ID), Center="MOVER", Cluster=num(Cluster_GT60),
  Age=num(Age), Male=to_male(Sex), BMI=num(BMI), ASA=to_asa(ASA),
  Surgical_type=as.character(Surgical_type), Hypertension=num(Essential_hypertension_flag),
  RCRI=num(RCRI_score_0_6), Frailty=num(Modified_frailty_score_0_5),
  MACE=num(Final_MACE_enhanced), AKI=num(AKI_combined_flag), ALI=num(ALI_combined_strict_flag),
  Pulmonary=num(Pulmonary_enhanced_flag), Inhospital_death=num(In_hospital_death_flag),
  ICU=num(Any_ICU_admission_flag), Nonroutine_discharge=num(Non_routine_discharge_strict_flag),
  Postoperative_LOS_h=num(Postoperative_LOS_h), Total_LOS_d=num(Total_LOS_d)
)]
i <- i0[, .(
  ID=as.character(op_id), Center="INSPIRE", Cluster=num(Cluster_GT60),
  Age=num(Common_Age), Male=num(Common_Male), BMI=num(Common_BMI), ASA=to_asa(Common_ASA),
  Surgical_type=as.character(Common_Surgical_type), Hypertension=num(Common_Hypertension),
  RCRI=num(RCRI_score_0_6), Frailty=num(Modified_frailty_score_0_5),
  MACE=num(MACE_final_flag), AKI=num(SA_AKI), ALI=num(SA_ALI),
  Pulmonary=num(Pulmonary_enhanced_flag), Inhospital_death=num(SA_Inhospital_death),
  ICU=num(SA_ICU_admission), Nonroutine_discharge=num(SA_Nonroutine_discharge),
  Postoperative_LOS_h=num(SA_Postoperative_LOS_h), Total_LOS_d=num(SA_Total_LOS_d)
)]
m <- merge(m, mmed, by="ID", all.x=TRUE, sort=FALSE)
i <- merge(i, imed, by="ID", all.x=TRUE, sort=FALSE)
for (dname in c("m","i")) {
  d <- get(dname)
  for (v in c("ACEI_ARB","Beta_blocker","CCB","Diuretic")) d[is.na(get(v)), (v):=0]
  d[, Surgical_type := factor(trimws(Surgical_type))]
  d[, ClusterF := relevel(factor(Cluster, levels=c(1,2,3), labels=c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")), ref="Stable Hemodynamics")]
  assign(dname,d)
}

main_cov <- c("RCRI","Age","Male","BMI","ASA","Surgical_type","Hypertension","ACEI_ARB","Beta_blocker","CCB","Diuretic")
frailty_cov <- c(main_cov,"Frailty")
outcomes <- c("MACE","AKI","ALI","Pulmonary","Inhospital_death")
outcome_labels <- c(MACE="Major adverse cardiac events",AKI="Acute kidney injury",ALI="Severe acute liver injury",Pulmonary="Pulmonary complications",Inhospital_death="In-hospital death")

fmtp <- function(p) ifelse(is.na(p), "", ifelse(p<0.001,"<0.001",sprintf("%.3f",p)))
fit_one <- function(d,y,spec,covs) {
  y_name <- as.character(y)[1]
  vars <- c(y_name,"ClusterF",covs)
  z <- d[complete.cases(d[, ..vars]) & d[[y_name]] %in% c(0,1)]
  event_n <- sum(z[[y_name]]==1)
  analysis_n <- nrow(z)
  rhs <- c("ClusterF", covs)
  f <- as.formula(paste(y_name, "~", paste(rhs, collapse="+")))
  fit <- glm(f, data=z, family=binomial())
  sm <- coef(summary(fit))
  rows <- lapply(c("Labile Hypotension","Labile Hypertension"), function(lab) {
    term <- paste0("ClusterF",lab)
    est <- sm[term,"Estimate"]; se <- sm[term,"Std. Error"]; p <- sm[term,"Pr(>|z|)"]
    data.table(
      Center=unique(d$Center), Outcome=unname(outcome_labels[y_name]), Model=spec,
      Comparison=paste0(lab," vs Stable Hemodynamics"),
      Analysis_N=analysis_n, Events=event_n, OR=exp(est),
      CI_low=exp(est-1.96*se), CI_high=exp(est+1.96*se), P_value=p,
      Converged=fit$converged, Iterations=fit$iter, AIC=AIC(fit)
    )
  })
  full <- as.data.table(sm,keep.rownames="Term")
  setnames(full,c("Estimate","Std. Error","z value","Pr(>|z|)"),c("Coefficient","SE","z","P_value"))
  full[, `:=`(Center=unique(d$Center),Outcome=unname(outcome_labels[y_name]),Model=spec,Analysis_N=analysis_n,Events=event_n,OR=exp(Coefficient),CI_low=exp(Coefficient-1.96*SE),CI_high=exp(Coefficient+1.96*SE))]
  list(key=rbindlist(rows),full=full,data=z,fit=fit)
}

key <- list(); full <- list(); den <- list(); ri<-1; fi<-1; di<-1
for (d in list(m,i)) for (y in outcomes) {
  specs <- list(
    list(name="Unadjusted",covs=character()),
    list(name="Preoperatively adjusted (primary)",covs=main_cov),
    list(name="Expanded preoperative complete-case sensitivity",covs=frailty_cov)
  )
  for (s in specs) {
    obj <- fit_one(d,y,s$name,s$covs)
    key[[ri]]<-obj$key;ri<-ri+1
    full[[fi]]<-obj$full;fi<-fi+1
    z<-obj$data
    event_n <- sum(z[[as.character(y)[1]]]==1)
    den[[di]]<-data.table(Center=unique(d$Center),Outcome=unname(outcome_labels[y]),Model=s$name,Analysis_N=nrow(z),Events=event_n,
      Labile_Hypotension_N=sum(z$Cluster==1),Stable_Hemodynamics_N=sum(z$Cluster==2),Labile_Hypertension_N=sum(z$Cluster==3));di<-di+1
  }
}
key <- rbindlist(key); full <- rbindlist(full,fill=TRUE); den <- rbindlist(den)
key[, OR_95CI:=sprintf("%.2f (%.2f-%.2f)",OR,CI_low,CI_high)]
key[, P_formatted:=fmtp(P_value)]

cr <- key[Model=="Unadjusted",.(Center,Outcome,Comparison,Analysis_N_Unadjusted=Analysis_N,Events_Unadjusted=Events,Unadjusted_OR_95CI=OR_95CI,Unadjusted_P=P_formatted)]
ad <- key[Model=="Preoperatively adjusted (primary)",.(Center,Outcome,Comparison,Analysis_N_Adjusted=Analysis_N,Events_Adjusted=Events,Adjusted_OR_95CI=OR_95CI,Adjusted_P=P_formatted)]
pub <- merge(cr,ad,by=c("Center","Outcome","Comparison"),sort=FALSE)

miss_vars <- unique(c(main_cov,"Frailty"))
miss <- rbindlist(lapply(list(m,i), function(d) rbindlist(lapply(miss_vars,function(v)data.table(Center=unique(d$Center),Variable=v,Cohort_N=nrow(d),Nonmissing_N=sum(!is.na(d[[v]])),Missing_N=sum(is.na(d[[v]])),Missing_percent=100*mean(is.na(d[[v]])))))))

rates <- rbindlist(lapply(list(m,i),function(d)rbindlist(lapply(c(outcomes,"ICU","Nonroutine_discharge"),function(y){
  rbindlist(lapply(c(1,2,3),function(k){z<-d[Cluster==k,get(y)];z<-z[!is.na(z)];data.table(Center=unique(d$Center),Outcome=if(y%in%names(outcome_labels))unname(outcome_labels[y]) else y,Cluster=k,Phenotype=c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[k],Assessed_N=length(z),Events=sum(z==1),Percent=100*mean(z==1))}))
}))))

los <- rbindlist(lapply(list(m,i),function(d)rbindlist(lapply(c("Postoperative_LOS_h","Total_LOS_d"),function(y)rbindlist(lapply(c(1,2,3),function(k){z<-d[Cluster==k,get(y)];z<-z[!is.na(z)];data.table(Center=unique(d$Center),Outcome=y,Cluster=k,Phenotype=c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[k],Nonmissing_N=length(z),Median=median(z),Q1=quantile(z,.25),Q3=quantile(z,.75))}))))))

fwrite(key,file.path(out,"FINAL_MODEL_KEY_RESULTS_LONG.csv"),bom=TRUE)
fwrite(full,file.path(out,"FINAL_MODEL_FULL_COEFFICIENTS.csv"),bom=TRUE)
fwrite(den,file.path(out,"FINAL_MODEL_DENOMINATORS.csv"),bom=TRUE)
fwrite(pub,file.path(out,"TABLE_2_PRIMARY_PREOPERATIVE_ADJUSTED_OR.csv"),bom=TRUE)
fwrite(miss,file.path(out,"FINAL_MODEL_COVARIATE_MISSINGNESS.csv"),bom=TRUE)
fwrite(rates,file.path(out,"FINAL_OUTCOME_RATES_BY_PHENOTYPE.csv"),bom=TRUE)
fwrite(los,file.path(out,"FINAL_LOS_BY_PHENOTYPE.csv"),bom=TRUE)

meta <- list(
  analysis_date=as.character(Sys.Date()),
  inspire_version="1.0",
  inspire_doi="10.13026/jyzb-ez61",
  primary_adjustment=paste(main_cov,collapse=", "),
  frailty_sensitivity=paste(frailty_cov,collapse=", "),
  medication_definition="Recorded administration from hospital admission through operating-room entry in both cohorts",
  pulmonary_endpoint="Enhanced union of strict postoperative laboratory proxy and structured complication (MOVER) or postoperative ICD-10 (INSPIRE)",
  MOVER_N=nrow(m),INSPIRE_N=nrow(i)
)
writeLines(jsonlite::toJSON(meta,pretty=TRUE,auto_unbox=TRUE),file.path(out,"FINAL_ANALYSIS_METADATA.json"))

print(pub)
print(den[Model=="Preoperatively adjusted (primary)"])
