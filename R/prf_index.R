# PRF rainfall index values from either source, plus pieces both share.
#
# Sources:
#   rma   RMA's published history, one release per crop year
#         (R/prf_index_rma.R). Releases through 2026 are built on NOAA CPC
#         data, from 2027 on NCEI.
#   ncei  Computed from NCEI monthly precipitation (R/prf_index_ncei.R).
#         Matches RMA's 2027 release exactly and adds the current year's
#         intervals, which RMA's releases omit.

#' PRF index intervals
#'
#' The eleven two-month PRF index intervals and their calendar months.
#'
#' @format A `data.table` with columns `interval_code` (625-635),
#'   `interval_name`, `month1`, and `month2`.
#' @export
prf_intervals <- data.table(
  interval_code = 625:635,
  interval_name = paste(month.abb[1:11], month.abb[2:12], sep = "-"),
  month1 = 1:11,
  month2 = 2:12
)

# RMA publishes the index rounded half up to three decimals; the epsilon
# keeps ties such as 1.5395 from flooring on floating-point error.
round_prf_index <- function(x) floor(x * 1000 + 0.5 + 1e-9) / 1000

# Copies avoid name clashes between arguments and columns in i.
filter_prf_index <- function(index, year = NULL, grid_id = NULL,
                             interval_code = NULL) {

  years <- year
  grids <- grid_id
  intervals <- interval_code

  if (!is.null(years)) index <- index[year %in% years]

  if (!is.null(grids)) index <- index[grid_id %in% as.character(grids)]

  if (!is.null(intervals)) index <- index[interval_code %in% intervals]

  setkey(index, grid_id, year, interval_code)
  index[]
}

#' Compute PRF rainfall index values from monthly precipitation
#'
#' Sums monthly precipitation into the eleven PRF intervals and divides by the
#' interval normal: the average interval precipitation from `normal_start`
#' through `crop_year - 2`, as RMA uses to rate `crop_year`. The same normal
#' is applied to every year. Intervals missing either month are dropped. Index
#' values are rounded half up to three decimals, as RMA publishes them.
#'
#' @param precip A `data.table` with columns `grid_id`, `year`, `month`, and
#'   `precip`.
#' @param crop_year Crop year whose normal is applied to every year.
#' @param normal_start First year of the normal period.
#'
#' @return A `data.table` with columns `grid_id`, `year`, `interval_code`,
#'   `precip` (interval total), `normal`, and `index_value`.
#' @export
compute_prf_index <- function(precip, crop_year, normal_start = 1951) {
  stopifnot("`crop_year - 2` must not precede `normal_start`." =
              crop_year - 2 >= normal_start)

  # The two months in each interval: 625 = Jan + Feb, ..., 635 = Nov + Dec.
  # Intervals overlap, so most months appear twice.
  interval_months <- rbind(prf_intervals[, .(interval_code, month = month1)],
                           prf_intervals[, .(interval_code, month = month2)])

  # Interval totals. Keep only intervals with both months present, e.g. drop
  # the current year's intervals that are still in progress.
  index <- merge(precip, interval_months, by = "month", allow.cartesian = TRUE)[
    , .(precip = sum(precip), months = .N), by = .(grid_id, year, interval_code)]

  index <- index[months == 2L, .(grid_id, year, interval_code, precip)]

  normal_end <- crop_year - 2
  normal_years <- normal_end - normal_start + 1L

  normals <- index[year >= normal_start & year <= normal_end,
                   .(normal = mean(precip), years = .N),
                   by = .(grid_id, interval_code)]

  if (any(normals$years != normal_years)) {
    stop("Precipitation does not cover every year of the normal period ",
         normal_start, "-", normal_end, ".", call. = FALSE)
  }

  index[normals, on = c("grid_id", "interval_code"), normal := i.normal]

  index[, index_value := round_prf_index(precip / normal)]

  setkey(index, grid_id, year, interval_code)
  
  index[]
}

#' Get PRF rainfall index values
#'
#' Index values by grid, year, and interval from one or more sources. With
#' several sources the results are stacked, so the sources can be compared on
#' `grid_id`, `year`, and `interval_code`.
#'
#' @param source One or both of `"rma"` ([get_prf_index_rma()], RMA's
#'   published history; the default) and `"ncei"` ([get_prf_index_ncei()],
#'   computed from NCEI precipitation).
#' @param crop_year Crop year whose normal the index values are measured
#'   against. Defaults to each source's latest; see the source functions.
#' @param year Optional index year(s) to keep.
#' @param grid_id Optional RMA grid ID(s) to keep.
#' @param interval_code Optional interval code(s) to keep, from 625 (Jan-Feb)
#'   through 635 (Nov-Dec); see [prf_intervals].
#' @param force If `TRUE`, re-download the source files instead of using the
#'   cache.
#'
#' @return A `data.table` with columns `source`, `crop_year`, `grid_id`,
#'   `year`, `interval_code`, and `index_value`, plus `precip` and `normal`
#'   (`NA` for RMA rows) when `"ncei"` is requested.
#' @examples
#' \dontrun{
#' # RMA's last CPC-based release
#' get_prf_index("rma", crop_year = 2026, grid_id = 25330)
#'
#' # Both sources stacked for comparison on the 2027 normal
#' get_prf_index(c("rma", "ncei"), crop_year = 2027, grid_id = 25330, year = 2025)
#' }
#' @export
get_prf_index <- function(source = "rma", crop_year = NULL, year = NULL,
                          grid_id = NULL, interval_code = NULL, force = FALSE) {
  source <- match.arg(source, c("rma", "ncei"), several.ok = TRUE)
  getters <- list(rma = get_prf_index_rma, ncei = get_prf_index_ncei)

  indexes <- lapply(getters[source], function(get_index) {
    get_index(crop_year = crop_year, year = year, grid_id = grid_id,
              interval_code = interval_code, force = force)
  })

  # idcol takes the source names from the list
  rbindlist(indexes, use.names = TRUE, fill = TRUE, idcol = "source")
}
