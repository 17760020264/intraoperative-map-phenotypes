suppressPackageStartupMessages({library(data.table);library(nnet)})
root<-normalizePath(".",winslash="/",mustWork=TRUE);base<-file.path(root,"outputs","OR_GT60_TWO_CENTER");out<-Sys.getenv("ANALYSIS_OUT",unset=file.path(root,"work","final_submission_analysis"))
num<-function(x)suppressWarnings(as.numeric(as.character(x)));male<-function(x){z<-toupper(trimws(as.character(x)));fifelse(z%chin%c("M","MALE","1"),1,fifelse(z%chin%c("F","FEMALE","0"),0,NA_real_))}
m0<-fread(Sys.getenv("MOVER_INPUT",unset=file.path(base,"MOVER_GT60_FINAL_OUTCOMES_V2.csv")),showProgress=FALSE);i0<-fread(Sys.getenv("INSPIRE_INPUT",unset=file.path(base,"INSPIRE_GT60_FINAL_OUTCOMES_V4_RCRI_FRAILTY.csv")),showProgress=FALSE)
mm<-fread(Sys.getenv("MOVER_MEDICATION_INPUT",unset=file.path(base,"PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE","MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv")),showProgress=FALSE);im<-fread(Sys.getenv("INSPIRE_MEDICATION_INPUT",unset=file.path(base,"PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE","INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv")),showProgress=FALSE)
m<-m0[,.(ID=as.character(LOG_ID),Center="MOVER",Phenotype=factor(c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[num(Cluster_GT60)],levels=c("Stable Hemodynamics","Labile Hypotension","Labile Hypertension")),Hypertension=num(Essential_hypertension_flag),Age=num(Age),Male=male(Sex),BMI=num(BMI),ASA=num(ASA),RCRI=num(RCRI_score_0_6))]
i<-i0[,.(ID=as.character(op_id),Center="INSPIRE",Phenotype=factor(c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[num(Cluster_GT60)],levels=c("Stable Hemodynamics","Labile Hypotension","Labile Hypertension")),Hypertension=num(Common_Hypertension),Age=num(Common_Age),Male=num(Common_Male),BMI=num(Common_BMI),ASA=num(Common_ASA),RCRI=num(RCRI_score_0_6))]
mm<-unique(mm[,.(ID=as.character(LOG_ID),ACEI_ARB=num(ACEI_ARB_given_admission_to_or),Beta_blocker=num(Beta_blocker_given_admission_to_or),CCB=num(Calcium_channel_blocker_given_admission_to_or),Diuretic=num(Diuretic_given_admission_to_or))],by="ID")
im<-unique(im[,.(ID=as.character(op_id),ACEI_ARB=num(ACEI_ARB),Beta_blocker=num(Beta_blocker),CCB=num(CCB),Diuretic=num(Diuretic))],by="ID")
m<-merge(m,mm,by="ID",all.x=TRUE);i<-merge(i,im,by="ID",all.x=TRUE);for(dn in c("m","i")){d<-get(dn);for(v in c("ACEI_ARB","Beta_blocker","CCB","Diuretic"))d[is.na(get(v)),(v):=0];d[,Class_count:=ACEI_ARB+Beta_blocker+CCB+Diuretic];d[,Therapy_intensity:=factor(fifelse(Class_count==0,"None",fifelse(Class_count==1,"Single class","Multiple classes")),levels=c("None","Single class","Multiple classes"))];assign(dn,d)}

prev<-rbindlist(lapply(list(m,i),function(d)rbindlist(lapply(c("Hypertension","ACEI_ARB","Beta_blocker","CCB","Diuretic"),function(v){
  ans<-d[,.(N=.N,Positive=sum(get(v)==1),Percent=100*mean(get(v)==1)),by=.(Center,Phenotype)]
  ans[,Variable:=v]
  setcolorder(ans,c("Center","Phenotype","Variable","N","Positive","Percent"))
  ans
}))))
intensity<-rbindlist(lapply(list(m,i),function(d)d[,.(N=.N),by=.(Center,Phenotype,Therapy_intensity)][,Percent:=100*N/sum(N),by=.(Center,Phenotype)]))

extract_multinom<-function(fit,center,exposure,analysis_n){s<-summary(fit);co<-s$coefficients;se<-s$standard.errors;rbindlist(lapply(rownames(co),function(ph){if(!exposure%in%colnames(co))return(NULL);b<-co[ph,exposure];ss<-se[ph,exposure];z<-b/ss;p<-2*pnorm(-abs(z));data.table(Center=center,Analysis=exposure,Comparison=paste0(ph," vs Stable Hemodynamics"),Analysis_N=analysis_n,OR=exp(b),CI_low=exp(b-1.96*ss),CI_high=exp(b+1.96*ss),P_value=p)}))}
assoc<-list();r<-1
for(d in list(m,i)){
 z<-d[complete.cases(d[,.(Phenotype,Hypertension,Age,Male,BMI,ASA,RCRI)])]
 fit<-multinom(Phenotype~Hypertension+RCRI+Age+Male+BMI+ASA,data=z,trace=FALSE)
 assoc[[r]]<-extract_multinom(fit,unique(d$Center),"Hypertension",nrow(z));r<-r+1
 z<-d[Hypertension==1 & complete.cases(d[,.(Phenotype,ACEI_ARB,Beta_blocker,CCB,Diuretic,RCRI,Age,Male,BMI,ASA)])]
 fit<-multinom(Phenotype~ACEI_ARB+Beta_blocker+CCB+Diuretic+RCRI+Age+Male+BMI+ASA,data=z,trace=FALSE,maxit=1000)
 for(v in c("ACEI_ARB","Beta_blocker","CCB","Diuretic")){assoc[[r]]<-extract_multinom(fit,unique(d$Center),v,nrow(z));r<-r+1}
}
assoc<-rbindlist(assoc);assoc[,OR_95CI:=sprintf("%.2f (%.2f-%.2f)",OR,CI_low,CI_high)];assoc[,P_formatted:=fifelse(P_value<.001,"<0.001",sprintf("%.3f",P_value))]
fwrite(prev,file.path(out,"SUPPLEMENTARY_TABLE_S7A_HYPERTENSION_AND_DRUG_PREVALENCE.csv"),bom=TRUE)
fwrite(intensity,file.path(out,"SUPPLEMENTARY_TABLE_S7B_THERAPY_INTENSITY.csv"),bom=TRUE)
fwrite(assoc,file.path(out,"SUPPLEMENTARY_TABLE_S7C_ADJUSTED_HYPERTENSION_MEDICATION_ASSOCIATIONS.csv"),bom=TRUE)
print(assoc)
