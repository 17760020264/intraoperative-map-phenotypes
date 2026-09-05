suppressPackageStartupMessages(library(data.table))
root<-normalizePath(".",winslash="/",mustWork=TRUE)
base<-file.path(root,"outputs","OR_GT60_TWO_CENTER")
out<-Sys.getenv("ANALYSIS_OUT",unset=file.path(root,"derived","analysis"))
dir.create(out,recursive=TRUE,showWarnings=FALSE)
d<-fread(Sys.getenv("MOVER_INPUT",unset=file.path(base,"MOVER_GT60_FINAL_OUTCOMES_V2.csv")),showProgress=FALSE)
n<-names(d);cand<-n[match("baseline_map",n):match("mean_map_above_140",n)]
stopifnot(length(cand)==91L)

direct<-c("baseline_map","mean_map","min_map","max_map","time_weighted_avg_map","delta_map","max_decrease","arv","map_sd","map_cv","map_range")
derived<-c(time_below_65="fraction_time_below_65",time_below_55="fraction_time_below_55",aut_65="aut_65_per_min",episodes_below_65="episodes_below_65_per_hour",time_above_120="fraction_time_above_120",time_above_140="fraction_time_above_140",aat_120="aat_120_per_min",episodes_above_120="episodes_above_120_per_hour")
domain<-function(v){
 if(grepl("below|aut_|under",v))return("Hypotension burden")
 if(grepl("above|aat_",v))return("Hypertension burden")
 if(v%in%c("arv","map_sd","map_cv","map_range"))return("Variability")
 "Level and change"
}
threshold<-function(v){z<-regmatches(v,regexpr("[0-9]+$",v));ifelse(length(z)&&nzchar(z),z,NA_character_)}
decision<-function(v){
 if(v%in%direct)return(list("Retained directly",v,"Core global level/change or variability summary"))
 if(v%in%names(derived))return(list("Retained after duration normalization",unname(derived[v]),"Representative clinically interpretable threshold exposure; normalized for operation length"))
 if(grepl("mean_duration|max_duration|mean_interval|mean_aut|mean_aat|mean_map_under|mean_map_above",v))return(list("Excluded","","Conditionally defined or sparse among operations without threshold exposure"))
 if(grepl("time_below|episodes_below|aut_",v))return(list("Excluded","","Redundant nested hypotension threshold variant"))
 if(grepl("time_above|episodes_above|aat_",v))return(list("Excluded","","Redundant nested hypertension threshold variant"))
 list("Excluded","","Redundant summary")
}
rows<-rbindlist(lapply(seq_along(cand),function(j){v<-cand[j];x<-suppressWarnings(as.numeric(d[[v]]));dec<-decision(v);data.table(Candidate_order=j,Candidate_variable=v,Domain=domain(v),Threshold_mm_Hg=threshold(v),Missing_N=sum(is.na(x)),Missing_percent=100*mean(is.na(x)),Zero_percent=100*mean(x==0,na.rm=TRUE),Unique_N=uniqueN(x,na.rm=TRUE),Disposition=dec[[1]],Final_feature=dec[[2]],Reason=dec[[3]])}))
fwrite(rows,file.path(out,"SUPPLEMENTARY_TABLE_S2A_91_CANDIDATE_FEATURE_AUDIT.csv"),bom=TRUE)

spec<-fread(Sys.getenv("FEATURE_SPEC_INPUT",unset=file.path(root,"model","FULL_MODEL_FEATURE_SPECIFICATION.csv")))
definitions<-data.table(
 Feature=spec$Feature,
 Operational_definition=c(
  "First eligible intraoperative MAP","Arithmetic mean MAP","Minimum MAP","Maximum MAP","Time-weighted average MAP","Mean MAP minus first MAP","First MAP minus minimum MAP, truncated at 0","Mean absolute difference between successive MAP values","Standard deviation of MAP","MAP standard deviation divided by mean MAP","Maximum minus minimum MAP","Eligible MAP measurement count divided by analyzed minutes","Minutes with MAP <65 divided by analyzed minutes","Minutes with MAP <55 divided by analyzed minutes","Area under 65 mm Hg divided by analyzed minutes","Number of MAP <65 episodes per analyzed hour","Minutes with MAP >120 divided by analyzed minutes","Minutes with MAP >140 divided by analyzed minutes","Area above 120 mm Hg divided by analyzed minutes","Number of MAP >120 episodes per analyzed hour"),
 Units=c("mm Hg","mm Hg","mm Hg","mm Hg","mm Hg","mm Hg","mm Hg","mm Hg","mm Hg","ratio","mm Hg","measurements/min","proportion","proportion","mm Hg","episodes/h","proportion","proportion","mm Hg","episodes/h"),
 Source_candidate=c("baseline_map","mean_map","min_map","max_map","time_weighted_avg_map","delta_map","max_decrease","arv","map_sd","map_cv","map_range","n_measurements and total_duration_min","time_below_65 and total_duration_min","time_below_55 and total_duration_min","aut_65 and total_duration_min","episodes_below_65 and total_duration_min","time_above_120 and total_duration_min","time_above_140 and total_duration_min","aat_120 and total_duration_min","episodes_above_120 and total_duration_min")
)
final<-merge(spec,definitions,by="Feature",all.x=TRUE,sort=FALSE)
setorder(final,Order)
fwrite(final,file.path(out,"SUPPLEMENTARY_TABLE_S2B_FINAL_20_FEATURE_DEFINITIONS.csv"),bom=TRUE)

summary<-rows[,.(Candidate_N=.N),by=.(Disposition,Reason)]
summary<-rbind(summary,data.table(
 Disposition="Derived sampling-density feature",
 Reason="Eligible MAP count divided by analyzed duration; included to represent measurement density across databases",
 Candidate_N=1L
),use.names=TRUE)
fwrite(summary,file.path(out,"FEATURE_REDUCTION_SUMMARY.csv"),bom=TRUE)
print(summary)
