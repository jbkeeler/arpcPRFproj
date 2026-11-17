test_that("interval_from_practice_name maps two-month intervals to 625-635", {
  names <- c("Jan - Feb Index Interval", "Nov - Dec Index Interval (Irrigated)",
             "Feb - Mar Index Interval (Non-Irr) (OC)", "Jul - Sep Index Interval",
             "No Practice Specified", "JAN - FEB INDEX INTERVAL", "Aug - Sep Index Interval")
  expect_identical(interval_from_practice_name(names),
                   c(625L, 635L, 626L, NA, NA, 625L, 632L))
})

test_that("build_prf_book aggregates to the interval grain and drops empty rows", {
  sobtpu <- data.table::data.table(
    commodity_year = 2025, state_code = 38, state_abbreviation = "ND", county_code = 17, commodity_code = 88,
    insurance_plan_code = 13, type_code = 7, type_name = "Grazing",
    practice_code = c(625, 625, 0), coverage_type_code = "A",
    practice_name = c("Jan - Feb Index Interval", "Jan - Feb Index Interval",
                      "No Practice Specified"),
    coverage_level_percent = 0.9, net_reporting_level_amount = c(100, 50, 0),
    liability_amount = c(1000, 500, 0), total_premium_amount = c(100, 50, 0),
    subsidy_amount = c(51, 25.5, 0), indemnity_amount = c(0, 200, 0)
  )
  book <- build_prf_book(sobtpu)
  expect_identical(nrow(book), 1L)
  expect_identical(book$interval_code, 625L)
  expect_equal(book$insured_acres, 150)
  expect_equal(book$liability_amount, 1500)
  expect_equal(book$indemnity_amount, 200)
})
