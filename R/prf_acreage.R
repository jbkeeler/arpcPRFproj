# Insured grazing acres by partial adjustment toward a ceiling.
#
# Each year a county closes a fixed share (the adjustment speed) of the gap
# between its insured grazing acres and a ceiling: its state's saturation
# share of the county's eligible grazing acres.
#
#   acres(t + 1) = acres(t) + speed x max(0, ceiling x eligible - acres(t))
#
# Eligible grazing acres are Census of Agriculture pastureland plus federal
# land in BLM and Forest Service grazing allotments, which PRF insures but the
# Census leaves out. The speed is common to all states; ceilings are by state
# (states with few counties share one), capped at all eligible acres. Both
# are estimated from the last few years of county acreage changes.
#
# Haying acres grow at the same rate as their state's grazing acres: Census
# hay acres do not identify a haying ceiling, but haying has tracked grazing
# enrollment, at 20-27 haying acres per 1,000 grazing acres nationally since
# 2019.

# Eligible grazing acres by county.
prf_eligible_acres <- function() {

  census <- prf_county_forage_acres[census_year == max(census_year)]

  eligible <- merge(census, prf_county_allotment_acres,
                    by = c("state_code", "county_code"), all.x = TRUE)

  eligible[, .(state_code, county_code,
               eligible_acres = pasture_acres + fcoalesce(blm_acres, 0) +
                 fcoalesce(usfs_acres, 0))]
}

# Insured grazing acres by county and year, with eligible acres.
prf_grazing_acres <- function(book) {

  grazing <- book[type_code == 7, .(acres = sum(insured_acres)),
                  keyby = .(state_code, county_code, commodity_year)]

  grazing <- merge(grazing, prf_eligible_acres(), by = c("state_code", "county_code"))

  setkey(grazing, state_code, county_code, commodity_year)
}

#' Fit the PRF grazing acreage model
#'
#' Estimates how fast insured grazing acres approach their ceiling from the
#' year-to-year change in each county's acres: regressing the change, as a
#' share of eligible acres, on the prior year's penetration (insured /
#' eligible acres) with a state intercept gives
#'
#' `change / eligible = speed x (ceiling - penetration)`.
#'
#' Eligible acres are Census pastureland ([prf_county_forage_acres]) plus
#' federal grazing allotments ([prf_county_allotment_acres]). Counties are
#' weighted by eligible acres. Ceilings are capped at 1 (all eligible acres);
#' states with fewer than `min_counties` county-years share one ceiling.
#'
#' @param book Book of business from [build_prf_book()].
#' @param baseline_year Last year of acreage changes to fit.
#' @param fit_years Number of yearly changes to fit, ending at
#'   `baseline_year`.
#' @param min_counties Minimum county-years for a state's own ceiling.
#'
#' @return A `data.table` with `state_code` (`0` for the pooled states),
#'   `ceiling` (share of eligible acres), and `speed` (share of the gap to
#'   the ceiling closed each year, common to all states).
#' @seealso [project_prf_acres()].
#' @examples
#' \dontrun{
#' book <- build_prf_book(get_prf_sobtpu(baseline = 2025, window = 13))
#' fit_prf_acreage(book, baseline_year = 2025)
#' }
#' @export
fit_prf_acreage <- function(book, baseline_year, fit_years = 3, min_counties = 10) {

  grazing <- prf_grazing_acres(book)

  grazing[, `:=`(prior_acres = shift(acres), prior_year = shift(commodity_year)),
          by = .(state_code, county_code)]

  changes <- grazing[prior_year == commodity_year - 1 & eligible_acres > 0 &
                       commodity_year > baseline_year - fit_years &
                       commodity_year <= baseline_year]

  changes[, `:=`(change = (acres - prior_acres) / eligible_acres,
                 penetration = prior_acres / eligible_acres)]

  changes[, state_group := factor(fifelse(.N >= min_counties, state_code, 0)),
          by = state_code]

  model <- stats::lm(change ~ 0 + state_group + penetration, data = changes,
                     weights = eligible_acres)

  speed <- -stats::coef(model)[["penetration"]]

  intercepts <- stats::coef(model)[-length(stats::coef(model))]

  data.table(state_code = as.numeric(sub("state_group", "", names(intercepts))),
             ceiling = pmin(1, intercepts / speed),
             speed = speed)
}

#' Project PRF insured acres
#'
#' Projects each county's insured grazing acres from the baseline year with
#' the partial adjustment model from [fit_prf_acreage()]. Haying acres grow
#' at the same rate as their state's grazing acres. Grazing acres in counties
#' without eligible
#' acres (e.g. withheld from the Census) are held at the baseline, as is
#' haying in states with no modeled grazing.
#'
#' @param book Book of business from [build_prf_book()].
#' @param baseline_year Year to project from.
#' @param years Projection years after `baseline_year`.
#' @param acreage_fit Output of [fit_prf_acreage()].
#'
#' @return A `data.table` with `state_code`, `county_code`, `type_code`
#'   (7 grazing, 30 haying), `commodity_year`, and `acre_ratio` (projected /
#'   baseline acres). Counties and types not listed stay at the baseline.
#' @examples
#' \dontrun{
#' fit <- fit_prf_acreage(book, baseline_year = 2025)
#' project_prf_acres(book, 2025, 2026:2035, fit)
#' }
#' @export
project_prf_acres <- function(book, baseline_year, years, acreage_fit) {

  county <- prf_grazing_acres(book)[commodity_year == baseline_year & acres > 0 & eligible_acres > 0]

  county[, state_group := fifelse(state_code %in% acreage_fit$state_code, state_code, 0)]

  county[acreage_fit, on = c(state_group = "state_code"),
         `:=`(ceiling = i.ceiling, speed = i.speed)]

  county[, baseline_acres := acres]

  grazing <- rbindlist(lapply(seq_len(max(years) - baseline_year), function(step) {
    county[, acres := acres + speed * pmax(0, ceiling * eligible_acres - acres)]
    county[, .(state_code, county_code, commodity_year = baseline_year + step,
               acres, baseline_acres)]
  }))[commodity_year %in% years]

  # Haying follows its state's grazing growth. County grazing ratios would
  # overstate it: haying is concentrated in counties with small grazing books
  # far below their ceilings.
  state <- grazing[, .(acre_ratio = sum(acres) / sum(baseline_acres)),
                   by = .(state_code, commodity_year)]

  haying <- unique(book[type_code == 30 & commodity_year == baseline_year,
                        .(state_code, county_code)])
                        
  haying <- merge(haying, state, by = "state_code", allow.cartesian = TRUE)

  rbind(
    grazing[, .(state_code, county_code, type_code = 7, commodity_year,
                acre_ratio = acres / baseline_acres)],
    haying[, .(state_code, county_code, type_code = 30, commodity_year, acre_ratio)]
  )
}
