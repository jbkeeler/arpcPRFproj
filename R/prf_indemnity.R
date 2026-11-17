# Indemnity pieces of the projection: payment factors by weather year, the
# nowcast of years with observed rainfall, and the large-county calibration.
#
# Expected indemnity = liability x the mean payment factor over the rainfall
# history of the index release the year is rated on. The same history gives a
# range: the book paid out under each past year's rainfall (spatial pattern
# across counties kept intact). Intervals of the projection years that have
# already been observed replace their expected factors with realized ones.

# County payment factors for every weather year in each index release
# (release 0 = the supplied index).
prf_weather_payment_factors <- function(releases, coverage_levels, crosswalk, index = NULL) {

  rbindlist(lapply(releases, function(release) {

    release_index <- if (release == 0L) index else get_prf_index_rma(crop_year = release)

    get_county_payment_factors(release_index, coverage_levels = coverage_levels,
    
                               crosswalk = crosswalk)[, index_release := release]
  }))

}

#' Nowcast PRF payment factors from observed rainfall
#'
#' County payment factors for each year in `years` that has observed rainfall,
#' from the NCEI index ([get_prf_index_ncei()]) measured against that year's
#' normal (`crop_year = year`). Only intervals with final data for both months
#' are returned, so a year in progress has its completed intervals only.
#'
#' Through 2026 PRF was paid on CPC rather than NCEI data. On 2026's paid
#' intervals (January-June), NCEI-based payments came to 0.945 of SOB
#' indemnity before the large-county calibration, so no adjustment for the
#' data source is made.
#'
#' @param years Years to nowcast; years without observed rainfall are skipped.
#' @param coverage_levels Coverage levels to compute, as proportions.
#' @param crosswalk Grid-to-county weights; see [prf_grid_county].
#'
#' @return A `data.table` with `state_code`, `county_code`, `commodity_year`,
#'   `interval_code`, `coverage_level_percent`, and `county_payment_factor`.
#' @examples
#' \dontrun{
#' nowcast_payment_factors(2026, coverage_levels = c(0.7, 0.9))
#' }
#' @export
nowcast_payment_factors <- function(years, coverage_levels, crosswalk = prf_grid_county) {

  last_observed <- max(ncei_listing()$year)

  years <- years[years <= last_observed]

  factors <- rbindlist(lapply(years, function(year) {
    index <- get_prf_index_ncei(crop_year = year, year = year)
    get_county_payment_factors(index[, .(grid_id, year, interval_code, index_value)],
                               coverage_levels = coverage_levels, crosswalk = crosswalk)
  }))

  setnames(factors, "year", "commodity_year")[]

}

#' Fit the large-county indemnity calibration
#'
#' Area-weighted payment factors understate indemnities in counties with many
#' grids (about 0.92-0.95 of SOB in counties with more than 20 grids), likely
#' because insured land is not spread evenly across large counties. The
#' calibration scales each county's indemnity by its backtest ratio of actual
#' to predicted indemnity, shrunk toward the ratio for counties of its size:
#'
#' `calibration_factor = (actual + k x size ratio) / (predicted + k)`
#'
#' Counties with little predicted indemnity relative to `k` get mostly the
#' size-class ratio. `k` is chosen by two-fold cross-validation (fit on even
#' years, score on odd, and the reverse), minimizing the liability-weighted
#' error in county loss cost. Counties without backtest history get their
#' size-class ratio.
#'
#' The calibration is separate from the projection: pass it to
#' [project_prf_book()] or leave it out.
#'
#' @param backtest Output of [backtest_prf_book()].
#' @param crosswalk Grid-to-county weights; see [prf_grid_county].
#' @param k Shrinkage, in dollars of predicted indemnity. `NULL` chooses it
#'   from `k_candidates` by cross-validation.
#' @param k_candidates Values of `k` to try.
#'
#' @return A `data.table` with `state_code`, `county_code`, `grid_class`, and
#'   `calibration_factor`, with attribute `k`.
#' @examples
#' \dontrun{
#' calibration <- fit_prf_calibration(backtest_prf_book(book))
#' attr(calibration, "k")
#' }
#' @export
fit_prf_calibration <- function(backtest, crosswalk = prf_grid_county, k = NULL,
                                k_candidates = c(1, 2, 4, 8, 16, 32) * 1e6) {

  county_years <- merge(

    backtest[, .(actual = sum(indemnity_amount), predicted = sum(predicted_indemnity),
                 liability = sum(liability_amount)),
             by = .(state_code, county_code, commodity_year)],

    county_grid_classes(crosswalk)[, .(state_code, county_code, grid_class)],

    by = c("state_code", "county_code")
  )


  if (is.null(k)) {

    cv_error <- sapply(k_candidates, function(candidate) {
      sum(sapply(0:1, function(fold) {
        train <- county_years[commodity_year %% 2 == fold]
        test <- county_years[commodity_year %% 2 != fold,
                             .(actual = sum(actual), predicted = sum(predicted),
                               liability = sum(liability)), by = .(state_code, county_code)]
        test[calibration_factors(train, candidate, crosswalk), on = c("state_code", "county_code"),
             calibration_factor := i.calibration_factor]
        test[, sum(abs(actual - fcoalesce(calibration_factor, 1) * predicted))]
      }))
    })

    k <- k_candidates[which.min(cv_error)]

  }

  calibration <- calibration_factors(county_years, k, crosswalk)

  setattr(calibration, "k", k)
}

# Calibration factors for every county in the crosswalk from county-year
# backtest totals.
calibration_factors <- function(county_years, k, crosswalk) {

  size_ratio <- county_years[, .(size_ratio = sum(actual) / sum(predicted)), by = grid_class]

  county <- county_years[, .(actual = sum(actual), predicted = sum(predicted)),
                         by = .(state_code, county_code)]

  factors <- county_grid_classes(crosswalk)[, .(state_code, county_code, grid_class)]

  factors[size_ratio, on = "grid_class", size_ratio := i.size_ratio]

  factors[county, on = c("state_code", "county_code"),
          `:=`(actual = i.actual, predicted = i.predicted)]

  factors[, calibration_factor := fifelse(is.na(predicted), size_ratio,
                                          (actual + k * size_ratio) / (predicted + k))]

  factors[, .(state_code, county_code, grid_class,
              calibration_factor = fcoalesce(calibration_factor, 1))]
}

# National indemnity for each projection year under each weather year of its
# index release. Cells with a nowcast or no grid payment factors (Hawaii)
# contribute their fixed indemnity to every weather year.
indemnity_by_weather_year <- function(projection, weather_factors) {

  rbindlist(lapply(unique(projection$commodity_year), function(projection_year) {

    cells <- projection[commodity_year == projection_year]

    varies_by_weather <- cells$is_expected & cells$has_grids

    fixed_indemnity <- sum(cells$indemnity_amount[!varies_by_weather])

    merge(cells[varies_by_weather, c(prf_payment_keys, "index_release", "scaled_liability"),
                with = FALSE],
          weather_factors, by = c(prf_payment_keys, "index_release"))[
      , .(commodity_year = projection_year,
          indemnity_amount = sum(scaled_liability * county_payment_factor) + fixed_indemnity),
      keyby = .(weather_year = year)]

  }))

}
