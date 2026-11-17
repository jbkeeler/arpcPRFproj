test_that("prf_intervals covers 625-635 as consecutive month pairs", {
  expect_identical(prf_intervals$interval_code, 625:635)
  expect_identical(prf_intervals$month2 - prf_intervals$month1, rep(1L, 11))
  expect_identical(prf_intervals$interval_name[1], "Jan-Feb")
})

test_that("get_prf_index rejects unknown sources and crop years", {
  expect_error(get_prf_index("prism"), "should be one of")
  expect_error(get_prf_index_rma(crop_year = c(2026, 2027)), "crop_year")
})

test_that("get_prf_index tags rows with their source", {
  skip_on_cran()
  skip_if_offline()

  index <- get_prf_index(crop_year = 2026, grid_id = 25330, year = 2020)
  expect_identical(unique(index$source), "rma")
  expect_identical(names(index)[1:2], c("source", "crop_year"))
})
