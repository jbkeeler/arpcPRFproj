test_that("ndsu_colors are named hex codes", {
  expect_named(ndsu_colors)
  expect_true(all(grepl("^#[0-9A-F]{6}$", ndsu_colors)))
})
