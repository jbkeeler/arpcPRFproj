test_that("year is validated", {
  expect_error(get_prf_subsidy_rates("2026"), "year")
  expect_error(get_prf_county_base_values(2026.5), "year")
})

test_that("get_prf_subsidy_rates returns the plan 13 schedule", {
  skip_on_cran()
  skip_if_offline()

  subsidy <- get_prf_subsidy_rates(2026)
  expect_s3_class(subsidy, "data.table")
  expect_true(all(subsidy$subsidy_percent > 0 & subsidy$subsidy_percent <= 1))
  expect_false(anyDuplicated(subsidy, by = c("coverage_level_percent",
                                             "coverage_type_code")) > 0)
})
