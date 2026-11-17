# Build prf_grid_county: the share of each county's area that falls in each
# PRF grid cell.
#
# Sources:
#   RMA Rainfall Index grid (official_RMA_RI_grid.shp, NAD83), from
#     https://pubfs-rma.fpac.usda.gov/pub/Miscellaneous_Files/VI_RI_Data/rainfall_index_grids.zip
#   Census 2020 cartographic boundary counties (1:500k, clipped to shoreline),
#     from https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_county_500k.zip
#   Census 2023 cartographic boundaries for Connecticut's planning regions,
#     from https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_500k.zip
#
# Connecticut replaced its counties with planning regions in 2022. RMA's ADM
# uses the region codes (110-190) from 2026 while SOB history uses the old
# county codes (1-15), so both are included; the code ranges do not overlap.
#
# Areas are computed in CONUS Albers equal-area (EPSG:5070). The grid covers
# the continental US only, so Alaska, Hawaii, and the territories are absent.
# Run from the package root: Rscript data-raw/prf_grid_county.R

library(data.table)
library(sf)

read_zipped_shapefile <- function(url) {
  zip_path <- tempfile(fileext = ".zip")
  exdir <- tempfile("shp_")
  download.file(url, zip_path, mode = "wb", quiet = TRUE)
  shp <- grep("\\.shp$", unzip(zip_path, exdir = exdir), value = TRUE)
  st_read(shp, quiet = TRUE)
}

grids <- read_zipped_shapefile(
  "https://pubfs-rma.fpac.usda.gov/pub/Miscellaneous_Files/VI_RI_Data/rainfall_index_grids.zip"
)
counties <- read_zipped_shapefile(
  "https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_county_500k.zip"
)
ct_regions <- read_zipped_shapefile(
  "https://www2.census.gov/geo/tiger/GENZ2023/shp/cb_2023_us_county_500k.zip"
)
ct_regions <- ct_regions[ct_regions$STATEFP == "09", ]

conus_states <- setdiff(sprintf("%02d", 1:56), c("02", "15", "03", "07", "14", "43", "52"))
counties <- rbind(
  counties[counties$STATEFP %in% conus_states, c("STATEFP", "COUNTYFP")],
  st_transform(ct_regions[, c("STATEFP", "COUNTYFP")], st_crs(counties))
)

grids <- st_transform(grids[, "GRIDCODE"], 5070)
counties <- st_transform(counties, 5070)

pieces <- st_intersection(counties, grids)
crosswalk <- data.table(
  state_code = as.numeric(pieces$STATEFP),
  county_code = as.numeric(pieces$COUNTYFP),
  grid_id = as.character(pieces$GRIDCODE),
  area_km2 = as.numeric(st_area(pieces)) / 1e6
)

# Slivers from shared boundaries carry no meaningful area.
crosswalk <- crosswalk[area_km2 > 1e-6]

# Shannon County, SD (46113) was renamed Oglala Lakota County (46102) in 2015;
# SOB uses the old code through 2016.
crosswalk <- rbind(crosswalk,
                   crosswalk[state_code == 46 & county_code == 102][, county_code := 113])
crosswalk[, weight := area_km2 / sum(area_km2), by = .(state_code, county_code)]
setkey(crosswalk, state_code, county_code, grid_id)

stopifnot(
  !anyDuplicated(crosswalk, by = c("state_code", "county_code", "grid_id")),
  crosswalk[, all(abs(sum(weight) - 1) < 1e-9), by = .(state_code, county_code)]$V1
)

prf_grid_county <- crosswalk
usethis::use_data(prf_grid_county, overwrite = TRUE)
