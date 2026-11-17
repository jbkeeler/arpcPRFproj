# Constants and helpers shared across the package.

# RMA codes for Pasture, Rangeland, Forage and its Rainfall Index plan.
prf_crop_code <- 88
prf_plan_code <- 13

#' Current PRF policy year
#'
#' PRF sales close December 1 for the following crop year, so from December 1
#' onward the policy year is the next calendar year.
#'
#' @param date A `Date`. Defaults to today.
#' @return An integer policy year.
#' @examples
#' prf_policy_year(as.Date("2026-11-30")) # 2026
#' prf_policy_year(as.Date("2026-12-01")) # 2027
#' @export
prf_policy_year <- function(date = Sys.Date()) {
  year <- as.integer(format(date, "%Y"))
  if (format(date, "%m-%d") >= "12-01") year + 1L else year
}

is_whole_number <- function(x) {
  is.numeric(x) && all(x %% 1 == 0)
}

check_years <- function(year) {
  stopifnot("`year` must be a numeric vector of years." =
              length(year) >= 1 && is_whole_number(year))
}

# NULL means "use the default".
check_crop_year <- function(crop_year) {
  stopifnot("`crop_year` must be a single crop year." =
              is.null(crop_year) || (length(crop_year) == 1 && is_whole_number(crop_year)))
}
