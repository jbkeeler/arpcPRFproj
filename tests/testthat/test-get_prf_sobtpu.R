test_that("get_prf_sobtpu validates arguments before downloading", {
  expect_error(get_prf_sobtpu(window = 0), "window")
  expect_error(get_prf_sobtpu(window = 2.5), "window")
  expect_error(get_prf_sobtpu(baseline = c(2024, 2025)), "baseline")
})

test_that("get_prf_sobtpu returns a data.table for the requested years", {
  skip_on_cran()
  skip_if_offline()

  sobtpu <- get_prf_sobtpu(baseline = 2025, window = 2)
  expect_s3_class(sobtpu, "data.table")
  expect_setequal(unique(sobtpu$commodity_year), 2024:2025)
  expect_true(all(sobtpu$commodity_code == 88))
})
