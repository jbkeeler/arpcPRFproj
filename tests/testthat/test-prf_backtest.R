book <- data.table::data.table(
  commodity_year = c(2002, 2003), state_code = 1, state_abbreviation = "AL", county_code = 1, commodity_code = 88L,
  insurance_plan_code = 13L, type_code = 7, interval_code = 625L,
  coverage_level_percent = 0.9, insured_acres = 100, liability_amount = 1000,
  total_premium_amount = 200, subsidy_amount = 100, indemnity_amount = c(400, 0)
)
crosswalk <- data.table::data.table(state_code = 1, county_code = 1, grid_id = "a", weight = 1)

test_that("rebase_prf_index measures each year against its own normal", {
  index <- data.table::data.table(grid_id = "a", year = 2000:2003, interval_code = 625L,
                                  index_value = c(1, 3, 1, 4))
  rebased <- rebase_prf_index(index, 2002:2003, normal_start = 2000)
  expect_equal(rebased$index_value, c(1 / 1, 4 / 2))
})

test_that("backtest_prf_book pays each year on its own index", {
  # Normal through 2000 is 1 for 2002 and (1 + 3) / 2 = 2 for 2003.
  index <- data.table::data.table(grid_id = "a", year = 2000:2003, interval_code = 625L,
                                  index_value = c(1, 3, 0.45, 4))
  backtest <- backtest_prf_book(book, index = index, crosswalk = crosswalk)
  expect_equal(backtest$commodity_year, c(2002, 2003))
  expect_equal(backtest$county_payment_factor, c(0.5, 0))
  expect_equal(backtest$predicted_indemnity, c(500, 0))
})

test_that("plots build for every figure type", {
  backtest <- data.table::copy(book)[, `:=`(county_payment_factor = c(0.5, 0), predicted_indemnity = c(500, 0))]
  for (type in c("year", "county", "grids", "state")) {
    expect_s3_class(ggplot2::ggplot_build(plot_prf_backtest(backtest, type, crosswalk = crosswalk)),
                    "ggplot_built")
  }
  outlook <- data.table::copy(book)[, .source := c("observed", "projected")]
  expect_s3_class(ggplot2::ggplot_build(plot_prf_outlook(outlook)), "ggplot_built")
})
