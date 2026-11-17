crosswalk <- data.table::data.table(state_code = 1, county_code = 1:3,
                                    grid_id = c("a", "b", "c"), weight = 1)

backtest <- data.table::data.table(
  state_code = 1, county_code = rep(1:2, each = 4), commodity_year = rep(2021:2024, 2),
  liability_amount = 1000, predicted_indemnity = 100,
  indemnity_amount = c(rep(120, 4), rep(100, 4))
)

test_that("calibration shrinks each county's ratio toward its size class", {
  calibration <- fit_prf_calibration(backtest, crosswalk, k = 400)
  # Size class (1-5 grids): actual 880 / predicted 800 = 1.1.
  # County 1: (480 + 400 x 1.1) / (400 + 400) = 1.15; county 2: 1.05.
  expect_equal(calibration[order(county_code), calibration_factor], c(1.15, 1.05, 1.1))
  expect_identical(attr(calibration, "k"), 400)
})

test_that("calibration picks k by cross-validation", {
  calibration <- fit_prf_calibration(backtest, crosswalk, k_candidates = c(1, 1e6))
  # County ratios are identical in even and odd years, so the least shrinkage wins.
  expect_identical(attr(calibration, "k"), 1)
})
