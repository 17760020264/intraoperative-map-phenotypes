packages <- trimws(readLines("requirements-r.txt", warn = FALSE))
packages <- packages[nzchar(packages)]
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  install.packages(missing, repos = "https://cloud.r-project.org")
}
cat("R dependencies are available.\n")
