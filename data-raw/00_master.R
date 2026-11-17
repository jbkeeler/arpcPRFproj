# Entry point for building the package's datasets from raw USDA data.
# Run from the package root: Rscript data-raw/00_master.R
#
# Put downloaded raw files in data-raw/raw/ (gitignored). Each script should
# finish with usethis::use_data(<object>, overwrite = TRUE) to write data/*.rda.

devtools::load_all()

# source("data-raw/01_import_data.R")
# source("data-raw/02_clean_data.R")
