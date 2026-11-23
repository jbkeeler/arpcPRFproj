# arpcPRFproj

Projects outcomes for USDA RMA's Pasture, Rangeland, Forage (PRF) Rainfall
Index insurance: insured acres, liability, premium, subsidy, and indemnity,
by county, over a 10-year window. The results come out in the county
preliminary-outlook layout used by
[arpcFCIPproj](https://github.com/ftsiboe/arpcFCIPproj).

arpcFCIPproj currently projects PRF as a fixed share of its yield-based crop
outlook, so PRF losses follow corn and soybean losses. This package models
how PRF actually pays instead: on a grid rainfall index, by two-month
interval and coverage level. The indemnity mechanics are checked against the
Summary of Business.

Full data sources, methods, validation, and known limitations are in
[METHODS.md](METHODS.md).

## Installation

```r
# install.packages("devtools")
devtools::install_github("jbkeeler/arpcPRFproj")
```

## Quick start

To use the published outlook without running anything:

```r
library(arpcPRFproj)

# Latest release: projected acres, liability, premium, subsidy, indemnity,
# and loss ratio by county and year, from the baseline year on ("state" and
# "national" also available)
county <- get_prf_outlook()
county[commodity_year == 2030]
```

Releases hold the projected years only. The observed history stays in the
local `.rds` tables that the outlook scripts write.

To build a projection yourself:

```r

# Book of business: SOB-TPU summed to county x type x interval x coverage
book <- build_prf_book(get_prf_sobtpu(baseline = 2025, window = 13))

# Check the indemnity model against history, and fit the optional
# large-county calibration from that check
backtest <- backtest_prf_book(book)
calibration <- fit_prf_calibration(backtest)

# Project 2025-2035, then format for arpcFCIPproj
projection <- project_prf_book(book, baseline_year = 2025, calibration = calibration)
outlook <- prf_fcip_outlook(book, projection)
plot_prf_outlook(outlook)
```

The first run downloads RMA rainfall index releases, NCEI precipitation, and
the 2027 ADM. Everything is cached afterwards (`tools::R_user_dir("arpcPRFproj", "cache")`).

## Key options

`project_prf_book()`:

| Argument | Default | What it does |
|---|---|---|
| `baseline_year` | last full SOB year | Book year the projection starts from |
| `projection_window` | `10` | Years projected past the baseline |
| `acreage_fit` | `fit_prf_acreage(book, baseline_year)` | Grazing acres move toward a state ceiling. `NULL` holds acres at the baseline |
| `nowcast` | `TRUE` | Use realized rainfall for intervals already observed |
| `calibration` | `NULL` | Large-county indemnity correction from `fit_prf_calibration()`. `NULL` applies none |
| `index` | `NULL` | Rainfall index to use. `NULL` uses the RMA release each year is rated on |

Rainfall index data:

- `get_prf_index(source = "rma")` reads RMA's published releases.
  `source = "ncei"` computes the index from NCEI precipitation; this matches
  RMA's 2027 release exactly and also covers the current year.
- `get_county_payment_factors()` converts grid index values into
  area-weighted county payment factors.

## Methods and assumptions

- **Payments.** Each grid pays `max(0, (coverage - index) / coverage)`.
  Payment factors are computed per grid, then area-weighted across the
  county's grids, because SOB reports by county, not grid.
- **Indemnity** is liability × the county payment factor, averaged over the
  rainfall history of the index release each year is rated on. That is CPC
  data through 2026 and NCEI data from 2027, which pays about 6–11% less for
  the same weather. Ranges come from running the book through every past
  rainfall year, keeping counties together so drought patterns hold.
- **Behavior is stable.** The baseline mix of intervals and coverage levels
  is held fixed. No demand response or weather forecast is used.
- **Acres** close a fixed share of the gap to a state ceiling each year (about
  4%). The ceiling is a share of eligible land: Census pasture plus BLM and
  Forest Service grazing allotments. Haying follows its state's grazing
  growth.
- **Liability and premium** move with ADM county base values and premium
  rates, applied as ratios to the baseline book. Years past the latest ADM
  keep its values.
- **Large-county calibration (optional).** Area weighting understates
  indemnity in counties with many grids (about 0.92 of actual with more than
  50 grids). The calibration scales each county by its backtest ratio of
  actual to predicted indemnity, shrunk toward its size class.

**Validation.** On 2013–2024, predicted indemnity is 0.963 of actual before
the calibration, and county loss costs correlate at 0.96.

**Main limitations.** The backtest uses CPC data that ends at 2024, so it
covers fewer years with each new baseline and must move to NCEI data. No
county enters or leaves PRF, and acres never decline. The ranges reflect
rainfall only. See METHODS.md §7 for the full list.

## Building a release

The release outlook is built by the numbered scripts in
[data-raw/scripts/prf-outlook/](data-raw/scripts/prf-outlook/). Run them all
with:

```
Rscript data-raw/scripts/prf-outlook/run_prf_outlook.R
```

Settings are set at the top of `00_prf_outlook_setup_and_data.R`: baseline
year, windows, nowcast, calibration, and `scenarios`. Only the `main`
acreage scenario is released for now; add `"flat_acres"` to `scenarios` to
release the flat-acres comparison as well. Outputs go to
`data-raw/releases/prf-outlook/` (gitignored). See METHODS.md §9.

### Publishing an outlook

`get_prf_outlook()` reads the files attached to a GitHub release of this
repository. To publish one:

1. **Run the outlook** (above) and check the printed national totals.
2. **Commit and push the code**, so the release tag points to the code that
   produced it.
3. **Create the release**, attaching the tables under their exact names:

   ```sh
   gh auth login   # once
   gh release create v1.0.0.2026 \
     data-raw/releases/prf-outlook/final_prf_outlook_county.csv \
     data-raw/releases/prf-outlook/final_prf_outlook_state.csv \
     data-raw/releases/prf-outlook/final_prf_outlook_national.csv \
     data-raw/releases/prf-outlook/prf_indemnity_ranges.csv \
     data-raw/releases/prf-outlook/figures/prf_outlook.png \
     --title "PRF outlook, 2025 baseline" --latest \
     --notes "Baseline 2025, projected 2025-2035. Main acreage scenario."
   ```

   On the website, the same is Releases → Draft a new release, with the
   files dragged into the assets box.
4. **Check it:** `get_prf_outlook("national")` should return the new
   release.

Tags follow the `v1.0.0.2026` pattern used for the first release (2025
baseline, released in 2026). With no tag, `get_prf_outlook()` reads the
release GitHub marks as latest. Any other release published later, such as
a package version without these files attached, becomes latest instead;
mark it `--latest=false`.

## AI disclosure

This package was developed with help from Anthropic's Claude,
used through Claude Code. It was used to write and refactor code, write tests
and documentation (including this README and METHODS.md), and check results
against the data. The author directed the work, reviewed the changes, edited documentation, ran
the tests and validation reported in METHODS.md, and is responsible for the
package's content. Report errors through the repository's issues.

## Development

```r
devtools::load_all()   # load the package for interactive work
devtools::document()   # regenerate NAMESPACE and man/ from roxygen comments
devtools::test()       # run tests/testthat
devtools::check()      # full R CMD check
```

- `R/`: package functions, documented with roxygen2. Use data.table for
  data manipulation; it is imported package-wide.
- `tests/testthat/`: unit tests.
- `data-raw/`: scripts that build `data/*.rda` (`prf_grid_county`,
  `prf_county_forage_acres`, `prf_county_allotment_acres`), plus the outlook
  scripts.
