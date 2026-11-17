#' @keywords internal
"_PACKAGE"

#' @import data.table
#' @import ggplot2
NULL

# Columns referenced inside data.table expressions.
utils::globalVariables(c(
  ".", ".source", "acre_ratio", "acres", "adm_insurance_offer_id", "adm_year",
  "actual", "base_rate", "baseline_cbv", "baseline_rate", "baseline_acres", "blm_acres", "cbv",
  "cbv_ratio", "census_year", "change", "commodity_code", "commodity_year",
  "county_base_value", "county_code", "coverage_level_percent",
  "coverage_type_code", "crop_year", "eligible_acres", "expected_payment_factor",
  "grid_class", "grid_id", "grids", "i.acre_ratio", "i.base_rate", "i.ceiling",
  "i.county_base_value", "i.expected_payment_factor", "i.loss_cost", "i.normal",
  "i.practice_name", "i.speed", "i.subsidy_percent", "i.type_name", "i.weight",
  "indemnity_amount", "index_release", "index_value", "insurance_plan_code",
  "insured_acres", "interval_code", "irrigation_practice_code", "label", "latitude",
  "liability", "liability_amount", "line_type", "longitude", "loss_ratio",
  "month", "month1", "month2", "months", "normal", "organic_practice_code", "outcome",
  "pasture_acres", "county_payment_factor", "penetration", "practice_code",
  "practice_name", "precip", "precipitation", "predicted", "predicted_indemnity",
  "prf_county_allotment_acres", "prf_county_forage_acres", "prf_grid_county",
  "prior_acres", "prior_year", "rate", "rate_ratio", "ratio", "reinsurance_year",
  "scenario", "series", "state_abbreviation", "state_code", "state_group",
  "sub_county_code", "subsidy_amount", "subsidy_percent", "total_premium_amount",
  "type_code", "type_name", "usfs_acres", "value", "weight", "year", "years",
  "panel", "speed", "ceiling", "low", "high",
  "grid_class", "has_grids", "is_expected", "scaled_liability", "calibration_factor",
  "i.calibration_factor", "i.county_payment_factor", "size_ratio", "i.size_ratio", "i.actual", "i.predicted",
  "weather_year", "commodity_year", "deleted_date", "area_rate_id"
))
