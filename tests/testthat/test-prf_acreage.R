eligible <- data.table::data.table(state_code = c(1, 1, 2), county_code = c(1, 2, 1),
                                   eligible_acres = 1000)

test_that("fit_prf_acreage recovers the speed and state ceilings", {
  # Simulate counties closing 20% of the gap to a 0.8 (state 1) or 0.5
  # (state 2) ceiling each year.
  simulate <- function(state, county, ceiling, start) {
    acres <- start
    for (i in 2:5) acres[i] <- acres[i - 1] + 0.2 * (ceiling * 1000 - acres[i - 1])
    data.table::data.table(commodity_year = 2021:2025, state_code = state, county_code = county,
                           type_code = 7, insured_acres = acres)
  }
  book <- rbind(simulate(1, 1, 0.8, 100), simulate(1, 2, 0.8, 300), simulate(2, 1, 0.5, 50))
  local_mocked_bindings(prf_eligible_acres = function() eligible)

  fit <- fit_prf_acreage(book, baseline_year = 2025, fit_years = 4, min_counties = 1)
  expect_equal(fit$speed, c(0.2, 0.2))
  expect_equal(fit[order(state_code), ceiling], c(0.8, 0.5))
})

test_that("project_prf_acres closes the gap to the ceiling and stops there", {
  local_mocked_bindings(prf_eligible_acres = function() eligible)
  book <- data.table::data.table(commodity_year = 2025, state_code = c(1, 2), county_code = 1,
                                 type_code = 7, insured_acres = c(400, 900))
  fit <- data.table::data.table(state_code = 0, ceiling = 0.8, speed = 0.5)
  acres <- project_prf_acres(book, 2025, 2026:2027, fit)
  # State 1: 400 -> 600 -> 700; state 2 is past its ceiling and stays put.
  expect_equal(acres[state_code == 1, acre_ratio], c(1.5, 1.75))
  expect_equal(acres[state_code == 2, acre_ratio], c(1, 1))
})

test_that("project_prf_acres skips counties without baseline acres", {
  local_mocked_bindings(prf_eligible_acres = function() eligible)
  book <- data.table::data.table(commodity_year = 2025, state_code = 1, county_code = 1:2,
                                 type_code = 7, insured_acres = c(400, 0))
  fit <- data.table::data.table(state_code = 0, ceiling = 0.8, speed = 0.5)
  acres <- project_prf_acres(book, 2025, 2026, fit)
  expect_equal(acres$county_code, 1)
  expect_true(all(is.finite(acres$acre_ratio)))
})

test_that("haying follows its state's grazing growth", {
  local_mocked_bindings(prf_eligible_acres = function() eligible)
  # State 1 grazing 400 -> 600 (ratio 1.5) applies to both its haying counties.
  book <- data.table::data.table(commodity_year = 2025, state_code = c(1, 1, 1, 2),
                                 county_code = c(1, 1, 2, 1), type_code = c(7, 30, 30, 30),
                                 insured_acres = c(400, 10, 20, 30))
  fit <- data.table::data.table(state_code = 0, ceiling = 0.8, speed = 0.5)
  acres <- project_prf_acres(book, 2025, 2026, fit)
  expect_equal(acres[type_code == 30 & state_code == 1, acre_ratio], c(1.5, 1.5))
  # State 2 has no modeled grazing, so its haying is not listed (stays flat).
  expect_false(any(acres$state_code == 2))
})
