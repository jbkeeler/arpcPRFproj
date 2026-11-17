# Build prf_county_forage_acres: acres PRF could insure in each county, from
# the NASS Census of Agriculture.
#
#   pasture_acres    AG LAND, PASTURELAND - ACRES: all pastureland, including
#                    cropland and woodland used for pasture (grazing policies)
#   rangeland_acres  AG LAND, PASTURELAND, (EXCL CROPLAND & WOODLAND) - ACRES:
#                    permanent pasture and rangeland only
#   hay_acres        HAY & HAYLAGE - ACRES HARVESTED (haying policies)
#
# The Census counts land in farms only, so public land grazed under permit
# (BLM, Forest Service) is excluded, as it is from PRF. Values NASS withholds
# to avoid disclosing individual operations, "(D)", are NA.
#
# Needs a NASS Quick Stats key in NASSQS_TOKEN.
# Run from the package root: Rscript data-raw/prf_county_forage_acres.R

library(data.table)
library(rnassqs)

nassqs_auth(key = Sys.getenv("NASSQS_TOKEN"))

census_years <- c(2007, 2012, 2017, 2022)
items <- c(
  pasture_acres = "AG LAND, PASTURELAND - ACRES",
  rangeland_acres = "AG LAND, PASTURELAND, (EXCL CROPLAND & WOODLAND) - ACRES",
  hay_acres = "HAY & HAYLAGE - ACRES HARVESTED"
)

get_census_county <- function(short_desc, year) {
  dt <- as.data.table(nassqs(list(
    source_desc = "CENSUS", agg_level_desc = "COUNTY", domain_desc = "TOTAL",
    short_desc = short_desc, year = year
  ), progress_bar = FALSE))
  dt[, .(census_year = as.integer(year),
         state_code = as.numeric(state_fips_code),
         county_code = as.numeric(county_code),
         value = suppressWarnings(as.numeric(gsub(",", "", Value))))]
}

acres <- rbindlist(lapply(names(items), function(item) {
  rbindlist(lapply(census_years, function(year) {
    get_census_county(items[[item]], year)[, item := item]
  }))
}))

prf_county_forage_acres <- dcast(acres, census_year + state_code + county_code ~ item,
                                 value.var = "value")
setcolorder(prf_county_forage_acres, c("census_year", "state_code", "county_code", names(items)))
setkey(prf_county_forage_acres, census_year, state_code, county_code)

stopifnot(!anyDuplicated(prf_county_forage_acres, by = key(prf_county_forage_acres)))

usethis::use_data(prf_county_forage_acres, overwrite = TRUE)
