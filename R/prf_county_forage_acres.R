#' County pasture and hay acres from the Census of Agriculture
#'
#' Acres in each county that PRF could insure, from the NASS Census of
#' Agriculture (2007, 2012, 2017, 2022). The Census counts land in farms only
#' and assigns an operation's land to its principal county, so it excludes
#' public land grazed under permit and can differ from where insured land
#' lies. Built by `data-raw/prf_county_forage_acres.R`.
#'
#' @format A `data.table` with one row per census year and county:
#' \describe{
#'   \item{census_year}{Census of Agriculture year.}
#'   \item{state_code, county_code}{FIPS codes.}
#'   \item{pasture_acres}{All pastureland, including cropland and woodland
#'     used for pasture (AG LAND, PASTURELAND - ACRES).}
#'   \item{rangeland_acres}{Permanent pasture and rangeland only (AG LAND,
#'     PASTURELAND, (EXCL CROPLAND & WOODLAND) - ACRES).}
#'   \item{hay_acres}{Hay and haylage acres harvested.}
#' }
#' Values NASS withholds to avoid disclosing individual operations are `NA`.
#' @source USDA NASS Quick Stats, <https://quickstats.nass.usda.gov/>.
"prf_county_forage_acres"
