test_that("prf_release_url builds latest and tagged asset URLs", {
  expect_equal(prf_release_url("a.csv", repo = "o/r"),
               "https://github.com/o/r/releases/latest/download/a.csv")
  expect_equal(prf_release_url("a.csv", tag = "v1.0.0.2026", repo = "o/r"),
               "https://github.com/o/r/releases/download/v1.0.0.2026/a.csv")
})

# A county outlook as script 03 writes it, served in place of the download.
local_release_asset <- function(table, env = parent.frame()) {
  asset <- withr::local_tempfile(fileext = ".csv", .local_envir = env)
  data.table::fwrite(table, asset)
  urls <- character()
  local_mocked_bindings(
    download_release_asset = function(url, dest) {
      urls <<- c(urls, url)
      file.copy(asset, dest, overwrite = TRUE)
    },
    .env = env
  )
  function() urls
}

county_outlook <- data.table::data.table(
  scenario = "main", commodity_year = c(2025, 2025, 2026), state_code = c(1, 48, 48),
  county_code = c(3, 1, 1), .source = c("observed", "projected", "projected"),
  plan_group = "prf", commodity_code = 88L, insurance_plan_code = 13L,
  unit_structure_code = "OU", insured_acres = c(100, 200, 210),
  liability_amount = c(1000, 2000, 2100), total_premium_amount = c(200, 400, 0),
  subsidy_amount = c(100, 200, 0), indemnity_amount = c(150, 300, 50)
)

test_that("get_prf_outlook reads projected county years with FIPS and loss ratio", {
  urls <- local_release_asset(county_outlook)
  outlook <- get_prf_outlook(repo = "o/r")

  expect_equal(urls(), "https://github.com/o/r/releases/latest/download/final_prf_outlook_county.csv")
  expect_equal(unique(outlook$.source), "projected")
  expect_equal(outlook$county_fips, c("48001", "48001"))
  expect_equal(match("county_fips", names(outlook)), match("county_code", names(outlook)) + 1L)
  # Older releases without loss_ratio get it computed; no premium gives NA.
  expect_equal(outlook$loss_ratio, c(0.75, NA))
  expect_type(outlook$unit_structure_code, "character")
  expect_equal(attr(outlook, "source_url"), urls())
})

test_that("get_prf_outlook keeps observed years on request", {
  local_release_asset(county_outlook)
  outlook <- get_prf_outlook(repo = "o/r", projected_only = FALSE)

  expect_equal(outlook$.source, c("observed", "projected", "projected"))
  expect_equal(outlook$county_fips, c("01003", "48001", "48001"))
})

test_that("get_prf_outlook keeps a published loss_ratio and skips FIPS above county", {
  national <- county_outlook[, lapply(.SD, sum),
                             by = .(scenario, commodity_year, .source, plan_group,
                                    commodity_code, insurance_plan_code, unit_structure_code),
                             .SDcols = prf_outcome_cols][, loss_ratio := 9]
  local_release_asset(national)
  outlook <- get_prf_outlook("national", tag = "v1.0.0.2026", repo = "o/r")

  expect_false("county_fips" %in% names(outlook))
  expect_equal(unique(outlook$loss_ratio), 9)
})

test_that("get_prf_outlook explains a failed download or a malformed table", {
  local_mocked_bindings(download_release_asset = function(url, dest) FALSE)
  expect_error(get_prf_outlook(tag = "nope", repo = "o/r"), "release `nope` exists in o/r")

  local_release_asset(county_outlook[, !"indemnity_amount"])
  expect_error(get_prf_outlook(repo = "o/r"), "lacks indemnity_amount")
})
