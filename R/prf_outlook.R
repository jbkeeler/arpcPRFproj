# PRF projection: the baseline book of business with the mix of intervals
# and coverage levels held fixed, county grazing acres growing toward a
# ceiling (R/prf_acreage.R), dollar outcomes moved by RMA's published
# actuarial changes, and indemnities from the rainfall index history
# (R/prf_indemnity.R).
#
# For projection year t, at county x type x practice x interval x coverage:
#   acre ratio = grazing acres(t) / acres(baseline): county for grazing,
#                state for haying
#   liability  = baseline liability x acre ratio x CBV(t) / CBV(baseline)
#   premium    = baseline premium x acre ratio x CBV ratio x rate(t) / rate(baseline)
#   subsidy    = premium x subsidy percent(t)
#   indemnity  = liability x payment factor x calibration factor
# CBV and rates are area-weighted county averages of ADM grid values. Ratios
# are applied to observed SOB levels, so the weighting largely cancels. Years
# past the latest available ADM use that ADM's values; where a driver is
# missing (e.g. an offer not in the ADM) the baseline value carries forward.
# The payment factor is the county's area-weighted grid average, either
# expected over the index history each year is rated on (CPC through 2026,
# NCEI from 2027) or realized for intervals already observed (nowcast), or its
# observed loss cost where it has no grids. The optional calibration factor
# corrects the large-county shortfall of area weighting.

# County CBV, premium rate, and subsidy percent from one year's ADM, keyed to
# the book grain.
prf_adm_drivers <- function(year, crosswalk = prf_grid_county) {

  actuarial <- get_prf_actuarial(year)

  actuarial[crosswalk, on = c("state_code", "county_code", "grid_id"), weight := i.weight]

  actuarial[!is.na(weight),
            .(county_base_value = stats::weighted.mean(county_base_value, weight),
              base_rate = stats::weighted.mean(base_rate, weight),
              subsidy_percent = mean(subsidy_percent)),
            by = .(state_code, county_code, type_code, practice_code,
                   coverage_level_percent)]
}

# ADM drivers for each year from baseline_year on, stopping at the first year
# whose ADM is not yet available (no file, or no PRF records in it yet).
prf_adm_driver_years <- function(years, crosswalk = prf_grid_county) {

  drivers <- list()
  for (year in years) {
    year_drivers <- tryCatch(prf_adm_drivers(year, crosswalk), error = function(e) NULL)
    if (is.null(year_drivers) || nrow(year_drivers) == 0) break
    drivers[[as.character(year)]] <- year_drivers[, adm_year := year]
  }
  if (length(drivers) == 0) {
    stop("No ADM data available for ", years[1], ".", call. = FALSE)
  }
  message("Using ADM for ", paste(names(drivers), collapse = ", "), ".")
  rbindlist(drivers)

}

#' Project the PRF book of business
#'
#' Projects the baseline year's book with its mix of intervals and coverage
#' levels held fixed. County grazing acres grow toward a ceiling
#' ([project_prf_acres()]) and haying acres grow at the same rate; outcomes
#' scale with acres. Liability and premium also follow RMA's published
#' changes in county base values and premium rates, and subsidy follows the
#' ADM subsidy schedule. Years past the latest available ADM keep that ADM's
#' values.
#'
#' Indemnity is liability times the expected payment factor over the
#' rainfall history of the index release the year is rated on, or its realized
#' factor for intervals already observed (`nowcast`), times the county's
#' large-county `calibration` factor. Counties outside the continental grid
#' (Hawaii) use their observed loss cost.
#'
#' @param book Book of business from [build_prf_book()]; must include
#'   `baseline_year`.
#' @param baseline_year Last observed year to project from. Defaults to the
#'   year before [prf_policy_year()].
#' @param projection_window Number of years to project past `baseline_year`.
#' @param index Grid index history for expected payment factors, with columns
#'   `grid_id`, `year`, `interval_code`, and `index_value`, used for every
#'   projection year. When `NULL` (the default), each year uses the RMA
#'   release it is rated and paid on ([get_prf_index_rma()] for that crop
#'   year, or the latest release for later years): CPC data through 2026 and
#'   NCEI data from 2027, which pays systematically less on the same weather.
#' @param crosswalk Grid-to-county weights; see [prf_grid_county].
#' @param acreage_fit Grazing acreage model from [fit_prf_acreage()],
#'   fitted on the years up to `baseline_year` by default. `NULL` holds all
#'   acres at the baseline.
#' @param nowcast If `TRUE`, intervals of projection years with observed
#'   rainfall use their realized payment factors
#'   ([nowcast_payment_factors()]) instead of expected ones.
#' @param calibration Large-county calibration from [fit_prf_calibration()],
#'   or `NULL` for none.
#'
#' @return A `data.table` at the book grain with one row per projection year
#'   from `baseline_year` through `baseline_year + projection_window`, the
#'   projected outcomes, and `adm_year` (the ADM year whose values were used).
#'   The baseline year is included as a projection so growth from it can be
#'   measured. Attribute `indemnity_by_weather_year` holds national
#'   indemnity for each projection year under each weather year of its index
#'   history, for ranges around the expected value.
#' @seealso [prf_fcip_outlook()] to format the result for arpcFCIPproj.
#' @examples
#' \dontrun{
#' book <- build_prf_book(get_prf_sobtpu(baseline = 2025, window = 13))
#' calibration <- fit_prf_calibration(backtest_prf_book(book))
#' projection <- project_prf_book(book, baseline_year = 2025, calibration = calibration)
#' }
#' @export
project_prf_book <- function(book, baseline_year = prf_policy_year() - 1L,
                             projection_window = 10, index = NULL,
                             crosswalk = prf_grid_county,
                             acreage_fit = fit_prf_acreage(book, baseline_year),
                             nowcast = TRUE, calibration = NULL) {

  baseline_book <- book[commodity_year == baseline_year]

  if (nrow(baseline_book) == 0) {
    stop("`book` has no rows for ", baseline_year, ".", call. = FALSE)
  }

  years <- baseline_year:(baseline_year + projection_window)

  drivers <- prf_adm_driver_years(years, crosswalk)

  last_adm_year <- max(drivers$adm_year)

  projection <- rbindlist(lapply(years, function(year) {
    copy(baseline_book)[, `:=`(commodity_year = year, adm_year = min(year, last_adm_year))]
  }))

  # Dollar outcomes: acres, base values, rates, subsidy schedule. ADM calls
  # the premium rate base_rate; "baseline" here means the baseline year.
  driver_keys <- c("state_code", "county_code", "type_code", "practice_code",
                   "coverage_level_percent")

  projection[drivers[adm_year == baseline_year], on = driver_keys,
             `:=`(baseline_cbv = i.county_base_value, baseline_rate = i.base_rate)]

  projection[drivers, on = c(driver_keys, "adm_year"),
             `:=`(cbv = i.county_base_value, rate = i.base_rate,
                  subsidy_percent = i.subsidy_percent)]

  projection[, acre_ratio := 1]

  if (!is.null(acreage_fit)) {
    acre_ratios <- project_prf_acres(book, baseline_year, years, acreage_fit)
    projection[acre_ratios, on = c("state_code", "county_code", "type_code", "commodity_year"),
               acre_ratio := i.acre_ratio]
  }

  projection[, `:=`(
    cbv_ratio = fcoalesce(cbv / baseline_cbv, 1),
    rate_ratio = fcoalesce(rate / baseline_rate, 1),
    subsidy_percent = fcoalesce(subsidy_percent, subsidy_amount / total_premium_amount)
  )]

  projection[, `:=`(
    insured_acres = insured_acres * acre_ratio,
    liability_amount = liability_amount * acre_ratio * cbv_ratio,
    total_premium_amount = total_premium_amount * acre_ratio * cbv_ratio * rate_ratio
  )]

  projection[, subsidy_amount := total_premium_amount * subsidy_percent]

  # Payment factors: expected over the release's history, realized where
  # nowcast, observed loss cost where a county has no grids.
  coverage_levels <- unique(baseline_book$coverage_level_percent)

  latest_release <- if (is.null(index)) max(rma_index_releases()$crop_year) else 0L

  projection[, index_release := if (is.null(index)) as.integer(pmin(commodity_year, latest_release)) else 0L]

  weather_factors <- prf_weather_payment_factors(unique(projection$index_release),
                                                 coverage_levels, crosswalk, index)

  expected_factors <- weather_factors[, .(county_payment_factor = mean(county_payment_factor)),
                                      by = c(prf_payment_keys, "index_release")]

  projection[expected_factors, on = c(prf_payment_keys, "index_release"),
             county_payment_factor := i.county_payment_factor]

  projection[, `:=`(has_grids = !is.na(county_payment_factor), is_expected = TRUE)]

  if (nowcast) {
    realized_factors <- nowcast_payment_factors(years, coverage_levels, crosswalk)
    projection[realized_factors, on = c(prf_payment_keys, "commodity_year"),
               `:=`(county_payment_factor = i.county_payment_factor, is_expected = FALSE)]
  }

  observed_loss_cost <- book[commodity_year <= baseline_year,
                             .(loss_cost = sum(indemnity_amount) / sum(liability_amount)),
                             by = prf_payment_keys]

  projection[observed_loss_cost, on = prf_payment_keys,
             county_payment_factor := fcoalesce(county_payment_factor, i.loss_cost)]


  projection[, calibration_factor := 1]

  if (!is.null(calibration)) {
    projection[calibration, on = c("state_code", "county_code"),
               calibration_factor := i.calibration_factor]
  }

  projection[, scaled_liability := liability_amount * calibration_factor]
  projection[, indemnity_amount := scaled_liability * county_payment_factor]

  by_weather <- indemnity_by_weather_year(projection, weather_factors)

  projection[, c("baseline_cbv", "baseline_rate", "cbv", "rate", "subsidy_percent",
                 "acre_ratio", "cbv_ratio", "rate_ratio", "index_release",
                 "county_payment_factor", "has_grids", "is_expected", "calibration_factor",
                 "scaled_liability") := NULL]
  setattr(projection, "indemnity_by_weather_year", by_weather)
  projection[]
}

#' Format a PRF projection as an arpcFCIPproj preliminary outlook
#'
#' Stacks observed outcomes from the book with a projection and aggregates
#' them to county, in the layout of arpcFCIPproj's preliminary outlooks
#' (e.g. the input to `arpcFCIPproj::benchmark_fcip_outlook()`).
#'
#' @param book Book of business from [build_prf_book()].
#' @param projection Projection from [project_prf_book()].
#'
#' @return A `data.table` with `commodity_year`, `state_code`, `county_code`,
#'   `plan_group` (`"prf"`), `commodity_code`, `insurance_plan_code`,
#'   `insured_acres`, `liability_amount`, `total_premium_amount`,
#'   `subsidy_amount`, `indemnity_amount`, `.source` (`"observed"` for book
#'   years through the baseline, `"projected"` from the baseline on), and
#'   `unit_structure_code` (`"OU"`).
#' @examples
#' \dontrun{
#' outlook <- prf_fcip_outlook(book, project_prf_book(book))
#' }
#' @export
prf_fcip_outlook <- function(book, projection) {

  baseline_year <- min(projection$commodity_year)

  outlook <- rbind(
    book[commodity_year <= baseline_year][, .source := "observed"],
    copy(projection)[, .source := "projected"],
    fill = TRUE
  )

  outlook_keys <- c("commodity_year", "state_code", "county_code",
                    "commodity_code", "insurance_plan_code", ".source")

  outlook <- outlook[, lapply(.SD, sum, na.rm = TRUE), by = outlook_keys,
                     .SDcols = prf_outcome_cols]

  outlook[, `:=`(plan_group = "prf", unit_structure_code = "OU")]

  setcolorder(outlook, c("commodity_year", "state_code", "county_code", "plan_group",
                         "commodity_code", "insurance_plan_code", prf_outcome_cols,
                         ".source", "unit_structure_code"))
                         
  setorder(outlook, .source, commodity_year, state_code, county_code)
  setattr(outlook, "indemnity_by_weather_year", attr(projection, "indemnity_by_weather_year"))
  outlook[]
}
