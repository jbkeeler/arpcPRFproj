# =====================================================================
# PRF OUTLOOK: RUN ALL STEPS                                        ####
#  Runs scripts 00-03 and 200 in order, each in a fresh R process so every
#  step depends only on the files the previous steps saved.
#
#   00  settings and book of business (SOB-TPU)
#   01  indemnity backtest, large-county calibration, acreage model
#   02  projection under the acreage scenarios set in 00 (only "main" for now)
#   03  release tables (county, state, national) and indemnity ranges
#   200 figures
#
#  Edit the settings in 00 before running. Outputs go to
#  data-raw/releases/prf-outlook/ (gitignored).
#
#  Run from the package root:
#    Rscript data-raw/scripts/prf-outlook/run_prf_outlook.R
#  A first run downloads RMA index releases, NCEI precipitation, and the 2027
#  ADM (cached afterwards); later runs take about 15 minutes.
# =====================================================================
stopifnot(basename(getwd()) == "arpcPRFproj")

steps <- c("00_prf_outlook_setup_and_data.R",
           "01_prf_outlook_models.R",
           "02_prf_outlook_projection.R",
           "03_prf_outlook_release.R",
           "200_prf_outlook_exhibits.R")

for (step in steps) {
  message("\n==== ", step, " (", format(Sys.time(), "%H:%M"), ")")
  status <- system2(file.path(R.home("bin"), "Rscript"),
                    file.path("data-raw/scripts/prf-outlook", step))
  if (status != 0) stop(step, " failed; later steps were not run.", call. = FALSE)
}
message("\nDone. Release files are in data-raw/releases/prf-outlook/.")
