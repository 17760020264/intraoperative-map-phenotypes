suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

ROOT <- normalizePath('.', winslash='/', mustWork=TRUE)
INPUT <- Sys.getenv(
  'RECOGNITION_INPUT',
  unset=file.path(ROOT, 'derived', 'analysis', 'recognition',
                  'FOLD_SAFE_RECOGNITION_PERFORMANCE.csv')
)
OUT <- Sys.getenv(
  'FIGURE_OUT',
  unset=file.path(ROOT, 'derived', 'figures')
)
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

d <- fread(INPUT)
d[, Stage := fcase(
  Scenario == 'Preoperative model', 'Preoperative',
  grepl('first 15 min', Scenario, fixed=TRUE), '15 min',
  grepl('first 30 min', Scenario, fixed=TRUE), '30 min',
  grepl('first 60 min', Scenario, fixed=TRUE), '60 min',
  default=NA_character_
)]
d[, Cohort := fcase(
  grepl('^MOVER', Center), 'MOVER: 10-fold cross-validation',
  grepl('^INSPIRE', Center), 'INSPIRE: frozen external validation',
  default=Center
)]
d <- d[!is.na(Stage)]
d[, Stage := factor(Stage, levels=c('Preoperative','15 min','30 min','60 min'))]
d[, Cohort := factor(Cohort,
                     levels=c('MOVER: 10-fold cross-validation',
                              'INSPIRE: frozen external validation'))]
d[, Label := sprintf('%.3f', Macro_AUC)]

cohort_colors <- c(
  'MOVER: 10-fold cross-validation'='#7663AD',
  'INSPIRE: frozen external validation'='#667085'
)

p <- ggplot(d, aes(x=Stage, y=Macro_AUC, group=Cohort, color=Cohort)) +
  geom_hline(yintercept=.50, color='#9AA0A6', linewidth=.45, linetype='dashed') +
  geom_line(linewidth=1.15) +
  geom_point(size=3.2) +
  geom_text(aes(label=Label), vjust=-1.05, size=3.4, fontface='bold',
            show.legend=FALSE) +
  facet_wrap(~Cohort, nrow=1) +
  scale_color_manual(values=cohort_colors) +
  scale_y_continuous(
    limits=c(.50,.96),
    breaks=seq(.50,.90,.10),
    labels=function(x) sprintf('%.2f',x),
    expand=expansion(mult=c(.01,.035))
  ) +
  labs(
    title='Recognition of the Final Hemodynamic Phenotype Over Time',
    subtitle='Preoperative information followed by cumulative MAP data from the first 15, 30, and 60 minutes',
    x='Information available at the time of classification',
    y='Macro-average one-vs-rest AUC'
  ) +
  theme_minimal(base_family='sans', base_size=11) +
  theme(
    legend.position='none',
    plot.title=element_text(face='bold', hjust=.5, size=15, margin=margin(b=5)),
    plot.subtitle=element_text(hjust=.5, size=10.5, color='#4B5563', margin=margin(b=12)),
    strip.text=element_text(face='bold', size=11, margin=margin(7,0,7,0)),
    strip.background=element_rect(fill='#F2F3F5', color='#80868B', linewidth=.55),
    panel.border=element_rect(fill=NA, color='#80868B', linewidth=.55),
    panel.grid.major.x=element_blank(),
    panel.grid.minor=element_blank(),
    panel.grid.major.y=element_line(color='#E2E4E7', linewidth=.5),
    axis.title=element_text(face='bold'),
    axis.text.x=element_text(face='bold'),
    plot.margin=margin(12,18,12,12)
  )

stem <- file.path(OUT, 'Supplementary_Figure_S8_Early_Phenotype_Recognition')
ggsave(paste0(stem,'.png'), p, width=10.5, height=5.8, dpi=600, bg='white')
ggsave(paste0(stem,'.pdf'), p, width=10.5, height=5.8, device=cairo_pdf, bg='white')
fwrite(d[,.(Cohort,Stage,N,Macro_AUC,Labile_Hypotension_AUC,
             Stable_Hemodynamics_AUC,Labile_Hypertension_AUC,
             Accuracy,Balanced_accuracy,Multiclass_Brier)],
       paste0(stem,'_Data.csv'), bom=TRUE)

cat('Generated Supplementary Figure S8 from', nrow(d), 'validated landmark rows.\n')
