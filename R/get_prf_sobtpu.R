#' Get PRF Summary of Business by type, practice, and unit history
#'
#' Downloads RMA's Summary of Business by type, practice, and unit structure
#' (SOB-TPU) for Pasture, Rangeland, Forage (crop code 88) over a window of
#' policy years ending at `baseline`, using [rfcip::get_sob_data()].
#'
#' @param baseline Last policy year in the window. Defaults to
#'   [prf_policy_year()].
#' @param window Number of policy years to pull, ending at and including
#'   `baseline`.
#' @param ... Passed to [rfcip::get_sob_data()], e.g. `state`, `cov_lvl`,
#'   `force`.
#'
#' @return A `data.table` covering policy years
#'   `(baseline - window + 1):baseline`.
#' @examples
#' \dontrun{
#' get_prf_sobtpu()
#' get_prf_sobtpu(baseline = 2025, window = 10, state = "ND")
#' }
#' @export
get_prf_sobtpu <- function(baseline = prf_policy_year(), window = 5, ...) {

  stopifnot(
    "`baseline` must be a single year." =
      length(baseline) == 1 && is_whole_number(baseline),
    "`window` must be a positive whole number." =
      length(window) == 1 && is_whole_number(window) && window >= 1
  )

  years <- seq(baseline - window + 1, baseline)

  sobtpu <- rfcip::get_sob_data(year = years, crop = prf_crop_code,
                                sob_version = "sobtpu", ...)
                                
  setDT(sobtpu)[]
}
