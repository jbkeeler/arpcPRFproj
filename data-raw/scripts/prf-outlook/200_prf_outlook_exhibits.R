# =====================================================================
# PRF OUTLOOK 200: EXHIBITS                                         ####
#  Outlook and backtest figures from the release artifacts. Nothing is
#  recomputed, so figures can be redrawn quickly after a run.
#
#  INPUTS   prf_outlook_settings.rds, outlook_county_<scenario>.rds,
#           backtest.rds (scripts 00-02)
#  FIGURES  (data-raw/releases/prf-outlook/figures)
#   prf_outlook.png           national totals for the released scenarios
#                             (`scenarios` in script 00), rainfall ranges
#   prf_backtest_year.png     national indemnity and loss cost by year
#   prf_backtest_county.png   county loss cost, predicted vs actual
#   prf_backtest_grids.png    predicted / actual by grids per county
#   prf_backtest_state.png    predicted / actual, top states by liability
# =====================================================================
rm(list = ls(all = TRUE)); gc()

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})
stopifnot(basename(getwd()) == "arpcPRFproj")
devtools::load_all(quiet = TRUE)

release_directory <- "data-raw/releases/prf-outlook"
settings_file <- file.path(release_directory, "prf_outlook_settings.rds")
if (!file.exists(settings_file)) stop("Missing ", settings_file, "\nRun script 00 first.")
prf_outlook_settings <- readRDS(settings_file)

# The outlook figure plots the scenarios in the settings: only "main" for
# now. Add "flat_acres" to `scenarios` in script 00 to plot it too.
scenarios <- prf_outlook_settings$scenarios
if (is.null(scenarios)) stop("The settings have no `scenarios`; rerun script 00.")
scenario_labels <- c(main = "Acres toward ceiling", flat_acres = "Flat acres")

need <- c("backtest.rds", paste0("outlook_county_", scenarios, ".rds"))
missing <- need[!file.exists(file.path(release_directory, need))]
if (length(missing)) {
  stop("Missing inputs in ", release_directory, ": ", paste(missing, collapse = ", "),
       "\nRun scripts 00-02 first.")
}
backtest <- readRDS(file.path(release_directory, "backtest.rds"))
outlooks <- lapply(setNames(scenarios, scenario_labels[scenarios]), function(scenario) {
  readRDS(file.path(release_directory, paste0("outlook_county_", scenario, ".rds")))
})

figure_directory <- file.path(release_directory, "figures")
dir.create(figure_directory, recursive = TRUE, showWarnings = FALSE)
save_figure <- function(figure, name, width = 11, height = 8) {
  ggsave(file.path(figure_directory, paste0(name, ".png")), figure,
         width = width, height = height, dpi = 200)
}

save_figure(plot_prf_outlook(outlooks, first_year = 2015, range = prf_outlook_settings$range),
            "prf_outlook")
save_figure(plot_prf_backtest(backtest, "year"), "prf_backtest_year", height = 5)
save_figure(plot_prf_backtest(backtest, "county"), "prf_backtest_county", width = 8, height = 8)
save_figure(plot_prf_backtest(backtest, "grids"), "prf_backtest_grids", width = 8, height = 5)
save_figure(plot_prf_backtest(backtest, "state"), "prf_backtest_state", width = 8, height = 6)
