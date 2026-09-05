suppressPackageStartupMessages({
  library(data.table)
  library(xgboost)
  library(pROC)
})

set.seed(20260823)
root <- normalizePath(".", winslash="/", mustWork=TRUE)
base <- file.path(root,"outputs","OR_GT60_TWO_CENTER")
out <- file.path(Sys.getenv("ANALYSIS_OUT", unset=file.path(root,"work","final_submission_analysis")),"recognition")
dir.create(out,recursive=TRUE,showWarnings=FALSE)

phenotypes <- c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")
surgical_levels <- c("General surgery","Orthopedic surgery","Urologic and gynecologic surgery","Neurosurgery","Thoracic surgery","Vascular surgery","Other")
num <- function(x) suppressWarnings(as.numeric(as.character(x)))
male <- function(x){z<-toupper(trimws(as.character(x)));fifelse(z%chin%c("M","MALE","1"),1,fifelse(z%chin%c("F","FEMALE","0"),0,NA_real_))}
norm_surg <- function(x){z<-trimws(as.character(x));z[is.na(z)|z==""|!z%chin%surgical_levels]<-"Other";z}

m0<-fread(Sys.getenv("MOVER_INPUT", unset=file.path(base,"MOVER_GT60_FINAL_OUTCOMES_V2.csv")),showProgress=FALSE)
i0<-fread(Sys.getenv("INSPIRE_INPUT", unset=file.path(base,"INSPIRE_GT60_FINAL_OUTCOMES_V4_RCRI_FRAILTY.csv")),showProgress=FALSE)
mmed<-fread(Sys.getenv("MOVER_MEDICATION_INPUT",unset=file.path(base,"PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE","MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv")),showProgress=FALSE)
imed<-fread(Sys.getenv("INSPIRE_MEDICATION_INPUT",unset=file.path(base,"PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE","INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv")),showProgress=FALSE)

m<-m0[,.(ID=as.character(LOG_ID),Phenotype=factor(c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[num(Cluster_GT60)],levels=phenotypes),
 Age=num(Age),Male=male(Sex),BMI=num(BMI),ASA=num(ASA),Surgical_type=norm_surg(Surgical_type),Hypertension=num(Essential_hypertension_flag),Diabetes=num(Diabetes_mellitus_flag),CAD=num(Coronary_artery_disease_flag),Heart_failure=num(Heart_failure_flag),Cerebrovascular=num(Cerebrovascular_disease_flag),CKD=num(Chronic_kidney_disease_flag),RCRI=num(RCRI_score_0_6),Frailty=num(Modified_frailty_score_0_5),Hematocrit=num(Hematocrit_pct),Albumin=num(Albumin_g_dL),Creatinine=num(Creatinine_mg_dL))]
i<-i0[,.(ID=as.character(op_id),Phenotype=factor(c("Labile Hypotension","Stable Hemodynamics","Labile Hypertension")[num(Cluster_GT60)],levels=phenotypes),
 Age=num(Common_Age),Male=num(Common_Male),BMI=num(Common_BMI),ASA=num(Common_ASA),Surgical_type=norm_surg(Common_Surgical_type),Hypertension=num(Common_Hypertension),Diabetes=num(Common_Diabetes),CAD=num(Common_Coronary_artery_disease),Heart_failure=num(Common_Heart_failure),Cerebrovascular=num(Common_Cerebrovascular_disease),CKD=num(Common_Chronic_kidney_disease),RCRI=num(RCRI_score_0_6),Frailty=num(Modified_frailty_score_0_5),Hematocrit=num(Preop_Hematocrit_pct),Albumin=num(Preop_Albumin_g_dL),Creatinine=num(Preop_Creatinine_mg_dL))]
mmed<-unique(mmed[,.(ID=as.character(LOG_ID),ACEI_ARB=num(ACEI_ARB_given_admission_to_or),Beta_blocker=num(Beta_blocker_given_admission_to_or),CCB=num(Calcium_channel_blocker_given_admission_to_or),Diuretic=num(Diuretic_given_admission_to_or))],by="ID")
imed<-unique(imed[,.(ID=as.character(op_id),ACEI_ARB=num(ACEI_ARB),Beta_blocker=num(Beta_blocker),CCB=num(CCB),Diuretic=num(Diuretic))],by="ID")
m<-merge(m,mmed,by="ID",all.x=TRUE,sort=FALSE);i<-merge(i,imed,by="ID",all.x=TRUE,sort=FALSE)
for(dn in c("m","i")){d<-get(dn);for(v in c("ACEI_ARB","Beta_blocker","CCB","Diuretic"))d[is.na(get(v)),(v):=0];assign(dn,d)}

bounds<-list(Age=c(18,110),BMI=c(10,80),RCRI=c(0,6),Frailty=c(0,5),Hematocrit=c(10,70),Albumin=c(.5,6.5),Creatinine=c(.1,30),ASA=c(1,4))
for(dn in c("m","i")){d<-get(dn);for(v in names(bounds)){bad<-is.finite(d[[v]])&(d[[v]]<bounds[[v]][1]|d[[v]]>bounds[[v]][2]);d[bad,(v):=NA_real_]};assign(dn,d)}

base_cont<-c("Age","BMI","RCRI","Frailty","Hematocrit","Albumin","Creatinine")
base_bin<-c("Male","Hypertension","Diabetes","CAD","Heart_failure","Cerebrovascular","CKD","ACEI_ARB","Beta_blocker","CCB","Diuretic")
base_cat<-c("ASA","Surgical_type")

prepare_matrix <- function(train,target,extra_cont=character()){
 tr<-copy(train);ta<-copy(target);cont<-c(base_cont,extra_cont);bin<-base_bin;catv<-base_cat
 meds<-sapply(cont,function(v){x<-tr[[v]];x<-x[is.finite(x)];if(length(x))median(x) else 0})
 for(v in cont){mis<-paste0(v,"_missing");tr[,(mis):=as.integer(!is.finite(get(v)))];ta[,(mis):=as.integer(!is.finite(get(v)))];tr[!is.finite(get(v)),(v):=meds[v]];ta[!is.finite(get(v)),(v):=meds[v]]}
 for(v in bin){mis<-paste0(v,"_missing");tr[,(mis):=as.integer(is.na(get(v)))];ta[,(mis):=as.integer(is.na(get(v)))];tr[is.na(get(v)),(v):=0];ta[is.na(get(v)),(v):=0]}
 tr[,ASA:=factor(as.character(as.integer(ASA)),levels=as.character(1:4))];ta[,ASA:=factor(as.character(as.integer(ASA)),levels=as.character(1:4))]
 tr[,Surgical_type:=factor(norm_surg(Surgical_type),levels=surgical_levels)];ta[,Surgical_type:=factor(norm_surg(Surgical_type),levels=surgical_levels)]
 for(v in catv){mis<-paste0(v,"_missing");tr[,(mis):=as.integer(is.na(get(v)))];ta[,(mis):=as.integer(is.na(get(v)))]}
 tr[is.na(ASA),ASA:=factor("2",levels=as.character(1:4))];ta[is.na(ASA),ASA:=factor("2",levels=as.character(1:4))]
 tr[is.na(Surgical_type),Surgical_type:=factor("Other",levels=surgical_levels)];ta[is.na(Surgical_type),Surgical_type:=factor("Other",levels=surgical_levels)]
 rhs<-c(cont,bin,catv,paste0(cont,"_missing"),paste0(bin,"_missing"),paste0(catv,"_missing"))
 form<-as.formula(paste("~",paste(rhs,collapse="+")))
 x<-model.matrix(form,tr)[,-1,drop=FALSE];xt<-model.matrix(form,ta)[,-1,drop=FALSE]
 miss<-setdiff(colnames(x),colnames(xt));if(length(miss))xt<-cbind(xt,matrix(0,nrow(xt),length(miss),dimnames=list(NULL,miss)))
 extra<-setdiff(colnames(xt),colnames(x));if(length(extra))xt<-xt[,setdiff(colnames(xt),extra),drop=FALSE]
 xt<-xt[,colnames(x),drop=FALSE]
 list(train=x,target=xt,medians=meds,columns=colnames(x))
}

auc1<-function(y,p)if(length(unique(y))<2)NA_real_ else as.numeric(auc(roc(y,p,quiet=TRUE)))
evaluate<-function(truth,prob){
 prob<-pmax(pmin(prob,1-1e-9),1e-9);prob<-prob/rowSums(prob);pred<-max.col(prob)-1L
 cls<-rbindlist(lapply(0:2,function(k){yy<-as.integer(truth==k);pp<-prob[,k+1];pr<-as.integer(pred==k);tp<-sum(pr==1&yy==1);fn<-sum(pr==0&yy==1);tn<-sum(pr==0&yy==0);fp<-sum(pr==1&yy==0);data.table(Phenotype=phenotypes[k+1],AUC=auc1(yy,pp),Sensitivity=tp/(tp+fn),Specificity=tn/(tn+fp),Events=sum(yy))}))
 oh<-matrix(0,nrow(prob),3);oh[cbind(seq_len(nrow(prob)),truth+1)]<-1
 list(summary=data.table(Macro_AUC=mean(cls$AUC),Labile_Hypotension_AUC=cls[1,AUC],Stable_Hemodynamics_AUC=cls[2,AUC],Labile_Hypertension_AUC=cls[3,AUC],Accuracy=mean(pred==truth),Balanced_accuracy=mean(cls$Sensitivity),Multiclass_Brier=mean(rowSums((prob-oh)^2))),class=cls,pred=pred,prob=prob)
}

params<-list(objective="multi:softprob",num_class=3,eval_metric="mlogloss",eta=.08,max_depth=3,min_child_weight=25,subsample=.8,colsample_bytree=.8,nthread=8)
nrounds<-100L
make_folds<-function(y){f<-integer(length(y));for(k in 0:2){ids<-which(y==k);f[ids]<-sample(rep(1:10,length.out=length(ids)))};f}

fit_scenario<-function(name,dm,di,extra_cont=character()){
 y<-as.integer(dm$Phenotype)-1L;yi<-as.integer(di$Phenotype)-1L;fold<-make_folds(y);oof<-matrix(NA_real_,nrow(dm),3)
 for(f in 1:10){va<-which(fold==f);tr<-which(fold!=f);pr<-prepare_matrix(dm[tr],dm[va],extra_cont);fit<-xgboost(params=params,data=pr$train,label=y[tr],nrounds=nrounds,verbose=0);oof[va,]<-matrix(predict(fit,pr$target),ncol=3,byrow=TRUE)}
 frozen<-prepare_matrix(dm,di,extra_cont);fit<-xgboost(params=params,data=frozen$train,label=y,nrounds=nrounds,verbose=0);pext<-matrix(predict(fit,frozen$target),ncol=3,byrow=TRUE)
 em<-evaluate(y,oof);ei<-evaluate(yi,pext)
 perf<-rbind(cbind(data.table(Center="MOVER 10-fold cross-validation",Scenario=name,N=nrow(dm)),em$summary),cbind(data.table(Center="INSPIRE frozen external validation",Scenario=name,N=nrow(di)),ei$summary))
 cls<-rbind(cbind(data.table(Center="MOVER 10-fold cross-validation",Scenario=name,N=nrow(dm)),em$class),cbind(data.table(Center="INSPIRE frozen external validation",Scenario=name,N=nrow(di)),ei$class))
 preds<-rbind(data.table(Center="MOVER_CV",Scenario=name,ID=dm$ID,Observed=dm$Phenotype,P_Labile_Hypotension=oof[,1],P_Stable_Hemodynamics=oof[,2],P_Labile_Hypertension=oof[,3]),data.table(Center="INSPIRE_external",Scenario=name,ID=di$ID,Observed=di$Phenotype,P_Labile_Hypotension=pext[,1],P_Stable_Hemodynamics=pext[,2],P_Labile_Hypertension=pext[,3]))
 list(perf=perf,class=cls,preds=preds,model=fit,preprocessing=frozen)
}

results<-list();results[["Preoperative model"]]<-fit_scenario("Preoperative model",m,i)

edir<-Sys.getenv("EARLY_FEATURE_DIR",unset=file.path(base,"EARLY_INTRAOPERATIVE_RECOGNITION_STEP2"))
me<-fread(Sys.getenv("MOVER_EARLY_FEATURE_INPUT",unset=file.path(edir,"MOVER_EARLY_MAP_FEATURES_15_30_60.csv")),showProgress=FALSE)
ie<-fread(Sys.getenv("INSPIRE_EARLY_FEATURE_INPUT",unset=file.path(edir,"INSPIRE_EARLY_MAP_FEATURES_15_30_60.csv")),showProgress=FALSE)
me[,ID:=as.character(ID)];ie[,ID:=as.character(ID)]
for(w in c(15,30,60)){
 prefix<-paste0("early",w,"_");evalv<-paste0(prefix,"evaluable");cols<-grep(paste0("^",prefix),names(me),value=TRUE);features<-setdiff(cols,c(evalv,paste0(prefix,c("first_observation_delay_min","last_observation_min","temporal_coverage_percent","observable_window_percent","median_sampling_interval_min"))))
 mm<-merge(m,me[,c("ID",evalv,features),with=FALSE],by="ID",all.x=FALSE);ii<-merge(i,ie[,c("ID",evalv,features),with=FALSE],by="ID",all.x=FALSE)
 mm<-mm[get(evalv)==1];ii<-ii[get(evalv)==1]
 for(v in features){mm[,(v):=num(get(v))];ii[,(v):=num(get(v))]}
 nm<-paste0("Preoperative + first ",w," min MAP")
 results[[nm]]<-fit_scenario(nm,mm,ii,features)
}

perf<-rbindlist(lapply(results,`[[`,"perf"));cls<-rbindlist(lapply(results,`[[`,"class"));preds<-rbindlist(lapply(results,`[[`,"preds"))
fwrite(perf,file.path(out,"FOLD_SAFE_RECOGNITION_PERFORMANCE.csv"),bom=TRUE)
fwrite(cls,file.path(out,"FOLD_SAFE_RECOGNITION_CLASS_PERFORMANCE.csv"),bom=TRUE)
fwrite(preds,file.path(out,"FOLD_SAFE_RECOGNITION_PREDICTIONS.csv"),bom=TRUE)
saveRDS(results,file.path(out,"FOLD_SAFE_RECOGNITION_MODELS.rds"))
writeLines(c("All MOVER cross-validation predictions were generated with preprocessing refit inside each training fold.","Continuous-value medians and missingness indicators were learned within each training fold; no validation-fold values informed preprocessing.","The full MOVER preprocessing and model were then frozen and applied to INSPIRE version 1.0 without refitting.","Antihypertensive exposure means recorded administration from hospital admission through operating-room entry in both cohorts.","The 15-, 30-, and 60-minute analyses are early recognition analyses because the early MAP segment is part of the final trajectory defining phenotype."),file.path(out,"FOLD_SAFE_RECOGNITION_METHODS.txt"))
print(perf)
