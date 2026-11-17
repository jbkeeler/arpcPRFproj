test_that("download_prf_adm_rma keeps PRF records with rfcip column names", {
  tables <- list(
    "2027_A00810_Price_YTD.txt" = c(
      "Record Type Code|ADM Insurance Offer ID|Commodity Code|Insurance Plan Code|County Base Value|Released Date",
      "A00810|1|0088|13|138.00|20260828",
      "A00810|2|0332|13|201.17|20260422"),
    "2027_A01130_AreaCoverageLevel_YTD.txt" = c(
      "ADM Insurance Offer ID|Coverage Level Percent|Area Rate ID", "1|0.90|11", "2|0.90|22"),
    "2027_A01135_AreaRate_YTD.txt" = c("Area Rate ID|Base Rate", "11|0.1280", "22|0.1103"),
    "2027_A00070_SubsidyPercent_YTD.txt" = c(
      "Insurance Plan Code|Coverage Level Percent|Subsidy Percent", "01|0.70|0.64", "13|0.90|0.51"),
    "2027_A00540_Type_YTD.txt" = c("Commodity Code|Type Code|Type Name", "0011|011|Winter", "0088|007|Grazing"),
    "2027_A00510_Practice_YTD.txt" = c("Commodity Code|Practice Code|Practice Name",
                                       "0088|625|Jan - Feb Index Interval")
  )
  local_mocked_bindings(rma_adm_fetch = function(year, zip_path) {
    dir <- withr::local_tempdir()
    for (name in names(tables)) writeLines(tables[[name]], file.path(dir, name))
    withr::with_dir(dir, utils::zip(zip_path, names(tables), flags = "-q"))
  })
  cache_dir <- withr::local_tempdir()
  suppressMessages(download_prf_adm_rma(2027, cache_dir))

  price <- readRDS(file.path(cache_dir, "2027_A00810_Price.rds"))
  expect_identical(price$adm_insurance_offer_id, 1L)
  expect_equal(price$county_base_value, 138)
  expect_equal(readRDS(file.path(cache_dir, "2027_A01135_AreaRate.rds"))$base_rate, 0.128)
  expect_equal(readRDS(file.path(cache_dir, "2027_A00070_SubsidyPercent.rds"))$subsidy_percent, 0.51)
  expect_identical(readRDS(file.path(cache_dir, "2027_A00540_Type.rds"))$type_name, "Grazing")
})
