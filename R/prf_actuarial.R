# PRF actuarial data from RMA's Actuarial Data Master (ADM), via rfcip.
#
# PRF ADM records live in:
#   A00810 Price              county base values and interval acre limits,
#                             one row per insurance offer x grid
#   A01130 AreaCoverageLevel  coverage levels per offer x grid -> area_rate_id
#   A01135 AreaRate           premium rate (base_rate) per area_rate_id
#   A00070 SubsidyPercent     subsidy schedule for plan 13 (not crop-specific)
#   A00540 / A00510           type and practice names
# Grids are stored in sub_county_code. rfcip returns many codes as factors,
# which are converted to character or integer here.

# Columns identifying a PRF offer on a grid.
prf_offer_keys <- c(
  "commodity_year", "state_code", "county_code", "grid_id",
  "type_code", "type_name", "practice_code", "practice_name",
  "irrigation_practice_code", "organic_practice_code", "interval_code",
  "adm_insurance_offer_id"
)

# One ADM table for one year as a data.table, from rfcip or, for the years in
# rma_adm_years, directly from RMA (R/prf_adm_rma.R). With key_cols, keeps
# only the latest release of any record RMA re-released within the year.
read_adm <- function(year, dataset, key_cols = NULL) {

  adm <- if (year %in% rma_adm_years) {
    read_adm_rma(year, dataset)
  } else {
    setDT(rfcip::get_adm_data(year = year, dataset = dataset, show_progress = FALSE))
  }
  if (!is.null(key_cols)) {
    setorderv(adm, "released_date", order = -1L, na.last = TRUE)
    adm <- unique(adm, by = key_cols)
  }

  adm
}

# Run a single-year function over each year and stack the results.
by_year <- function(year, fun) {

  check_years(year)

  rbindlist(lapply(year, fun), use.names = TRUE)

}

prf_county_base_values_year <- function(year) {

  price <- read_adm(year, "A00810_Price",
                    c("adm_insurance_offer_id", "sub_county_code"))

  price <- price[commodity_code == prf_crop_code &
                   insurance_plan_code == prf_plan_code]

  price[, `:=`(
    grid_id = as.character(sub_county_code),
    interval_code = as.integer(as.character(interval_code)),
    irrigation_practice_code = as.character(irrigation_practice_code),
    organic_practice_code = as.character(organic_practice_code)
  )]

  types <- read_adm(year, "A00540_Type", c("commodity_code", "type_code"))[
    commodity_code == prf_crop_code]

  practices <- read_adm(year, "A00510_Practice", c("commodity_code", "practice_code"))[
    commodity_code == prf_crop_code]

  price[types, on = "type_code", type_name := as.character(i.type_name)]

  price[practices, on = "practice_code",
        practice_name := as.character(i.practice_name)]

  price[, c(prf_offer_keys, "county_base_value", "minimum_acre_percent",
            "maximum_acre_percent"), with = FALSE]

}

# Expand offers (one row per offer x grid) to one row per coverage level with
# its premium rate, via AreaCoverageLevel -> AreaRate.
add_premium_rates <- function(offers, year) {

  coverage <- read_adm(year, "A01130_AreaCoverageLevel",
                       c("adm_insurance_offer_id", "sub_county_code",
                         "coverage_level_percent", "coverage_type_code"))

  coverage <- coverage[adm_insurance_offer_id %in% offers$adm_insurance_offer_id]

  coverage[, `:=`(grid_id = as.character(sub_county_code),
                  coverage_type_code = as.character(coverage_type_code))]

  rates <- read_adm(year, "A01135_AreaRate", "area_rate_id")

  coverage[rates, on = "area_rate_id", base_rate := i.base_rate]

  coverage <- coverage[, .(adm_insurance_offer_id, grid_id, coverage_level_percent,
                           coverage_type_code, base_rate)]

  rated <- merge(offers, coverage, by = c("adm_insurance_offer_id", "grid_id"),
                 sort = FALSE)

  setcolorder(rated, names(offers))
}

prf_premium_rates_year <- function(year) {

  offers <- prf_county_base_values_year(year)[, prf_offer_keys, with = FALSE]
  add_premium_rates(offers, year)

}

prf_subsidy_rates_year <- function(year) {

  subsidy <- read_adm(year, "A00070_SubsidyPercent",
                      c("insurance_plan_code", "coverage_level_percent",
                        "coverage_type_code"))

  # PRF commodity years coincide with reinsurance years.
  subsidy <- subsidy[insurance_plan_code == prf_plan_code,
                     .(commodity_year = reinsurance_year, coverage_level_percent,
                       coverage_type_code = as.character(coverage_type_code),
                       subsidy_percent)]

  subsidy[order(coverage_type_code, coverage_level_percent)]
}

prf_actuarial_year <- function(year) {

  actuarial <- add_premium_rates(prf_county_base_values_year(year), year)

  actuarial[prf_subsidy_rates_year(year),
            on = c("commodity_year", "coverage_level_percent", "coverage_type_code"),
            subsidy_percent := i.subsidy_percent]

  actuarial
}

#' Get PRF county base values
#'
#' County base values and interval acre-allocation limits for Pasture,
#' Rangeland, Forage, from the ADM Price table (A00810).
#'
#' @param year Commodity (policy) year(s). Defaults to [prf_policy_year()].
#'
#' @return A `data.table` with one row per year, grid, type, practice, and
#'   interval, with columns `county_base_value` (dollars per acre) and
#'   `minimum_acre_percent` / `maximum_acre_percent` (limits on the share of
#'   insured acres allocated to an interval).
#' @seealso [get_prf_actuarial()] for base values, premium rates, and subsidies
#'   in one table.
#' @examples
#' \dontrun{
#' get_prf_county_base_values(2026)
#' }
#' @export
get_prf_county_base_values <- function(year = prf_policy_year()) {

  by_year(year, prf_county_base_values_year)

}

#' Get PRF premium rates
#'
#' Premium rates by grid, type, practice, interval, and coverage level for
#' Pasture, Rangeland, Forage, from the ADM Area Coverage Level (A01130) and
#' Area Rate (A01135) tables.
#'
#' @inheritParams get_prf_county_base_values
#'
#' @return A `data.table` with the offer key columns, `coverage_level_percent`,
#'   `coverage_type_code`, and `base_rate` (premium rate before subsidy and
#'   productivity factor).
#' @examples
#' \dontrun{
#' get_prf_premium_rates(2026)
#' }
#' @export
get_prf_premium_rates <- function(year = prf_policy_year()) {

  by_year(year, prf_premium_rates_year)

}

#' Get PRF premium subsidy schedule
#'
#' Premium subsidy percentages by coverage level for the Rainfall Index plan
#' (plan 13), from the ADM Subsidy Percent table (A00070).
#'
#' @inheritParams get_prf_county_base_values
#'
#' @return A `data.table` with `commodity_year`, `coverage_level_percent`,
#'   `coverage_type_code` (`"A"` buy-up, `"C"` catastrophic), and
#'   `subsidy_percent`.
#' @examples
#' \dontrun{
#' get_prf_subsidy_rates(2026)
#' }
#' @export
get_prf_subsidy_rates <- function(year = prf_policy_year()) {

  by_year(year, prf_subsidy_rates_year)

}

#' Get PRF actuarial data
#'
#' County base values, premium rates, and subsidy percentages for Pasture,
#' Rangeland, Forage joined into one table. The productivity factor (60 to 150
#' percent) is elected by the producer and is not part of the ADM.
#'
#' @inheritParams get_prf_county_base_values
#'
#' @return A `data.table` with one row per year, grid, type, practice,
#'   interval, and coverage level, combining the columns of
#'   [get_prf_county_base_values()], [get_prf_premium_rates()], and
#'   [get_prf_subsidy_rates()].
#' @examples
#' \dontrun{
#' act <- get_prf_actuarial(2026)
#' act[grid_id == "25330" & type_name == "Grazing" & coverage_level_percent == 0.9]
#' }
#' @export
get_prf_actuarial <- function(year = prf_policy_year()) {

  by_year(year, prf_actuarial_year)
  
}
