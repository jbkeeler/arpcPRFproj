test_that("rma_grid_id matches GRIDCODE in RMA's official grid shapefile", {
  # Cell centres and GRIDCODEs from official_RMA_RI_grid.shp
  # (rainfall_index_grids.zip on RMA's VI_RI_Data site); all 36,000 cells match.
  expect_identical(rma_grid_id(20.125, -129.875), "1")
  expect_identical(rma_grid_id(20.125, -129.625), "2")
  expect_identical(rma_grid_id(20.375, -129.875), "301")
  expect_identical(rma_grid_id(41.125, -97.625), "25330")
  expect_identical(rma_grid_id(49.875, -55.125), "36000")
  expect_error(rma_grid_id(20.2, -129.875), "centres")
  expect_error(rma_grid_id(50.125, -129.875), "outside")
})

test_that("compute_prf_index sums intervals and divides by the fixed normal", {
  # One grid, two years of 12 months; year 1 has 1 mm/month, year 2 has 3.
  precip <- data.table::CJ(grid_id = "1", year = 2001:2002, month = 1:12)
  precip[, precip := ifelse(year == 2001, 1, 3)]

  # Crop year 2004 normal covers 2001-2002: (2 + 6) / 2 = 4 mm per interval.
  index <- compute_prf_index(precip, crop_year = 2004, normal_start = 2001)
  expect_identical(nrow(index), 22L)
  expect_true(all(index$normal == 4))
  expect_equal(index[year == 2001, unique(index_value)], 0.5)
  expect_equal(index[year == 2002, unique(index_value)], 1.5)
})

test_that("compute_prf_index drops incomplete intervals and short normals", {
  precip <- data.table::CJ(grid_id = "1", year = 2001:2002, month = 1:12)
  precip[, precip := 1]
  partial <- precip[!(year == 2002 & month > 7)]

  index <- compute_prf_index(partial, crop_year = 2003, normal_start = 2001)
  expect_identical(index[year == 2002, max(interval_code)], 630L)

  expect_error(compute_prf_index(precip, crop_year = 2005, normal_start = 2001),
               "normal period")
  expect_error(compute_prf_index(precip, crop_year = 2002, normal_start = 2001),
               "normal_start")
})
