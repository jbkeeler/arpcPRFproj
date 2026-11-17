# PRF book of business from the Summary of Business by type, practice, and
# unit (SOB-TPU), at the grain PRF projections work on: county x type x
# practice x interval x coverage level.
#
# SOB carries the index interval only in the practice name ("Jan - Feb Index
# Interval (Irrigated)"), so the interval code is parsed from it. Rows whose
# practice is not a two-month interval (the three-month intervals of the pilot
# years, "No Practice Specified") carry no liability from 2012 on and drop out.

prf_outcome_cols <- c("insured_acres", "liability_amount", "total_premium_amount",
                      "subsidy_amount", "indemnity_amount")

# Columns that define one row of the book.
prf_book_keys <- c("commodity_year", "state_code", "state_abbreviation", "county_code",
                   "commodity_code", "insurance_plan_code", "type_code", "type_name",
                   "practice_code", "practice_name", "interval_code",
                   "coverage_type_code", "coverage_level_percent")

# Interval code (625 Jan-Feb ... 635 Nov-Dec) from a practice name, or NA when
# the name is not a two-month interval.
interval_from_practice_name <- function(practice_name) {
  # "Jan - Feb Index Interval (Irrigated)" -> "JAN-FEB". Early years are in
  # upper case.
  interval_name <- gsub(" ", "", sub(" INDEX INTERVAL.*", "", toupper(practice_name)))
  prf_intervals$interval_code[match(interval_name, toupper(prf_intervals$interval_name))]
}

#' Build the PRF book of business
#'
#' Aggregates SOB-TPU records for Pasture, Rangeland, Forage to county, type,
#' practice, index interval, and coverage level.
#'
#' @param sobtpu SOB-TPU records as returned by [get_prf_sobtpu()].
#'
#' @return A `data.table` with `commodity_year`, `state_code`,
#'   `state_abbreviation`, `county_code`,
#'   `commodity_code`, `insurance_plan_code`, `type_code`, `type_name`,
#'   `practice_code`, `practice_name`, `interval_code`, `coverage_type_code`,
#'   `coverage_level_percent`, and the summed outcomes `insured_acres`,
#'   `liability_amount`, `total_premium_amount`, `subsidy_amount`, and
#'   `indemnity_amount`.
#' @examples
#' \dontrun{
#' book <- build_prf_book(get_prf_sobtpu(baseline = 2025, window = 10))
#' }
#' @export
build_prf_book <- function(sobtpu = get_prf_sobtpu()) {

  sobtpu <- as.data.table(sobtpu)[liability_amount > 0]

  sobtpu[, interval_code := interval_from_practice_name(practice_name)]

  sobtpu <- sobtpu[!is.na(interval_code)]
  
  setnames(sobtpu, "net_reporting_level_amount", "insured_acres")

  sobtpu[, lapply(.SD, sum), by = prf_book_keys, .SDcols = prf_outcome_cols]
}
