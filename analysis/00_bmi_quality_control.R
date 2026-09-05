suppressPackageStartupMessages(library(data.table))

# Inputs are operation-level analytic cohorts before BMI correction. This script
# writes only audit files; it never modifies the source files in place.
mover_path <- Sys.getenv("MOVER_PRE_BMI_INPUT")
inspire_path <- Sys.getenv("INSPIRE_PRE_BMI_INPUT")
out_dir <- Sys.getenv("BMI_AUDIT_OUT", unset=file.path("derived", "bmi_audit"))
if (!nzchar(mover_path) || !nzchar(inspire_path)) {
  stop("Set MOVER_PRE_BMI_INPUT and INSPIRE_PRE_BMI_INPUT before running.")
}
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)

num <- function(x) suppressWarnings(as.numeric(as.character(x)))
max_pairwise_smd <- function(x, cluster) {
  z <- rbindlist(lapply(list(c(1,2), c(1,3), c(2,3)), function(pair) {
    a <- x[cluster == pair[1] & is.finite(x)]
    b <- x[cluster == pair[2] & is.finite(x)]
    pooled <- sqrt((var(a) + var(b)) / 2)
    data.table(Comparison=paste(pair, collapse=" vs "), SMD=(mean(a)-mean(b))/pooled)
  }))
  max(abs(z$SMD), na.rm=TRUE)
}
summarize_bmi <- function(center, id, cluster, bmi) {
  labels <- c("Labile Hypotension", "Stable Hemodynamics", "Labile Hypertension")
  d <- data.table(ID=id, Cluster=cluster, BMI=bmi)
  overall <- d[, .(Center=center, Group="Overall", Total_N=.N,
                   BMI_nonmissing_N=sum(is.finite(BMI)), BMI_missing_N=sum(!is.finite(BMI)),
                   BMI_missing_percent=100*mean(!is.finite(BMI)), BMI_median=median(BMI, na.rm=TRUE),
                   BMI_Q1=quantile(BMI,.25,na.rm=TRUE), BMI_Q3=quantile(BMI,.75,na.rm=TRUE),
                   Maximum_absolute_pairwise_SMD=max_pairwise_smd(BMI, Cluster))]
  grouped <- d[, .(Total_N=.N, BMI_nonmissing_N=sum(is.finite(BMI)),
                   BMI_missing_N=sum(!is.finite(BMI)), BMI_missing_percent=100*mean(!is.finite(BMI)),
                   BMI_median=median(BMI,na.rm=TRUE), BMI_Q1=quantile(BMI,.25,na.rm=TRUE),
                   BMI_Q3=quantile(BMI,.75,na.rm=TRUE)), by=Cluster]
  grouped[, `:=`(Center=center, Group=labels[Cluster], Maximum_absolute_pairwise_SMD=NA_real_, Cluster=NULL)]
  rbind(overall, grouped, fill=TRUE)
}

m <- fread(mover_path, showProgress=FALSE)
i <- fread(inspire_path, showProgress=FALSE)

# MOVER source conversions were already retained as height in meters and weight
# in kilograms. Recompute BMI and enforce the prespecified plausible interval.
m[, BMI_old := num(BMI)]
m[, BMI_recalculated := num(Weight_kg) / num(Height_m)^2]
m[!between(BMI_recalculated, 10, 80), BMI_recalculated := NA_real_]

# INSPIRE height is normally centimeters. Convert only recognizable alternative
# units that map to an adult height of 120-220 cm; ambiguous values remain missing.
i[, `:=`(BMI_old=num(BMI), height_raw=num(height), weight_raw=num(weight),
         height_cm_corrected=NA_real_, height_unit_rule="unresolved_or_missing")]
rules <- list(
  list(120,220,1,"centimeters"), list(1.2,2.2,100,"meters_to_centimeters"),
  list(12,22,10,"decimeters_to_centimeters"), list(47.25,86.61,2.54,"inches_to_centimeters"),
  list(1200,2200,.1,"millimeters_to_centimeters")
)
for (r in rules) {
  take <- is.na(i$height_cm_corrected) & between(i$height_raw, r[[1]], r[[2]])
  i[take, `:=`(height_cm_corrected=height_raw*r[[3]], height_unit_rule=r[[4]])]
}
i[, weight_kg_corrected := fifelse(between(weight_raw,25,350), weight_raw, NA_real_)]
i[, BMI_recalculated := weight_kg_corrected/(height_cm_corrected/100)^2]
i[is.na(BMI_recalculated) & between(BMI_old,10,80), BMI_recalculated := BMI_old]
i[!between(BMI_recalculated,10,80), BMI_recalculated := NA_real_]

fwrite(m[, .(LOG_ID, Cluster_GT60, Height_m, Weight_kg, BMI_old, BMI_recalculated)],
       file.path(out_dir,"MOVER_BMI_CORRECTION_AUDIT.csv"), bom=TRUE)
fwrite(i[, .(op_id, Cluster_GT60, height=height_raw, weight=weight_raw,
             height_cm_corrected, height_unit_rule, weight_kg_corrected, BMI_old, BMI_recalculated)],
       file.path(out_dir,"INSPIRE_BMI_CORRECTION_AUDIT.csv"), bom=TRUE)
summary <- rbind(
  summarize_bmi("MOVER", as.character(m$LOG_ID), num(m$Cluster_GT60), m$BMI_recalculated),
  summarize_bmi("INSPIRE", as.character(i$op_id), num(i$Cluster_GT60), i$BMI_recalculated), fill=TRUE)
fwrite(summary, file.path(out_dir,"BMI_RECALCULATED_SUMMARY_AND_SMD.csv"), bom=TRUE)
print(summary)
