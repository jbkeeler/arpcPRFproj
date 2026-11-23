# =====================================================================
# PRF OUTLOOK 03: RELEASE                                           ####
#  Assembles the release tables: county, state, and national outlooks for
#  each scenario in the settings (only "main" for now; see `scenarios` in
#  script 00), national indemnity ranges across past rainfall years, and a
#  record of the run.
#
#  INPUTS   prf_outlook_settings.rds, outlook_county_<scenario>.rds,
#           calibration.rds, acreage_fit.rds (scripts 00-02)
#  OUTPUTS  final_prf_outlook_<county|state|national>.rds and .csv
#              arpcFCIPproj outlook layout plus `scenario` and `loss_ratio`
#              (indemnity / total premium). The .rds files hold observed and
#              projected years; the .csv files, the assets of the GitHub
#              outlook release read by get_prf_outlook(), hold projected years
#              only.
#           prf_indemnity_ranges.csv
#              national indemnity and loss ratio percentiles by year
#           prf_outlook_run.rds
#              settings, model values, data sources, and package versions
# =====================================================================
rm(list = ls(all = TRUE)); gc()

suppressPackageStartupMessages(library(data.table))
stopifnot(basename(getwd()) == "arpcPRFproj")
devtools::load_all(quiet = TRUE)

release_directory <- "data-raw/releases/prf-outlook"

settings_file <- file.path(release_directory, "prf_outlook_settings.rds")
if (!file.exists(settings_file)) stop("Missing ", settings_file, "\nRun script 00 first.")
prf_outlook_settings <- readRDS(settings_file)

# Released scenarios follow `scenarios` in script 00's settings: only "main"
# for now. Add "flat_acres" there (not here) to release the flat-acres
# comparison too; every table below then carries both, by `scenario`.
scenarios <- prf_outlook_settings$scenarios
if (is.null(scenarios)) stop("The settings have no `scenarios`; rerun script 00.")

need <- c("calibration.rds", "acreage_fit.rds", paste0("outlook_county_", scenarios, ".rds"))

missing <- need[!file.exists(file.path(release_directory, need))]

if (length(missing)) {
  stop("Missing inputs in ", release_directory, ": ", paste(missing, collapse = ", "),
       "\nRun scripts 00-02 first.")
}

outlooks <- lapply(setNames(scenarios, scenarios), function(scenario) {
  readRDS(file.path(release_directory, paste0("outlook_county_", scenario, ".rds")))
})

# ---- County, state, and national outlooks
county <- rbindlist(outlooks, idcol = "scenario")

id_cols <- c("scenario", ".source", "commodity_year", "plan_group", "commodity_code",
             "insurance_plan_code", "unit_structure_code")
             
levels <- list(county = c("state_code", "county_code"), state = "state_code", national = NULL)

for (level in names(levels)) {
  final <- county[, lapply(.SD, sum), by = c(id_cols, levels[[level]]),
                  .SDcols = prf_outcome_cols]
  # Loss ratio after summing, so each level's ratio is of its own totals.
  final[, loss_ratio := fifelse(total_premium_amount > 0,
                                indemnity_amount / total_premium_amount, NA_real_)]
  setcolorder(final, c("scenario", "commodity_year", levels[[level]]))
  setorderv(final, c("scenario", ".source", "commodity_year", levels[[level]]))
  saveRDS(final, file.path(release_directory, paste0("final_prf_outlook_", level, ".rds")))
  # The .csv files are the GitHub release assets, so they hold the projected
  # years only (baseline on). The .rds keeps the observed history too. To
  # publish the history as well, write `final` here unfiltered.
  fwrite(final[.source == "projected"],
         file.path(release_directory, paste0("final_prf_outlook_", level, ".csv")))
}

# ---- National indemnity ranges across past rainfall years
probs <- c((1 - prf_outlook_settings$range) / 2, 0.5, 1 - (1 - prf_outlook_settings$range) / 2)
ranges <- rbindlist(lapply(scenarios, function(scenario) {
  by_weather <- attr(outlooks[[scenario]], "indemnity_by_weather_year")
  premium <- outlooks[[scenario]][.source == "projected",
                                  .(premium = sum(total_premium_amount)), by = commodity_year]
  by_weather <- merge(by_weather, premium, by = "commodity_year")
  by_weather[, .(scenario = scenario,
                 indemnity_low = stats::quantile(indemnity_amount, probs[1]),
                 indemnity_median = stats::quantile(indemnity_amount, probs[2]),
                 indemnity_high = stats::quantile(indemnity_amount, probs[3]),
                 loss_ratio_low = stats::quantile(indemnity_amount / premium, probs[1]),
                 loss_ratio_high = stats::quantile(indemnity_amount / premium, probs[3])),
             keyby = commodity_year]
}))
fwrite(ranges, file.path(release_directory, "prf_indemnity_ranges.csv"))

# ---- Record of the run
calibration <- readRDS(file.path(release_directory, "calibration.rds"))
acreage_fit <- readRDS(file.path(release_directory, "acreage_fit.rds"))
run <- list(
  setting = prf_outlook_settings,
  calibration_k = if (is.null(calibration)) NA else attr(calibration, "k"),
  acreage_speed = acreage_fit$speed[1],
  acreage_ceilings = acreage_fit[, .(state_code, ceiling)],
  rma_adm_years = rma_adm_years,
  latest_index_release = max(rma_index_releases()$crop_year),
  versions = c(arpcPRFproj = as.character(utils::packageVersion("arpcPRFproj")),
               rfcip = as.character(utils::packageVersion("rfcip")),
               R = R.version.string)
)
saveRDS(run, file.path(release_directory, "prf_outlook_run.rds"))

print(readRDS(file.path(release_directory, "final_prf_outlook_national.rds"))[
  .source == "projected", .(scenario, commodity_year, acres_m = round(insured_acres / 1e6),
                            liability_bn = round(liability_amount / 1e9, 2),
                            premium_bn = round(total_premium_amount / 1e9, 2),
                            indemnity_bn = round(indemnity_amount / 1e9, 2),
                            loss_ratio = round(indemnity_amount / total_premium_amount, 2))])
