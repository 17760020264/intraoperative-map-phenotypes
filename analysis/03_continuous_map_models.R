suppressPackageStartupMessages(library(data.table))
root<-normalizePath('.',winslash='/',mustWork=TRUE);base<-file.path(root,'outputs','OR_GT60_TWO_CENTER');out<-Sys.getenv('ANALYSIS_OUT',unset=file.path(root,'work','final_submission_analysis'))
num<-function(x)suppressWarnings(as.numeric(as.character(x)));male<-function(x){z<-toupper(trimws(as.character(x)));fifelse(z%chin%c('M','MALE','1'),1,fifelse(z%chin%c('F','FEMALE','0'),0,NA_real_))}
m0<-fread(Sys.getenv('MOVER_INPUT',unset=file.path(base,'MOVER_GT60_FINAL_OUTCOMES_V2.csv')),showProgress=FALSE);i0<-fread(Sys.getenv('INSPIRE_INPUT',unset=file.path(base,'INSPIRE_GT60_FINAL_OUTCOMES_V4_RCRI_FRAILTY.csv')),showProgress=FALSE)
mm<-fread(Sys.getenv('MOVER_MEDICATION_INPUT',unset=file.path(base,'PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE','MOVER_PREOP_ANTIHYPERTENSIVE_EVIDENCE_BY_OPERATION.csv')),showProgress=FALSE);im<-fread(Sys.getenv('INSPIRE_MEDICATION_INPUT',unset=file.path(base,'PREOP_ANTIHYPERTENSIVE_BY_PHENOTYPE','INSPIRE_PREOP_RECORDED_ANTIHYPERTENSIVE_FLAGS.csv')),showProgress=FALSE)
mm<-unique(mm[,.(ID=as.character(LOG_ID),ACEI_ARB=num(ACEI_ARB_given_admission_to_or),Beta_blocker=num(Beta_blocker_given_admission_to_or),CCB=num(Calcium_channel_blocker_given_admission_to_or),Diuretic=num(Diuretic_given_admission_to_or))],by='ID');im<-unique(im[,.(ID=as.character(op_id),ACEI_ARB=num(ACEI_ARB),Beta_blocker=num(Beta_blocker),CCB=num(CCB),Diuretic=num(Diuretic))],by='ID')
features<-c('baseline_map','mean_map','min_map','max_map','time_weighted_avg_map','delta_map','max_decrease','arv','map_sd','map_cv','map_range','measurement_rate_per_min','fraction_time_below_65','fraction_time_below_55','aut_65_per_min','episodes_below_65_per_hour','fraction_time_above_120','fraction_time_above_140','aat_120_per_min','episodes_above_120_per_hour')
logvars<-c('max_decrease','arv','map_sd','map_cv','map_range','measurement_rate_per_min','fraction_time_below_65','fraction_time_below_55','aut_65_per_min','episodes_below_65_per_hour','fraction_time_above_120','fraction_time_above_140','aat_120_per_min','episodes_above_120_per_hour')
domains<-c(rep('BP level',7),rep('BP variability / sampling',5),rep('Hypotension burden',4),rep('Hypertension burden',4));names(domains)<-features
labels<-c('Baseline MAP','Mean MAP','Minimum MAP','Maximum MAP','Time-weighted average MAP','Mean minus baseline MAP','Maximum decrease from baseline','Average real variability','MAP standard deviation','MAP coefficient of variation','MAP range','Measurement rate','Fraction of time MAP <65','Fraction of time MAP <55','Area under 65 per min','Episodes MAP <65 per h','Fraction of time MAP >120','Fraction of time MAP >140','Area above 120 per min','Episodes MAP >120 per h');names(labels)<-features
prep<-function(d,center){dur<-pmax(num(d$total_duration_min),1e-9);if(center=='MOVER'){z<-d[,.(ID=as.character(LOG_ID),Center=center,RCRI=num(RCRI_score_0_6),Age=num(Age),Male=male(Sex),BMI=num(BMI),ASA=num(ASA),Surgical_type=factor(trimws(as.character(Surgical_type))),Hypertension=num(Essential_hypertension_flag),MACE=num(Final_MACE_enhanced),AKI=num(AKI_combined_flag),baseline_map=num(baseline_map),mean_map=num(mean_map),min_map=num(min_map),max_map=num(max_map),time_weighted_avg_map=num(time_weighted_avg_map),delta_map=num(delta_map),max_decrease=num(max_decrease),arv=num(arv),map_sd=num(map_sd),map_cv=num(map_cv),map_range=num(map_range),measurement_rate_per_min=num(n_measurements)/dur,fraction_time_below_65=num(time_below_65)/dur,fraction_time_below_55=num(time_below_55)/dur,aut_65_per_min=num(aut_65)/dur,episodes_below_65_per_hour=60*num(episodes_below_65)/dur,fraction_time_above_120=num(time_above_120)/dur,fraction_time_above_140=num(time_above_140)/dur,aat_120_per_min=num(aat_120)/dur,episodes_above_120_per_hour=60*num(episodes_above_120)/dur)];z<-merge(z,mm,by='ID',all.x=TRUE)}else{z<-d[,.(ID=as.character(op_id),Center=center,RCRI=num(RCRI_score_0_6),Age=num(Common_Age),Male=num(Common_Male),BMI=num(Common_BMI),ASA=num(Common_ASA),Surgical_type=factor(trimws(as.character(Common_Surgical_type))),Hypertension=num(Common_Hypertension),MACE=num(MACE_final_flag),AKI=num(SA_AKI),baseline_map=num(baseline_map),mean_map=num(mean_map),min_map=num(min_map),max_map=num(max_map),time_weighted_avg_map=num(time_weighted_avg_map),delta_map=num(delta_map),max_decrease=num(max_decrease),arv=num(arv),map_sd=num(map_sd),map_cv=num(map_cv),map_range=num(map_range),measurement_rate_per_min=num(n_measurements)/dur,fraction_time_below_65=num(time_below_65)/dur,fraction_time_below_55=num(time_below_55)/dur,aut_65_per_min=num(aut_65)/dur,episodes_below_65_per_hour=60*num(episodes_below_65)/dur,fraction_time_above_120=num(time_above_120)/dur,fraction_time_above_140=num(time_above_140)/dur,aat_120_per_min=num(aat_120)/dur,episodes_above_120_per_hour=60*num(episodes_above_120)/dur)];z<-merge(z,im,by='ID',all.x=TRUE)};for(v in c('ACEI_ARB','Beta_blocker','CCB','Diuretic'))z[is.na(get(v)),(v):=0];z}
centers<-list(MOVER=prep(m0,'MOVER'),INSPIRE=prep(i0,'INSPIRE'));covs<-c('RCRI','Age','Male','BMI','ASA','Surgical_type','Hypertension','ACEI_ARB','Beta_blocker','CCB','Diuretic')
res_list<-list();ri<-1
for(ct in names(centers)){
  d<-centers[[ct]]
  for(y in c('MACE','AKI')){
    for(v in features){
      vars<-c(y,v,covs)
      z<-d[complete.cases(d[,..vars])&get(y)%in%c(0,1)]
      x<-num(z[[v]])
      if(v%in%logvars)x<-log1p(pmax(x,0))
      sx<-sd(x)
      if(!is.finite(sx)||sx==0)next
      z[,Feature_z:=(x-mean(x))/sx]
      fit<-glm(as.formula(paste(y,'~ Feature_z +',paste(covs,collapse='+'))),data=z,family=binomial())
      sm<-coef(summary(fit));b<-sm['Feature_z','Estimate'];se<-sm['Feature_z','Std. Error'];p<-sm['Feature_z','Pr(>|z|)']
      res_list[[ri]]<-data.table(Center=ct,Outcome=y,Domain=domains[v],Parameter=v,Display_name=labels[v],Analysis_scale=ifelse(v%in%logvars,'1 SD of log1p-transformed feature','1 SD of untransformed feature'),Analysis_N=nrow(z),Events=sum(z[[y]]==1),OR=exp(b),CI_low=exp(b-1.96*se),CI_high=exp(b+1.96*se),P_value=p)
      ri<-ri+1
    }
  }
}
res<-rbindlist(res_list,fill=TRUE)
res[,FDR_P:=p.adjust(P_value,'BH'),by=.(Center,Outcome)];res[,OR_95CI:=sprintf('%.2f (%.2f-%.2f)',OR,CI_low,CI_high)];res[,P_formatted:=fifelse(P_value<.001,'<0.001',sprintf('%.3f',P_value))];res[,FDR_formatted:=fifelse(FDR_P<.001,'<0.001',sprintf('%.3f',FDR_P))]
fwrite(res,file.path(out,'SUPPLEMENTARY_TABLE_S6_ALL_20_FEATURES_PER_SD_ASSOCIATIONS.csv'),bom=TRUE);cat('Rows:',nrow(res),'\n')
