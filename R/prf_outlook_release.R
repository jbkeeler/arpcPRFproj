# Published PRF outlooks. Each outlook is a GitHub release of this repository
# whose assets are the final_prf_outlook_<level>.csv tables written by
# data-raw/scripts/prf-outlook/03_prf_outlook_release.R.

prf_outlook_repo <- "jbkeeler/arpcPRFproj"

# Download URL of one release asset. "latest" is GitHub's most recent
# published (non-draft, non-prerelease) release.
prf_release_url <- function(asset, tag = "latest", repo = prf_outlook_repo) {
  if (identical(tag, "latest")) {
    sprintf("https://github.com/%s/releases/latest/download/%s", repo, asset)
  } else {
    sprintf("https://github.com/%s/releases/download/%s/%s", repo, tag, asset)
  }
}

# Download a release asset to `dest`; FALSE if it could not be downloaded.
download_release_asset <- function(url, dest) {
  status <- tryCatch(utils::download.file(url, dest, mode = "wb", quiet = TRUE),
                     error = function(e) 1L, warning = function(w) 1L)
  identical(as.integer(status), 0L)
}

#' Get a published PRF outlook
#'
#' Downloads the PRF outlook published as a GitHub release of this package
#' and returns projected insured acres, liability, total premium, subsidy,
#' indemnity, and loss ratio by year at the county, state, or national
#' level, from the baseline year on.
#'
#' Releases hold projected years only. A release that also holds observed
#' Summary of Business years labels them `.source = "observed"`; they are
#' dropped unless `projected_only = FALSE`. The baseline year then appears
#' under both, so filter on `.source` before summing over years.
#'
#' @param level `"county"` (the default), `"state"`, or `"national"`.
#' @param tag Release tag, e.g. `"v1.0.0.2026"`. `"latest"` (the
#'   default) is the repository's most recent published release.
#' @param repo GitHub repository holding the releases, as `"owner/name"`.
#' @param projected_only If `TRUE` (the default), keep projected years only.
#'   `FALSE` returns every row the release holds.
#'
#' @return A `data.table` with `scenario`, `commodity_year`, the level's
#'   geography (`state_code`, `county_code`, and `county_fips` for counties;
#'   `state_code` for states), `.source`, the arpcFCIPproj outlook columns
#'   (`plan_group`, `commodity_code`, `insurance_plan_code`,
#'   `unit_structure_code`), `insured_acres`, `liability_amount`,
#'   `total_premium_amount`, `subsidy_amount`, `indemnity_amount`, and
#'   `loss_ratio` (indemnity / total premium; `NA` without premium). Dollar
#'   amounts are nominal. Attribute `source_url` records where it came from.
#' @examples
#' \dontrun{
#' county <- get_prf_outlook()
#' county[commodity_year == 2030]
#'
#' get_prf_outlook("national", tag = "v1.0.0.2026")
#' }
#' @export
get_prf_outlook <- function(level = c("county", "state", "national"), tag = "latest",
                            repo = prf_outlook_repo, projected_only = TRUE) {
  level <- match.arg(level)
  url <- prf_release_url(paste0("final_prf_outlook_", level, ".csv"), tag, repo)

  dest <- tempfile(fileext = ".csv")
  on.exit(unlink(dest), add = TRUE)
  if (!download_release_asset(url, dest)) {
    stop("Could not download the ", level, " outlook from ", url,
         "\nCheck that release `", tag, "` exists in ", repo,
         " and has this file attached.", call. = FALSE)
  }

  outlook <- fread(dest, colClasses = list(
    character = c("scenario", ".source", "plan_group", "unit_structure_code")
  ))

  required <- c("scenario", "commodity_year", ".source", prf_outcome_cols)
  missing <- setdiff(required, names(outlook))
  if (length(missing)) {
    stop("The release's ", level, " outlook lacks ", paste(missing, collapse = ", "),
         ".", call. = FALSE)
  }

  if (projected_only) outlook <- outlook[.source == "projected"]

  # Releases made before loss_ratio was added to the tables.
  if (!"loss_ratio" %in% names(outlook)) {
    outlook[, loss_ratio := fifelse(total_premium_amount > 0,
                                    indemnity_amount / total_premium_amount, NA_real_)]
  }

  if (level == "county") {
    outlook[, county_fips := sprintf("%02d%03d", as.integer(state_code),
                                     as.integer(county_code))]
    setcolorder(outlook, "county_fips", after = "county_code")
  }

  setattr(outlook, "source_url", url)
  outlook[]
}
