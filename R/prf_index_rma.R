# PRF rainfall index values as published by RMA.
#
# RMA publishes one release per crop year under VI_RI_Data/, each holding the
# full index history used to rate that crop year. Releases through 2026 are
# built on NOAA Climate Prediction Center data, from 2027 on NCEI data.

rma_index_url <- "https://pubfs-rma.fpac.usda.gov/pub/Miscellaneous_Files/VI_RI_Data/"

# Release zips by crop year, skipping the Annual Forage ("api_",
# "AnnualForage_") and Vegetation Index files. Releases 2014-2015 exist only
# in Annual Forage form and are not listed.
rma_index_releases <- function() {

  listing <- readLines(paste0(rma_index_url, "index.html"), warn = FALSE)

  # Links are quoted: href="./Rainfall_Index_HistoricData2025CY.zip"
  links <- basename(unlist(strsplit(listing, '"')))
  files <- grep("^(prf_)?rainfall_index_historicdata\\d{4}cy\\.zip$", links,
                ignore.case = TRUE, value = TRUE)

  data.table(
    crop_year = as.integer(gsub("\\D", "", files)),
    url = paste0(rma_index_url, files)
  )[order(crop_year)]
}

# Column names have changed across releases; map them to one schema.
rma_index_standardize <- function(index) {

  setnames(index, tolower(names(index)))

  pick <- function(candidates) intersect(candidates, names(index))[1]

  index[, .(
    grid_id = as.character(get(pick("grid_id"))),
    year = as.integer(get(pick(c("year", "crop_yr_id")))),
    interval_code = as.integer(get(pick(c("practicecode", "intervalcode",
                                          "interval_code")))),
    index_value = as.numeric(get(pick(c("actualindex", "final_index"))))
  )]

}

rma_index_download <- function(url) {
  
  old <- options(timeout = max(600, getOption("timeout")))
  on.exit(options(old))

  zip_path <- tempfile(fileext = ".zip")
  exdir <- tempfile("rma_index_")
  on.exit(unlink(c(zip_path, exdir), recursive = TRUE), add = TRUE)

  utils::download.file(url, zip_path, mode = "wb", quiet = TRUE)
  txt <- grep("\\.txt$", utils::unzip(zip_path, exdir = exdir), value = TRUE)
  rma_index_standardize(fread(txt[1], sep = "|",
                              colClasses = list(character = "grid_id")))
}

#' Get PRF rainfall index values published by RMA
#'
#' Downloads RMA's historical Rainfall Index values for Pasture, Rangeland,
#' Forage by grid and index interval. The index is the ratio of interval
#' precipitation to the grid's historical normal (1 = normal). Releases through
#' crop year 2026 are built on NOAA Climate Prediction Center (CPC) data, from
#' 2027 on NCEI data.
#'
#' Each RMA release is the history used to rate one crop year, running from
#' 1948 (1951 from the 2027 release) through two years before that crop year,
#' so index values for the current and prior year are not included; see
#' [get_prf_index_ncei()] for those. Grids are added and retired between
#' releases, and early releases (e.g. 2010) use a different grid numbering, so
#' when joining to [get_prf_actuarial()] use the release matching its
#' `commodity_year`. Parsed releases are cached in
#' [tools::R_user_dir()]`("arpcPRFproj", "cache")`.
#'
#' @inheritParams get_prf_index
#' @param crop_year Crop year of the RMA release to read. Defaults to the
#'   latest available.
#'
#' @return A `data.table` with columns `crop_year`, `grid_id`, `year`,
#'   `interval_code`, and `index_value`.
#' @seealso [get_prf_index()] to read either source.
#' @examples
#' \dontrun{
#' get_prf_index_rma(grid_id = 25330, year = 2000:2025)
#' get_prf_index_rma(crop_year = 2026, grid_id = 25330) # last CPC release
#' }
#' @export
get_prf_index_rma <- function(crop_year = NULL, year = NULL, grid_id = NULL,
                              interval_code = NULL, force = FALSE) {

  check_crop_year(crop_year)

  releases <- rma_index_releases()

  if (is.null(crop_year)) crop_year <- max(releases$crop_year)
  
  url <- releases$url[releases$crop_year == crop_year]

  if (length(url) == 0) {
    stop("No RMA rainfall index release for crop year ", crop_year,
         ". Available: ", paste(releases$crop_year, collapse = ", "),
         call. = FALSE)
  }

  cache_file <- file.path(tools::R_user_dir("arpcPRFproj", which = "cache"),
                          paste0("rainfall_index_", crop_year, "cy.rds"))

  if (file.exists(cache_file) && !force) {
    index <- setDT(readRDS(cache_file))
  } else {
    index <- rma_index_download(url)
    dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
    saveRDS(index, cache_file)
  }

  index <- filter_prf_index(index, year, grid_id, interval_code)
  index[, crop_year := as.integer(crop_year)]
  setcolorder(index, "crop_year")[]
}
