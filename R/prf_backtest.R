# Backtest of the indemnity side of the projection: each observed year's book
# is paid out on that year's actual index values, using the same grid-to-
# county weights as the projection, and compared with SOB indemnities.
#
# RMA rates and pays crop year t against a normal running through t - 2. One
# release holds every year's precipitation divided by a single normal, so
# dividing a year's values by their mean over normal_start..t - 2 re-expresses
# them against the normal that year was paid on.

# Index values for each of `years`, each against its own normal.
rebase_prf_index <- function(index, years, normal_start) {

  rbindlist(lapply(years, function(y) {

    normal <- index[year >= normal_start & year <= y - 2L,
                    .(normal = mean(index_value)), by = .(grid_id, interval_code)]

    index[year == y][normal, on = c("grid_id", "interval_code"), nomatch = NULL][
      , .(grid_id, year, interval_code, index_value = round_prf_index(index_value / normal))]

  }))

}

#' Backtest PRF indemnities against the Summary of Business
#'
#' Predicts each observed year's indemnities from that year's rainfall index
#' values: liability times the county's area-weighted payment factor, the
#' same mechanics [project_prf_book()] uses for expected indemnities. Index
#' values are re-expressed against each year's own normal (the years from the
#' start of the index through two years before). Counties without grids
#' (Hawaii) are dropped.
#'
#' @param book Book of business from [build_prf_book()].
#' @param index Grid index history from one release, with columns `grid_id`,
#'   `year`, `interval_code`, and `index_value`. Defaults to RMA's 2026
#'   release, the last built on NOAA CPC data, which PRF paid on through 2026
#'   and which covers 1948-2024. The NCEI-based releases from 2027 on give
#'   systematically lower payments for the same years, so they do not
#'   reproduce historical indemnities.
#'
#'   The 2026 release ends at 2024, so as the book window moves forward the
#'   backtest covers fewer years, and none once the book starts after 2024.
#'   Years from 2027 on, paid on NCEI data, need to be backtested against an
#'   NCEI release instead.
#' @param crosswalk Grid-to-county weights; see [prf_grid_county].
#'
#' @return The book rows for years covered by `index`, with `county_payment_factor`
#'   and `predicted_indemnity` added.
#' @seealso [plot_prf_backtest()].
#' @examples
#' \dontrun{
#' book <- build_prf_book(get_prf_sobtpu(baseline = 2025, window = 13))
#' backtest <- backtest_prf_book(book)
#' backtest[, sum(predicted_indemnity) / sum(indemnity_amount)]
#' }
#' @export
backtest_prf_book <- function(book, index = get_prf_index_rma(crop_year = 2026),
                              crosswalk = prf_grid_county) {

  index <- as.data.table(index)

  normal_start <- min(index$year)
  
  # TODO: the default CPC release ends at 2024, so this shrinks with each new
  # baseline. Backtest 2027+ book years against an NCEI release.
  years <- intersect(sort(unique(book$commodity_year)), unique(index$year))

  years <- years[years - 2L >= normal_start]

  if (length(years) == 0) stop("`index` covers none of the book's years.", call. = FALSE)

  factors <- get_county_payment_factors(
    rebase_prf_index(index, years, normal_start),
    coverage_levels = unique(book$coverage_level_percent), crosswalk = crosswalk
  )

  setnames(factors, "year", "commodity_year")

  backtest <- merge(book[commodity_year %in% years], factors,
                    by = c(prf_payment_keys, "commodity_year"))
                    
  backtest[, predicted_indemnity := liability_amount * county_payment_factor]
  setorder(backtest, commodity_year, state_code, county_code, interval_code)
  backtest[]
}
