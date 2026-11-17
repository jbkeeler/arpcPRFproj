# PRF ADM tables read directly from RMA, for years rfcip does not carry yet.
# As of 2026-11-16 (rfcip 1.0.2, data refreshed with force = TRUE), rfcip's
# 2027 tables have no PRF records. (Its 2025 PRF base values equal 2026's,
# but so do RMA's own: PRF county base values are unchanged 2025-2027.)
# Remove a year from rma_adm_years once rfcip carries it.
rma_adm_years <- 2027

rma_adm_url <- "https://pubfs-rma.fpac.usda.gov/pub/References/actuarial_data_master/"

# ADM tables the package reads, filtered to PRF records.
prf_adm_datasets <- c("A00070_SubsidyPercent", "A00510_Practice", "A00540_Type",
                      "A00810_Price", "A01130_AreaCoverageLevel", "A01135_AreaRate")

# One PRF ADM table for one year, from the cache or RMA's year-to-date file.
read_adm_rma <- function(year, dataset) {
  cache_dir <- file.path(tools::R_user_dir("arpcPRFproj", which = "cache"), "adm")
  cache_file <- file.path(cache_dir, paste0(year, "_", dataset, ".rds"))
  if (!file.exists(cache_file)) download_prf_adm_rma(year, cache_dir)
  setDT(readRDS(cache_file))
}

rma_adm_fetch <- function(year, zip_path) {
  utils::download.file(paste0(rma_adm_url, year, "/", year, "_ADM_YTD.zip"),
                       zip_path, mode = "wb", quiet = TRUE)
}

# Download RMA's year-to-date ADM (1-3 GB), keep the PRF records of each table
# the package reads, and cache them (a few MB). Columns are renamed to rfcip's
# snake_case names, e.g. "ADM Insurance Offer ID" -> adm_insurance_offer_id.
download_prf_adm_rma <- function(year, cache_dir) {
  old <- options(timeout = max(3600, getOption("timeout")))
  on.exit(options(old))
  zip_path <- tempfile(fileext = ".zip")
  exdir <- tempfile("adm_")
  on.exit(unlink(c(zip_path, exdir), recursive = TRUE), add = TRUE)

  message("Downloading RMA's ", year, " ADM year-to-date file (1-3 GB); ",
          "PRF tables are cached afterwards.")
  rma_adm_fetch(year, zip_path)
  members <- utils::unzip(zip_path, list = TRUE)$Name
  members <- members[grepl(paste(prf_adm_datasets, collapse = "|"), members)]
  files <- utils::unzip(zip_path, files = members, exdir = exdir)

  read_table <- function(dataset) {
    table <- fread(grep(dataset, files, value = TRUE), sep = "|")
    setnames(table, gsub("[^a-z0-9]+", "_", tolower(names(table))))
    table
  }
  price <- read_table("A00810_Price")[commodity_code == prf_crop_code &
                                        insurance_plan_code == prf_plan_code]
  coverage <- read_table("A01130_AreaCoverageLevel")[
    adm_insurance_offer_id %in% price$adm_insurance_offer_id]
  tables <- list(
    A00810_Price = price,
    A01130_AreaCoverageLevel = coverage,
    A01135_AreaRate = read_table("A01135_AreaRate")[area_rate_id %in% coverage$area_rate_id],
    A00070_SubsidyPercent = read_table("A00070_SubsidyPercent")[insurance_plan_code == prf_plan_code],
    A00540_Type = read_table("A00540_Type")[commodity_code == prf_crop_code],
    A00510_Practice = read_table("A00510_Practice")[commodity_code == prf_crop_code]
  )

  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  for (dataset in names(tables)) {
    saveRDS(tables[[dataset]], file.path(cache_dir, paste0(year, "_", dataset, ".rds")))
  }
}
