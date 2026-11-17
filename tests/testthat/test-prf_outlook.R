book <- data.table::data.table(
  commodity_year = 2025, state_code = 1, state_abbreviation = "AL", county_code = 1, commodity_code = 88L,
  insurance_plan_code = 13L, type_code = 7, type_name = "Grazing",
  practice_code = 625, practice_name = "Jan - Feb Index Interval",
  interval_code = 625L, coverage_type_code = "A", coverage_level_percent = 0.9,
  insured_acres = 100, liability_amount = 1000, total_premium_amount = 200,
  subsidy_amount = 102, indemnity_amount = 50
)

# ADM for 2025 and 2026; 2027 published without PRF records yet.
mock_drivers <- function(year, crosswalk) {
  values <- list(`2025` = c(cbv = 10, rate = 0.20, subsidy = 0.51),
                 `2026` = c(cbv = 11, rate = 0.22, subsidy = 0.55))[[as.character(year)]]
  if (is.null(values)) return(data.table::data.table())
  data.table::data.table(state_code = 1, county_code = 1, type_code = 7,
                         practice_code = 625, coverage_level_percent = 0.9,
                         county_base_value = values[["cbv"]], base_rate = values[["rate"]],
                         subsidy_percent = values[["subsidy"]])
}

# One grid paying 0.5 and 0 at 90% coverage: expected payment factor 0.25.
index <- data.table::data.table(grid_id = "a", year = 2000:2001, interval_code = 625L,
                                index_value = c(0.45, 1.2))
crosswalk <- data.table::data.table(state_code = 1, county_code = 1, grid_id = "a",
                                    weight = 1)

test_that("project_prf_book moves outcomes with ADM drivers and expected payments", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 2,
                     index = index, crosswalk = crosswalk, acreage_fit = NULL, nowcast = FALSE)
  )

  expect_identical(projection$commodity_year, c(2025L, 2026L, 2027L))
  expect_identical(projection$adm_year, c(2025L, 2026L, 2026L))
  expect_equal(projection$insured_acres, c(100, 100, 100))
  expect_equal(projection$liability_amount, c(1000, 1100, 1100))
  expect_equal(projection$total_premium_amount, c(200, 242, 242))
  expect_equal(projection$subsidy_amount, c(102, 133.1, 133.1))
  expect_equal(projection$indemnity_amount, c(250, 275, 275))
})

test_that("counties without grids fall back to their observed loss cost", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  no_grids <- data.table::data.table(state_code = 2, county_code = 1, grid_id = "a",
                                     weight = 1)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 0,
                     index = index, crosswalk = no_grids, acreage_fit = NULL, nowcast = FALSE)
  )
  expect_equal(projection$indemnity_amount, 1000 * 50 / 1000)
})

test_that("prf_fcip_outlook stacks observed and projected rows in arpcFCIPproj layout", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 1,
                     index = index, crosswalk = crosswalk, acreage_fit = NULL, nowcast = FALSE)
  )
  outlook <- prf_fcip_outlook(book, projection)

  expect_named(outlook, c("commodity_year", "state_code", "county_code", "plan_group",
                          "commodity_code", "insurance_plan_code", "insured_acres",
                          "liability_amount", "total_premium_amount", "subsidy_amount",
                          "indemnity_amount", ".source", "unit_structure_code"))
  expect_identical(outlook$.source, c("observed", "projected", "projected"))
  expect_identical(outlook$commodity_year, c(2025, 2025, 2026))
  expect_equal(outlook[.source == "observed", indemnity_amount], 50)
  expect_false(".source" %in% names(projection))
})

test_that("each projection year uses the index release it is rated on", {
  # CPC releases (through 2026) pay 0.5 on average at 90% coverage; the NCEI
  # release (2027, the latest) pays 0.25.
  local_mocked_bindings(
    prf_adm_drivers = mock_drivers,
    rma_index_releases = function() data.table::data.table(crop_year = 2025:2027, url = ""),
    get_prf_index_rma = function(crop_year, ...) {
      values <- if (crop_year <= 2026) c(0, 1.2) else c(0.45, 1.2)
      data.table::data.table(crop_year = crop_year, grid_id = "a", year = 2000:2001,
                             interval_code = 625L, index_value = values)
    }
  )
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 3, crosswalk = crosswalk,
                     acreage_fit = NULL, nowcast = FALSE)
  )
  expect_equal(projection$indemnity_amount, c(1000 * 0.5, 1100 * 0.5, 1100 * 0.25, 1100 * 0.25))
  expect_false("index_release" %in% names(projection))
})

test_that("project_prf_book scales grazing outcomes with projected acres", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  # Eligible 1000 acres, ceiling 0.5, speed 0.5: 100 -> 300 -> 400 acres.
  local_mocked_bindings(prf_eligible_acres = function() {
    data.table::data.table(state_code = 1, county_code = 1, eligible_acres = 1000)
  })
  fit <- data.table::data.table(state_code = 0, ceiling = 0.5, speed = 0.5)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 2,
                     index = index, crosswalk = crosswalk, acreage_fit = fit, nowcast = FALSE)
  )
  expect_equal(projection$insured_acres, c(100, 300, 400))
  expect_equal(projection$liability_amount, c(1000, 3 * 1100, 4 * 1100))
  expect_equal(projection$indemnity_amount, c(250, 3 * 275, 4 * 275))
})

test_that("nowcast replaces expected payments for observed intervals", {
  local_mocked_bindings(
    prf_adm_drivers = mock_drivers,
    nowcast_payment_factors = function(years, coverage_levels, crosswalk) {
      data.table::data.table(state_code = 1, county_code = 1, commodity_year = 2026,
                             interval_code = 625L, coverage_level_percent = 0.9,
                             county_payment_factor = 0.1)
    }
  )
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 2,
                     index = index, crosswalk = crosswalk, acreage_fit = NULL)
  )
  expect_equal(projection$indemnity_amount, c(250, 1100 * 0.1, 275))
})

test_that("calibration scales indemnity and is optional", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  calibration <- data.table::data.table(state_code = 1, county_code = 1, calibration_factor = 1.2)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 1, index = index,
                     crosswalk = crosswalk, acreage_fit = NULL, nowcast = FALSE,
                     calibration = calibration)
  )
  expect_equal(projection$indemnity_amount, c(250, 275) * 1.2)
  expect_equal(projection$liability_amount, c(1000, 1100))
})

test_that("indemnity by weather year spans the index history and averages to the expectation", {
  local_mocked_bindings(prf_adm_drivers = mock_drivers)
  projection <- suppressMessages(
    project_prf_book(book, baseline_year = 2025, projection_window = 1, index = index,
                     crosswalk = crosswalk, acreage_fit = NULL, nowcast = FALSE)
  )
  by_weather <- attr(projection, "indemnity_by_weather_year")
  # Weather years 2000 (payment factor 0.5) and 2001 (0).
  expect_equal(by_weather[commodity_year == 2026, indemnity_amount], c(1100 * 0.5, 0))
  expect_equal(by_weather[, mean(indemnity_amount), by = commodity_year]$V1,
               projection$indemnity_amount)
  outlook <- prf_fcip_outlook(book, projection)
  expect_identical(attr(outlook, "indemnity_by_weather_year"), by_weather)
})
