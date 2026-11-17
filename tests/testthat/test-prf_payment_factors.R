test_that("prf_payment_factor pays the shortfall below coverage", {
  expect_equal(prf_payment_factor(c(0.45, 0.9, 1.2), 0.9), c(0.5, 0, 0))
})

test_that("county payment factors average grid payment factors, not the index", {
  crosswalk <- data.table::data.table(state_code = 1, county_code = 1,
                                      grid_id = c("a", "b"), weight = c(0.25, 0.75))
  # Grid a is dry, grid b wet: the area-weighted index (0.9) would pay nothing.
  index <- data.table::data.table(grid_id = c("a", "b"), year = 2020L,
                                  interval_code = 625L, index_value = c(0.45, 1.05))

  factors <- get_county_payment_factors(index, coverage_levels = 0.9, crosswalk = crosswalk)
  expect_equal(factors$county_payment_factor, 0.25 * 0.5)
})

test_that("grids without index values are dropped and weights rescaled", {
  crosswalk <- data.table::data.table(state_code = 1, county_code = 1,
                                      grid_id = c("a", "b"), weight = c(0.25, 0.75))
  index <- data.table::data.table(grid_id = "a", year = 2020L, interval_code = 625L,
                                  index_value = 0.45)
  factors <- get_county_payment_factors(index, coverage_levels = 0.9, crosswalk = crosswalk)
  expect_equal(factors$county_payment_factor, 0.5)
})

test_that("expected_payment_factors averages over years", {
  factors <- data.table::data.table(state_code = 1, county_code = 1, year = 2019:2020,
                                    interval_code = 625L, coverage_level_percent = 0.9,
                                    county_payment_factor = c(0, 0.4))
  expected <- expected_payment_factors(factors)
  expect_equal(expected$expected_payment_factor, 0.2)
  expect_identical(expected$years, 2L)
  expect_equal(expected_payment_factors(factors, year = 2020)$expected_payment_factor, 0.4)
})

test_that("prf_grid_county weights sum to one within each county", {
  sums <- prf_grid_county[, sum(weight), by = .(state_code, county_code)]$V1
  expect_true(all(abs(sums - 1) < 1e-9))
  expect_type(prf_grid_county$grid_id, "character")
})
