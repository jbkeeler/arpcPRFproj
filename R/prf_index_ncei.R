# PRF rainfall index values computed from NCEI precipitation.
#
# Source: NCEI USDA monthly gridded precipitation (final, 1/4 degree CONUS
# grid), one YYYYMM.usda.csv per month from 189501 with columns latitude,
# longitude, precipitation (mm). Derived from nClimGrid-Monthly. RMA moves the
# Rainfall Index to NCEI data from crop year 2027, with the normal starting in
# 1951; the values computed here match RMA's 2027 release exactly.

ncei_monthly_url <- "https://www.ncei.noaa.gov/monitoring-content/data/us/usda/monthly/final/"

# Monthly files with their sizes in bytes, used to verify downloads.
ncei_listing <- function() {

  listing_html <- paste(readLines(url(ncei_monthly_url), warn = FALSE), collapse = "\n")

  rows <- regmatches(listing_html, gregexpr(
    '(?s)href="[0-9]{6}\\.usda\\.csv">.*?</tr>', listing_html, perl = TRUE))[[1]]

  files <- regmatches(rows, regexpr("[0-9]{6}\\.usda\\.csv", rows))

  sizes <- as.numeric(sub('(?s).*<td align="right">([0-9]+)</td>\\s*</tr>$', "\\1",
                          rows, perl = TRUE))

  stopifnot("Could not parse the NCEI file listing." =
              length(files) > 0 && !anyNA(sizes))

  data.table(file = files, size = sizes,
             year = as.integer(substr(files, 1, 4)),
             month = as.integer(substr(files, 5, 6)))[order(year, month)]
}

# Download one file, keeping it only once its size matches the listing.
# Retries back off 5, 10, 20, 40 seconds.
download_verified <- function(src, dest, expected_size, max_tries = 5) {
  for (attempt in seq_len(max_tries)) {
    try(utils::download.file(src, dest, mode = "wb", quiet = TRUE), silent = TRUE)
    if (isTRUE(file.size(dest) == expected_size)) return(invisible(dest))
    unlink(dest)
    if (attempt < max_tries) Sys.sleep(5 * 2^(attempt - 1))
  }
  stop("Failed to download ", basename(src), "; re-run to retry.", call. = FALSE)
}

# Download missing or resized files one at a time with a pause between
# requests; NCEI drops connections when hit with many concurrent requests.
ncei_download <- function(listing, raw_dir, pause = 1) {
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(raw_dir, listing$file)
  missing <- which(!file.exists(dest) | file.size(dest) != listing$size)
  if (length(missing)) {
    message(sprintf("Downloading %d NCEI monthly files...", length(missing)))
  }

  for (i in missing) {
    download_verified(paste0(ncei_monthly_url, listing$file[i]), dest[i],
                      listing$size[i])
    Sys.sleep(pause)
  }
  dest
}

# RMA grid id (GRIDCODE in the official RMA RI grid shapefile). Cells are 0.25
# degrees square and numbered west to east, south to north, 300 per row,
# starting from the cell centred on 20.125N, 129.875W.
rma_grid_id <- function(latitude, longitude) {

  grid_row <- (latitude - 20.125) / 0.25

  grid_col <- (longitude + 129.875) / 0.25

  stopifnot(
    "NCEI cells must sit on RMA grid cell centres." =
      all(grid_row == round(grid_row) & grid_col == round(grid_col)),
    "NCEI cells fall outside the RMA grid." =
      all(grid_row >= 0 & grid_row < 120 & grid_col >= 0 & grid_col < 300)
  )
  as.character(as.integer(grid_row * 300 + grid_col + 1))
}

# Monthly precipitation by RMA grid, rebuilt only when the set of files changes.
ncei_monthly_precip <- function(listing, force = FALSE) {

  cache_dir <- tools::R_user_dir("arpcPRFproj", which = "cache")

  cache_file <- file.path(cache_dir, "ncei_monthly_precip.rds")

  signature <- paste(listing$file, listing$size, collapse = ";")

  if (!force && file.exists(cache_file)) {
    precip <- readRDS(cache_file)
    if (identical(attr(precip, "signature"), signature)) return(setDT(precip))
  }

  dest <- ncei_download(listing, file.path(cache_dir, "ncei_monthly"))

  precip <- rbindlist(lapply(seq_along(dest), function(i) {
    fread(dest[i])[, .(grid_id = rma_grid_id(latitude, longitude),
                       year = listing$year[i], month = listing$month[i],
                       precip = precipitation)]
  }))

  setkey(precip, grid_id, year, month)

  setattr(precip, "signature", signature)
  saveRDS(precip, cache_file)
  precip
}

#' Get PRF rainfall index values computed from NCEI precipitation
#'
#' Downloads NCEI's final monthly gridded precipitation for USDA (1/4 degree
#' CONUS grid, from nClimGrid-Monthly), maps cells to RMA grid IDs, and
#' computes PRF index values with [compute_prf_index()]. Unlike RMA's published
#' history ([get_prf_index_rma()]), this includes every interval with final
#' data through the latest month NCEI has published. With `crop_year = 2027`
#' it reproduces every value in RMA's 2027 release (the first rated on NCEI
#' data) for the grids NCEI covers; Hawaii and Puerto Rico grids are not
#' covered.
#'
#' The first call downloads one file per month from `normal_start` onward
#' (about 20 minutes at the one-second pause NCEI tolerates); later calls only
#' fetch new or revised months. Files and the combined precipitation are cached
#' in [tools::R_user_dir()]`("arpcPRFproj", "cache")`.
#'
#' @inheritParams get_prf_index
#' @param crop_year Crop year whose normal is applied to every year. Defaults
#'   to the latest crop year whose normal period is fully observed (the last
#'   complete year of NCEI data plus two).
#' @param normal_start First year of the normal period. RMA uses 1951 for NCEI.
#' @param force If `TRUE`, rebuild the cached precipitation table.
#'
#' @return A `data.table` with columns `crop_year`, `grid_id`, `year`,
#'   `interval_code`, `index_value`, `precip` (interval total, mm), and
#'   `normal` (mm).
#' @seealso [get_prf_index()] to read either source.
#' @examples
#' \dontrun{
#' get_prf_index_ncei(grid_id = 25330, year = 2020:2026)
#' }
#' @export
get_prf_index_ncei <- function(crop_year = NULL, year = NULL, grid_id = NULL,
                               interval_code = NULL, normal_start = 1951,
                               force = FALSE) {

  check_crop_year(crop_year)

  first_year <- min(c(year, normal_start))

  listing <- ncei_listing()[year >= first_year]

  last_complete_year <- listing[month == 12L, max(year)]

  if (is.null(crop_year)) crop_year <- last_complete_year + 2L
  if (crop_year - 2 > last_complete_year) {
    stop("NCEI final data are complete only through ", last_complete_year,
         ", so the latest computable `crop_year` is ", last_complete_year + 2,
         ".", call. = FALSE)
  }

  # Normals are per grid, so grids can be dropped before computing; years
  # cannot.

  precip <- ncei_monthly_precip(listing, force = force)

  grids <- grid_id

  if (!is.null(grids)) precip <- precip[grid_id %in% as.character(grids)]

  index <- compute_prf_index(precip, crop_year, normal_start)

  index <- filter_prf_index(index, year, grid_id, interval_code)

  index[, crop_year := as.integer(crop_year)]
  
  setcolorder(index, c("crop_year", "grid_id", "year", "interval_code",
                       "index_value"))[]
}
