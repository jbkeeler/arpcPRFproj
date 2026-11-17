test_that("rma_index_standardize maps every release layout to one schema", {
  layouts <- list(
    data.table::data.table(grid_id = 1L, ins_plan_id = 13L, crop_yr_id = 1948L,
                           interval_code = 625L, final_index = 0.646),
    data.table::data.table(grid_id = 1L, InsurancePlanCode = 13L, Year = 1948L,
                           ActualIndex = 0.646, IntervalCode = 625L),
    data.table::data.table(grid_id = "1", InsurancePlanCode = 13L, Year = 1948L,
                           PracticeCode = 625L, ActualIndex = 0.646)
  )
  expected <- data.table::data.table(grid_id = "1", year = 1948L,
                                     interval_code = 625L, index_value = 0.646)
  for (index in layouts) expect_equal(rma_index_standardize(index), expected)
})

test_that("get_prf_index_rma returns filtered index history", {
  skip_on_cran()
  skip_if_offline()

  index <- get_prf_index_rma(crop_year = 2026, grid_id = 25330, year = 2001:2002)
  expect_s3_class(index, "data.table")
  expect_named(index, c("crop_year", "grid_id", "year", "interval_code", "index_value"))
  expect_true(all(index$crop_year == 2026L))
  expect_setequal(unique(index$year), 2001:2002)
  expect_setequal(unique(index$interval_code), 625:635)
})

test_that("get_prf_index_rma downloads the requested release", {
  local_mocked_bindings(
    rma_index_releases = function() data.table::data.table(
      crop_year = 2025:2026, url = c("https://example.org/2025.zip", "https://example.org/2026.zip")
    ),
    rma_index_download = function(url) {
      expect_identical(url, "https://example.org/2025.zip")
      data.table::data.table(grid_id = "1", year = 2023L, interval_code = 625L, index_value = 1)
    }
  )
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())
  index <- get_prf_index_rma(crop_year = 2025)
  expect_identical(index$crop_year, 2025L)
})
