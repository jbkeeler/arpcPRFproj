test_that("prf_policy_year rolls over on December 1", {
  expect_identical(prf_policy_year(as.Date("2026-01-01")), 2026L)
  expect_identical(prf_policy_year(as.Date("2026-11-30")), 2026L)
  expect_identical(prf_policy_year(as.Date("2026-12-01")), 2027L)
})
