# County PRF payment factors from grid index values.
#
# PRF pays on each grid when the interval index falls below the coverage
# level. Payment factors are computed per grid and then averaged across a
# county's grids; averaging the index first would smooth out dry grids and
# understate payments.

# Columns a county payment factor varies by, apart from year.
prf_payment_keys <- c("state_code", "county_code", "interval_code", "coverage_level_percent")

#' Grid × county crosswalk for PRF
#'
#' The share of each county's area that falls in each PRF grid cell, from the
#' intersection of RMA's official Rainfall Index grid with Census county
#' boundaries (2020, plus Connecticut's 2023 planning regions) in an
#' equal-area projection. Continental US only. Built by
#' `data-raw/prf_grid_county.R`.
#'
#' @format A `data.table` with one row per county and grid:
#' \describe{
#'   \item{state_code, county_code}{FIPS codes.}
#'   \item{grid_id}{RMA grid ID (GRIDCODE), as character.}
#'   \item{area_km2}{Area of the county inside the grid cell.}
#'   \item{weight}{`area_km2` as a share of the county's area; sums to 1
#'     within a county.}
#' }
"prf_grid_county"

#' PRF payment factor
#'
#' The share of an interval's protection paid out:
#' `max(0, (coverage_level - index_value) / coverage_level)`.
#'
#' @param index_value Rainfall index value (1 = normal).
#' @param coverage_level Coverage level as a proportion, e.g. `0.9`.
#'
#' @return Payment factors between 0 and 1.
#' @examples
#' prf_payment_factor(c(0.5, 0.9, 1.2), 0.9) # 0.444, 0, 0
#' @export
prf_payment_factor <- function(index_value, coverage_level) {
  pmax(0, (coverage_level - index_value) / coverage_level)
}

#' County PRF payment factors
#'
#' Computes grid payment factors from index values and averages them across
#' each county's grids, weighted by the area each grid covers. Grids without
#' an index value for a year and interval are left out and the remaining
#' weights rescaled.
#'
#' @param index Grid index values with columns `grid_id`, `year`,
#'   `interval_code`, and `index_value`, e.g. from [get_prf_index()]. Use
#'   values from a single `crop_year` (normal).
#' @param coverage_levels Coverage levels to compute, as proportions.
#' @param crosswalk Grid-to-county weights; see [prf_grid_county].
#'
#' @return A `data.table` with `state_code`, `county_code`, `year`,
#'   `interval_code`, `coverage_level_percent`, and `county_payment_factor`.
#' @seealso [expected_payment_factors()] to average them over years.
#' @examples
#' \dontrun{
#' index <- get_prf_index("ncei", year = 2026)
#' get_county_payment_factors(index)
#' }
#' @export
get_county_payment_factors <- function(index,
                                       coverage_levels = c(0.70, 0.75, 0.80, 0.85, 0.90),
                                       crosswalk = prf_grid_county) {
  stopifnot("`index` must have one crop_year (normal)." =
              !"crop_year" %in% names(index) || uniqueN(index$crop_year) == 1)

  # One row per grid x county, with the grid's share of the county.
  grid_index <- merge(as.data.table(index)[, .(grid_id, year, interval_code, index_value)],
                      crosswalk[, .(state_code, county_code, grid_id, weight)],
                      by = "grid_id", allow.cartesian = TRUE)

  factors <- rbindlist(lapply(coverage_levels, function(level) {
    grid_index[, .(coverage_level_percent = level,
                   county_payment_factor = sum(weight * prf_payment_factor(index_value, level)) /
                     sum(weight)),
               by = .(state_code, county_code, year, interval_code)]
  }))
  setkey(factors, state_code, county_code, year, interval_code, coverage_level_percent)
  factors[]
}

#' Expected PRF payment factors
#'
#' Averages county payment factors over years: the expected share of
#' protection paid out by county, interval, and coverage level.
#'
#' @param payment_factors Output of [get_county_payment_factors()].
#' @param year Optional years to average over. Defaults to all years present.
#'
#' @return A `data.table` with `state_code`, `county_code`, `interval_code`,
#'   `coverage_level_percent`, `expected_payment_factor`, and `years` (the
#'   number of years averaged).
#' @examples
#' \dontrun{
#' index <- get_prf_index("rma", crop_year = 2027)
#' expected_payment_factors(get_county_payment_factors(index))
#' }
#' @export
expected_payment_factors <- function(payment_factors, year = NULL) {
  years <- year
  if (!is.null(years)) payment_factors <- payment_factors[year %in% years]
  payment_factors[, .(expected_payment_factor = mean(county_payment_factor), years = .N),
                  keyby = prf_payment_keys]
}
