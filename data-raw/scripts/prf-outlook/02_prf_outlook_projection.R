# =====================================================================
# PRF OUTLOOK 02: PROJECTION                                        ####
#  Projects the baseline book through baseline + projection_window under each
#  acreage scenario in the settings and formats each as an arpcFCIPproj
#  county outlook.
#
#   main        grazing acres move toward their ceiling; haying follows
#   flat_acres  acres held at the baseline (comparison; off by default)
#
#  Which scenarios run is set by `scenarios` in script 00.
#
#  INPUTS   prf_outlook_settings.rds, book.rds, calibration.rds, acreage_fit.rds
#  OUTPUTS  projection_<scenario>.rds      book-grain projection, with
#                                          attribute indemnity_by_weather_year
#           outlook_county_<scenario>.rds  arpcFCIPproj county outlook
# =====================================================================
rm(list = ls(all = TRUE)); gc()

suppressPackageStartupMessages(library(data.table))
stopifnot(basename(getwd()) == "arpcPRFproj")
devtools::load_all(quiet = TRUE)

release_directory <- "data-raw/releases/prf-outlook"

need <- c("prf_outlook_settings.rds", "book.rds", "calibration.rds", "acreage_fit.rds")

missing <- need[!file.exists(file.path(release_directory, need))]

if (length(missing)) {
  stop("Missing inputs in ", release_directory, ": ", paste(missing, collapse = ", "),
       "\nRun scripts 00 and 01 first.")
}

prf_outlook_settings <- readRDS(file.path(release_directory, "prf_outlook_settings.rds"))

book <- readRDS(file.path(release_directory, "book.rds"))

calibration <- readRDS(file.path(release_directory, "calibration.rds"))

acreage_fit <- readRDS(file.path(release_directory, "acreage_fit.rds"))

# Every scenario this script can project, by the acreage fit it uses (NULL
# holds acres flat). The scenarios actually run, and so released and plotted,
# are chosen by `scenarios` in script 00's settings; only "main" for now.
available_scenarios <- list(main = acreage_fit, flat_acres = NULL)

scenarios <- prf_outlook_settings$scenarios
if (is.null(scenarios) || !all(scenarios %in% names(available_scenarios))) {
  stop("`scenarios` in the settings must be one or more of ",
       paste(names(available_scenarios), collapse = ", "),
       ". Rerun script 00 if the settings predate it.")
}
scenarios <- available_scenarios[scenarios]

for (scenario in names(scenarios)) {

  message("Projecting scenario: ", scenario)

  projection <- project_prf_book(
    book,
    baseline_year     = prf_outlook_settings$baseline_year,
    projection_window = prf_outlook_settings$projection_window,
    acreage_fit       = scenarios[[scenario]],
    nowcast           = prf_outlook_settings$nowcast,
    calibration       = calibration
  )

  saveRDS(projection, file.path(release_directory, paste0("projection_", scenario, ".rds")))

  saveRDS(prf_fcip_outlook(book, projection),
          file.path(release_directory, paste0("outlook_county_", scenario, ".rds")))
}
