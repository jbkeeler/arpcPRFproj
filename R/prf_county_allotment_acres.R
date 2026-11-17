#' Federal grazing allotment acres by county
#'
#' Federal land inside BLM and Forest Service grazing allotments, by county.
#' PRF insures land grazed under federal permit, which the Census of
#' Agriculture leaves out of pastureland, so eligible grazing acres are
#' [prf_county_forage_acres] pasture plus these. Continental US only. Built by
#' `data-raw/prf_county_allotment_acres.R`.
#'
#' @format A `data.table` with one row per county with allotments:
#' \describe{
#'   \item{state_code, county_code}{FIPS codes.}
#'   \item{blm_acres}{BLM-managed land inside BLM grazing allotments, from
#'     the allotment polygons overlaid on BLM's surface management layer on a
#'     250 m grid.}
#'   \item{usfs_acres}{Active Forest Service allotments, scaled to the
#'     National Forest acres each allotment reports.}
#' }
#' @source BLM National Grazing Allotment Polygons and Surface Management
#'   Agency layers (<https://gis.blm.gov/arcgis/rest/services>); USFS Range
#'   Allotments (<https://data.fs.usda.gov/geodata/edw/datasets.php>).
"prf_county_allotment_acres"
