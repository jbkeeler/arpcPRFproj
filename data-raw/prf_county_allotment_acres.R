# Build prf_county_allotment_acres: federal grazing allotment acres by county.
#
# PRF insures federal land grazed under permit, which the Census of
# Agriculture leaves out of pastureland (see prf_county_forage_acres), so
# eligible grazing acres are Census pasture plus these allotments.
#
# Sources:
#   BLM National Grazing Allotment Polygons, BLM ArcGIS REST service
#     https://gis.blm.gov/arcgis/rest/services/range/BLM_Natl_Grazing_Allotment/MapServer/12
#   BLM Surface Management Agency (generalized), BLM-managed land
#     https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_LimitedScale/MapServer/7
#   USFS Range Allotments (S_USA.Allotment), FSGeodata Clearinghouse
#     https://data.fs.usda.gov/geodata/edw/edw_resources/shp/S_USA.Allotment.zip
#   Census 2020 cartographic boundary counties (1:500k)
#
# Allotment boundaries take in private and state inholdings that the Census
# may already count as pasture, so only federal land inside them is counted:
# BLM allotments are overlaid on BLM-managed land on a 250 m grid (150.7M
# acres of 232.6M inside allotments), and USFS allotments are scaled to the
# National Forest acres each reports. Only USFS allotments with status ACTIVE
# are kept (closed and vacant allotments are not grazed); the BLM layer has
# no status.
#
# Areas are computed in CONUS Albers equal-area (EPSG:5070).
# Run from the package root: Rscript data-raw/prf_county_allotment_acres.R

library(data.table)
library(sf)
library(terra)

sf_use_s2(FALSE)
acres_per_m2 <- 1 / 4046.8564224

# Page through a BLM map service layer, 1,000 polygons per request,
# simplified to about 50 m.
read_blm_layer <- function(layer_url) {
  query <- paste0(layer_url, "/query?where=1%3D1")
  count <- jsonlite::fromJSON(paste0(query, "&returnCountOnly=true&f=json"))$count
  layer <- do.call(rbind, lapply(seq(0, count - 1, by = 1000), function(offset) {
    st_read(paste0(query, "&outFields=OBJECTID&outSR=4326&geometryPrecision=5",
                   "&maxAllowableOffset=0.0005&orderByFields=OBJECTID",
                   "&resultRecordCount=1000&resultOffset=", offset, "&f=geojson"), quiet = TRUE)
  }))
  stopifnot(nrow(layer) == count)
  layer
}

blm_allotments <- read_blm_layer(
  "https://gis.blm.gov/arcgis/rest/services/range/BLM_Natl_Grazing_Allotment/MapServer/12"
)
blm_land <- read_blm_layer(
  "https://gis.blm.gov/arcgis/rest/services/lands/BLM_Natl_SMA_LimitedScale/MapServer/7"
)

read_zipped_shapefile <- function(url) {
  zip_path <- tempfile(fileext = ".zip")
  exdir <- tempfile("shp_")
  download.file(url, zip_path, mode = "wb", quiet = TRUE)
  st_read(grep("\\.shp$", unzip(zip_path, exdir = exdir), value = TRUE), quiet = TRUE)
}

usfs <- read_zipped_shapefile(
  "https://data.fs.usda.gov/geodata/edw/edw_resources/shp/S_USA.Allotment.zip"
)
usfs <- usfs[usfs$ALLOTMEN_2 %in% "ACTIVE", ]
usfs$federal_share <- with(usfs, pmin(1, fifelse(TOTAL_ACRE > 0, NFS_ACRES / TOTAL_ACRE, 1)))

counties <- read_zipped_shapefile(
  "https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_county_500k.zip"
)
conus_states <- setdiff(sprintf("%02d", 1:56), c("02", "15", "03", "07", "14", "43", "52"))
counties <- st_transform(counties[counties$STATEFP %in% conus_states, c("STATEFP", "COUNTYFP")], 5070)

# BLM: acres of BLM land inside allotments by county, on a 250 m grid.
counties$fips <- as.numeric(counties$STATEFP) * 1000 + as.numeric(counties$COUNTYFP)
grid <- rast(ext(vect(counties)), resolution = 250, crs = "EPSG:5070")
to_grid <- function(polygons, ...) rasterize(vect(st_transform(polygons, 5070)), grid, ...)
in_allotment <- to_grid(blm_allotments, field = 1, background = 0)
blm_owned <- to_grid(blm_land, field = 1, background = 0)
blm <- as.data.table(zonal(in_allotment * blm_owned, to_grid(counties, field = "fips"), fun = "sum"))
setnames(blm, c("fips", "cells"))
blm <- blm[cells > 0, .(state_code = fips %/% 1000, county_code = fips %% 1000,
                        blm_acres = cells * 250^2 * acres_per_m2)]

# USFS: allotment area by county, scaled to each allotment's National Forest share.
usfs <- st_make_valid(st_transform(usfs[, "federal_share"], 5070))
pieces <- st_intersection(counties, usfs)
usfs <- data.table(state_code = as.numeric(pieces$STATEFP),
                   county_code = as.numeric(pieces$COUNTYFP),
                   acres = as.numeric(st_area(pieces)) * acres_per_m2 * pieces$federal_share)[
  , .(usfs_acres = sum(acres)), by = .(state_code, county_code)]

prf_county_allotment_acres <- merge(blm, usfs, by = c("state_code", "county_code"), all = TRUE)
setnafill(prf_county_allotment_acres, fill = 0, cols = c("blm_acres", "usfs_acres"))
setkey(prf_county_allotment_acres, state_code, county_code)

stopifnot(
  !anyDuplicated(prf_county_allotment_acres, by = c("state_code", "county_code")),
  abs(sum(prf_county_allotment_acres$blm_acres) / 1e6 - 150) < 10
)

usethis::use_data(prf_county_allotment_acres, overwrite = TRUE)
