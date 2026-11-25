# =====================================================================
# PRF OUTLOOK 00: SETTINGS AND DATA                                 ####
#  Saves the outlook settings and the PRF book of business to the release
#  directory. Scripts 01-03 and 200 read them from there.
#
#  OUTPUTS (data-raw/releases/prf-outlook/)
#   prf_outlook_settings.rds   settings for this run
#   book.rds                  SOB-TPU book of business, county x type x
#                             interval x coverage, through the baseline year
#
#  Run from the package root, or all steps at once with
#  data-raw/scripts/prf-outlook/run_prf_outlook.R.
# =====================================================================
rm(list = ls(all = TRUE)); gc()

suppressPackageStartupMessages(library(data.table))
stopifnot(basename(getwd()) == "arpcPRFproj")
devtools::load_all(quiet = TRUE)

release_directory <- "data-raw/releases/prf-outlook"
dir.create(release_directory, recursive = TRUE, showWarnings = FALSE)

# ---- Settings. Saved first, so a failure below cannot leave later scripts
# reading the previous run's settings.
baseline_year   <- prf_policy_year() - 1L     # last full SOB year
projection_end  <- 2037L                      # last projected year
stopifnot(projection_end > baseline_year)

prf_outlook_settings <- list(
  baseline_year     = baseline_year,
  projection_window = projection_end - baseline_year,  # years projected past the baseline
  history_window    = 13,                      # SOB years in the book (from 2013)
  acreage_fit_years = 3,                       # yearly acreage changes fitted
  nowcast           = FALSE,                    # realized rainfall for observed intervals in incomplete current year
  calibration       = TRUE,                    # large-county indemnity calibration
  range             = 0.8,                     # share of weather years in the ranges
  # Acreage scenarios to project, release, and plot (see script 02):
  #   "main"        grazing acres move toward their ceiling; haying follows
  #   "flat_acres"  acres held at the baseline, for comparison
  # Only "main" is released for now. To bring the comparison back, use
  # c("main", "flat_acres"). The first scenario gets the rainfall bands.
  scenarios         = "main",
  release_directory = release_directory,
  run_date          = Sys.Date()
)
saveRDS(prf_outlook_settings, file.path(release_directory, "prf_outlook_settings.rds"))

# ---- Book of business

# get a clean copy of PRF filtered Summary of Business TPU for the given historical window
sobtpu <- get_prf_sobtpu(baseline = prf_outlook_settings$baseline_year,
                         window = prf_outlook_settings$history_window)

# aggregates SOB to county, type, practice, index interval, and coverage level unit, parses practice to interval          
book <- build_prf_book(sobtpu)

stopifnot(prf_outlook_settings$baseline_year %in% book$commodity_year)

saveRDS(book, file.path(release_directory, "book.rds"))

print(book[, .(acres_m = sum(insured_acres) / 1e6, liability_bn = sum(liability_amount) / 1e9,
               indemnity_bn = sum(indemnity_amount) / 1e9), keyby = commodity_year])
