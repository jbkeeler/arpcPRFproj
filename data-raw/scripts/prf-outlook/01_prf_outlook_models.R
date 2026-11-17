# =====================================================================
# PRF OUTLOOK 01: BACKTEST, CALIBRATION, AND ACREAGE MODEL          ####
#  Backtests indemnities over the book's history, fits the large-county
#  calibration from the backtest, and fits the grazing acreage model.
#
#  INPUTS   prf_outlook_settings.rds, book.rds (script 00)
#  OUTPUTS  backtest.rds      predicted vs SOB indemnity by year (2026 CPC release)
#           calibration.rds   county indemnity factors (NULL when turned off)
#           acreage_fit.rds   adjustment speed and state ceilings
# =====================================================================
rm(list = ls(all = TRUE)); gc()

suppressPackageStartupMessages(library(data.table))
stopifnot(basename(getwd()) == "arpcPRFproj")
devtools::load_all(quiet = TRUE)

release_directory <- "data-raw/releases/prf-outlook"
need <- c("prf_outlook_settings.rds", "book.rds")
missing <- need[!file.exists(file.path(release_directory, need))]
if (length(missing)) {
  stop("Missing inputs in ", release_directory, ": ", paste(missing, collapse = ", "),
       "\nRun 00_prf_outlook_setup_and_data.R first.")
}
prf_outlook_settings <- readRDS(file.path(release_directory, "prf_outlook_settings.rds"))
book <- readRDS(file.path(release_directory, "book.rds"))


####  ####

# ---- Indemnity backtest
# Uses the 2026 CPC release, which ends at 2024. With the 13-year history
# window, a 2027 baseline backtests 2015-2024 and a 2030 baseline 2018-2024;
# from a 2037 baseline no years are left and this stops with an error. Before
# then, backtest the NCEI-paid years (2027+) against an NCEI release.
backtest <- backtest_prf_book(book)
saveRDS(backtest, file.path(release_directory, "backtest.rds"))
print(backtest[, .(predicted_over_actual = sum(predicted_indemnity) / sum(indemnity_amount)),
               keyby = commodity_year])

# ---- Large-county calibration
calibration <- if (prf_outlook_settings$calibration) fit_prf_calibration(backtest) else NULL
saveRDS(calibration, file.path(release_directory, "calibration.rds"))
if (!is.null(calibration)) {
  message("Calibration k = $", attr(calibration, "k") / 1e6, "M")
  print(calibration[, .(counties = .N, mean_factor = mean(calibration_factor)), keyby = grid_class])
}

# ---- Grazing acreage model
acreage_fit <- fit_prf_acreage(book, prf_outlook_settings$baseline_year,
                               fit_years = prf_outlook_settings$acreage_fit_years)
saveRDS(acreage_fit, file.path(release_directory, "acreage_fit.rds"))
message("Acreage adjustment speed: ", round(acreage_fit$speed[1], 3))
