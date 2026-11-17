# arpcPRFproj: data, methods, and assumptions

arpcPRFproj projects Pasture, Rangeland, Forage (PRF) Rainfall Index insurance
outcomes: insured acres, liability, total premium, subsidy, and indemnity. The
results are formatted as a county-level preliminary outlook that
[arpcFCIPproj](https://github.com/ftsiboe/arpcFCIPproj) can use.

Throughout, we chose methods that are simple, can be explained to a
moderately technical audience, and are tested against history. Behavioral
responses(e.g. interval choice), demand elasticities, and weather or
climate forecasts, are left for later versions.

Code references are to files in this repository. Figures and the numbers
quoted for the 2025-baseline projection come from the outlook scripts in
[data-raw/scripts/prf-outlook/](data-raw/scripts/prf-outlook/) (§9).

---

## 1. Why a PRF-specific projection

arpcFCIPproj projects PRF as a fixed state share of its APH (yield-based) crop
outlook (`simulate_from_aph()` in arpcFCIPproj). PRF indemnities therefore
follow projected corn and soybean losses, not rainfall. Its current release
projects about \$4.3B a year in PRF indemnity, a loss ratio of 2.56. PRF's
observed loss ratio was 0.98 over 2013–2025.

This package models PRF's actual payment mechanics instead: a grid
rainfall index, interval-level coverage, and county base values. It keeps the
county × type × interval × coverage detail and checks the indemnity mechanics
against the Summary of Business.

## 2. Data

| Data | Source | Code |
|---|---|---|
| Book of business: acres, liability, premium, subsidy, and indemnity by county, type, practice (interval), and coverage | RMA Summary of Business by type, practice, and unit (SOB-TPU), via rfcip | [R/get_prf_sobtpu.R:22](R/get_prf_sobtpu.R#L22), [R/prf_book.R:44](R/prf_book.R#L44) |
| County base values, premium rates, subsidy schedule | RMA Actuarial Data Master (ADM) tables A00810, A01130, A01135, A00070: via rfcip, or directly from RMA for 2027 | [R/prf_actuarial.R:24](R/prf_actuarial.R#L24), [R/prf_adm_rma.R](R/prf_adm_rma.R) |
| Rainfall index, as published | RMA `VI_RI_Data` releases, one per crop year | [R/prf_index_rma.R:81](R/prf_index_rma.R#L81) |
| Rainfall index, computed (history and current year) | NCEI USDA monthly gridded precipitation (nClimGrid, 1/4°) | [R/prf_index_ncei.R:141](R/prf_index_ncei.R#L141), [R/prf_index.R:56](R/prf_index.R#L56) |
| Grid × county weights (`prf_grid_county`) | RMA Rainfall Index grid shapefile; Census 2020 county boundaries (plus 2023 Connecticut planning regions) | [data-raw/prf_grid_county.R](data-raw/prf_grid_county.R) |
| Pasture and hay acres (`prf_county_forage_acres`) | NASS Census of Agriculture 2007–2022, Quick Stats | [data-raw/prf_county_forage_acres.R](data-raw/prf_county_forage_acres.R) |
| Federal grazing allotments (`prf_county_allotment_acres`) | BLM grazing allotments and surface management layers; USFS range allotments | [data-raw/prf_county_allotment_acres.R](data-raw/prf_county_allotment_acres.R) |

Notes on the data:

- **SOB acres are allocated acres.** Each interval row reports the acres
  allocated to that interval. Liability ÷ (acres × CBV × coverage) comes out
  at 1.5, the maximum productivity factor, for the median dollar of
  liability. So summing acres across intervals gives the land insured, not a
  multiple of it.
- **The ADM comes from rfcip, except 2027.**
  - As of November 2026, rfcip's 2027 tables have no PRF records, even after
    a forced refresh. So 2027 is read from RMA's year-to-date ADM file.
  - That file is 1.3 GB. The PRF records are filtered out and cached (a few
    MB), and column names are mapped to rfcip's
    ([R/prf_adm_rma.R:30](R/prf_adm_rma.R#L30)).
  - When rfcip carries 2027, remove it from `rma_adm_years`
    ([R/prf_adm_rma.R:6](R/prf_adm_rma.R#L6)).
- **PRF county base values have not changed since 2025.** They are identical
  in RMA's 2025, 2026, and 2027 files. Premium rates were essentially flat
  from 2025 to 2026 (−0.05%) and fell 9.3% on average for 2027, when RMA
  re-rated PRF on NCEI data.

## 3. Book of business

[`build_prf_book()`](R/prf_book.R#L44) does the following:

- Keeps SOB-TPU rows with liability.
- Parses the two-month index interval (625 = Jan–Feb … 635 = Nov–Dec) from
  the practice name ([R/prf_book.R:15](R/prf_book.R#L15)). SOB carries the
  interval only there.
- Sums outcomes to county × type × practice × interval × coverage level.


## 4. Rainfall index and payments

### 4.1 Index values

The index is interval precipitation divided by the grid's normal, where the
normal is the mean over the normal period through two years before the crop
year. Values are rounded half up to three decimals, as RMA publishes them
([R/prf_index.R:27](R/prf_index.R#L27)).

**Data source change (CPC to NCEI).**
- RMA releases through crop year 2026 are built on NOAA CPC data, with a
  normal starting in 1948. From 2027, releases use NCEI data, with a normal
  starting in 1951.
- [`get_prf_index_ncei()`](R/prf_index_ncei.R#L141) reproduces RMA's 2027
  release exactly: all 11.16M shared values match.
- Its grid ID formula ([R/prf_index_ncei.R:65](R/prf_index_ncei.R#L65)) was
  checked against all 36,000 cells in RMA's grid shapefile.
- NCEI also provides the current year's intervals, which RMA releases omit.
  These feed the nowcast (§5.2).

**Why the source matters.** On the same weather years, NCEI-based releases pay
noticeably less than CPC:
- For 2013–2024, the backtest (§6) gives 0.852 of actual indemnity on NCEI,
  against 0.963 on CPC.
- On the 2025 book, NCEI history gives about 7% lower expected indemnity than
  CPC (\$1.17B against \$1.26B over 1951–2024).

So each projection year uses the release it is rated and paid on: CPC through
2026, NCEI from 2027 ([R/prf_outlook.R:151](R/prf_outlook.R#L151)). RMA's
2027 rates fell by a similar amount (9.3%), so projected loss ratios stay
roughly level across the switch.

### 4.2 Grid to county

PRF pays by grid, but SOB reports by county. `prf_grid_county` gives each
grid's share of a county's area, from the intersection of grid cells and
counties. It is computed in an equal-area projection (EPSG:5070)
([data-raw/prf_grid_county.R:66](data-raw/prf_grid_county.R#L66)) and has
about 30,900 county–grid rows across 3,108 counties.

Motivation:
- The constraint is public SOB data, which has no grid detail, so weights must
  come from geography.
- We weight by intersection area because it's transparent.
- Area weighting understates indemnity in large counties. That is corrected
  separately (§5.3) rather than by changing the weights.
- NLCD land-cover weights barely helped (large counties moved from 0.935 to
  0.938).

### 4.3 Payment factors

The payment factor for a grid is max(0, (coverage − index) / coverage)
([R/prf_payment_factors.R:38](R/prf_payment_factors.R#L38)). It is computed
for each grid and then area-weighted across the county's grids
([R/prf_payment_factors.R:76](R/prf_payment_factors.R#L76)).

The factor is not linear in the index. Averaging the index first would smooth
out dry grids and understate payments (Jensen's inequality).

## 5. Projection

[`project_prf_book()`](R/prf_outlook.R#L105) projects from a baseline year,
2025 by default, over a 10-year window. For each year t, at the book grain:

```
acre ratio  = projected grazing acres(t) / baseline acres         (§5.1)
liability   = baseline liability x acre ratio x CBV(t) / CBV(baseline)
premium     = baseline premium   x acre ratio x CBV ratio x rate(t) / rate(baseline)
subsidy     = premium x ADM subsidy percent(t)
indemnity   = liability x payment factor x calibration factor    (§5.2-5.3)
```

([R/prf_outlook.R:120-175](R/prf_outlook.R#L120-L175))

The payment factor is one of the following:
- **Expected:** the mean over the history of the index release the year is
  rated on.
- **Realized:** for intervals already observed (the nowcast).
- **Observed loss cost:** for counties outside the continental grid, such as
  Hawaii ([R/prf_outlook.R:163](R/prf_outlook.R#L163)).

**Assumptions**

- **Behavior is stable.** The mix of intervals and coverage levels in the
  baseline book is held fixed.
  - The data support this: the year-to-year correlation of county × interval ×
    coverage liability shares rose from 0.69 (2018) to 0.86 (2026).
  - The grazing/haying split has held at 72–77% grazing since 2020.
- **Liability follows base values.** CBV and rate changes come from the ADM,
  area-weighted to the county ([R/prf_outlook.R:26](R/prf_outlook.R#L26)).
  - Ratios to the baseline are applied to observed SOB levels, so the
    weighting largely cancels.
  - Years after the latest ADM (2027) keep its values. Because base values
    have not changed since 2025, projected liability grows only through acres.
- **Premium and subsidy track liability.** From 2014 to 2026, premium ÷
  liability stayed between 0.21 and 0.23, and subsidy ÷ premium between 0.530
  and 0.535. Premium moves with ADM rates, including the 2027 NCEI re-rating.
- **Indemnity has no weather forecast.** Years without observed rainfall use
  expected payments from the full index history.

### 5.1 Acreage: partial adjustment toward a ceiling

PRF grew 20–40% a year from 2017 to 2023, then 0.2%, 7.9%, and 4.7% in
2024–2026. ARPC briefs describe this as approaching saturation in western
states:
- Tsiboe, Davis and Turner (2025), *PRF Insurance Expansion and Emerging
  Limits to Growth*.
- Tsiboe and Davis (2026), *Continued PRF Insurance Expansion in 2026*.

**Model** ([R/prf_acreage.R](R/prf_acreage.R)). Each year, a county's insured
grazing acres close a fixed share of the gap to a ceiling:

```
acres(t + 1) = acres(t) + speed x max(0, ceiling x eligible acres - acres(t))
```

- **Eligible grazing acres** ([R/prf_acreage.R:21](R/prf_acreage.R#L21)) are
  2022 Census pastureland plus federal land in BLM and Forest Service grazing
  allotments.
- **Estimation.** The speed (common to all states) and the ceiling (by state,
  capped at all eligible acres) come from a single regression on the last
  three years of county changes:
  - change ÷ eligible acres on prior penetration, with a state intercept,
    weighted by eligible acres ([R/prf_acreage.R:81](R/prf_acreage.R#L81)).
  - States with few county-years share one ceiling.
- **Fitted values.** Fitting on 2023–2025, the speed is 0.043 a year. Most
  large western and Plains states reach the cap.

**Why partial adjustment**

- **It's an AR(1) in penetration.** Rewriting gives
  p(t) = speed × ceiling + (1 − speed) × p(t − 1). Persistence is
  1 − speed, and the long-run mean is the ceiling. Pooling across counties
  identifies it; a single short national series would not.
- **It explains easily.** "Each year a county closes about 4% of the
  remaining gap to its state's ceiling."
- **It backtests as well as S-curves.**
  - We compared logistic, Gompertz, and partial adjustment, all with capped
    state ceilings.
  - From a 2025 origin, partial adjustment projected 2026 acres at 1.005 of
    actual, against 0.968 for flat.
  - On the post-boom test (fit on 2024–25), it projected 0.995.
  - All three curves gave similar 2035 paths (370–381M acres). The ceiling and
    denominator matter more than the curve shape.
  - PRF is past its inflection point, so an S-shape adds little. The
    logistic-versus-Gompertz choice is long debated and fragile (Griliches
    1957; Dixon 1980).
- **An AR(1) on growth rates (damped trend) was rejected.**
  - Growth persistence is weak (ρ between −0.12 and 0.29), so it becomes
    constant growth at the recent average (5–10% a year) with no saturation.
  - It backtested worse than flat (1.85 from 2023 for grazing).

**Why Census pasture plus allotments as the denominator**

- Census pastureland alone counts only land in farms. Nevada insures 37M
  grazing acres against about 4.5M Census pasture acres (8.1 times), and
  Arizona and Utah are 2–3 times. PRF evidently insures federal grazing
  allotments.
- **Allotments in the data:**
  - **BLM:** 150.7M acres. This is BLM-owned land inside allotment
    boundaries, overlaid on a 250 m grid
    ([data-raw/prf_county_allotment_acres.R:74](data-raw/prf_county_allotment_acres.R#L74)).
    The full allotment boundaries cover 232.6M acres, including private and
    state inholdings the Census already counts.
  - **USFS:** 71.4M acres. Active allotments only, scaled to each allotment's
    National Forest acres
    ([data-raw/prf_county_allotment_acres.R:65](data-raw/prf_county_allotment_acres.R#L65)).
- **Effect on penetration.** National grazing penetration is 48%, and only 2%
  of counties exceed 100%, down from 8%. Fitted ceilings became plausible, and
  backtest error fell.
- **Comparison with ARPC.** ARPC's briefs use a land-cover eligibility
  measure (Forest Service Rangelands V1 plus CDL; about 72% national
  penetration in 2026). Adopting it would align our penetration with their
  published figures.

**Haying** follows its state's projected grazing growth
([R/prf_acreage.R:130](R/prf_acreage.R#L130)).

- Haying is 3% of acres but 28% of liability, because haying base values are
  about 4–5 times grazing's per acre. Holding it flat would understate 2035
  liability by about 12%.
- Census hay acres don't identify a haying ceiling: penetration predicts
  little, and the partial adjustment slope has the wrong sign.
- Haying has tracked grazing enrollment, at 20–27 haying acres per 1,000
  grazing acres nationally since 2019.
- Following state grazing growth projected 2026 haying at 0.98 of actual from
  a 2025 origin, against 0.93 for flat. This used realized grazing growth, so
  it is a best case.
- State rather than county growth is used because county growth ratios
  overstated haying (it doubled by 2035). Haying sits in counties with small
  grazing books far below their ceilings.

### 5.2 Nowcast of observed intervals

With `nowcast = TRUE` (the default), intervals of projection years that
already have rainfall data use their realized payment factors instead of
expected ones.
- [`nowcast_payment_factors()`](R/prf_indemnity.R#L43) computes them from
  NCEI's final monthly data, measured against each year's own normal.
- Only intervals with both months final are used. In November 2026 that is
  January–September 2026 (intervals 625–632), as well as all of 2025.

Why:
- A single year can move far from its expected value. 2025's rainfall paid
  16% above the historical average.
- A year with most intervals already settled shouldn't be projected at the
  average.
- Nowcasting the baseline year as well keeps year-over-year growth consistent
  for arpcFCIPproj's benchmarks.

Data source: 2026 was paid on CPC data, which isn't published for the current
year. On 2026's paid intervals (January–June), NCEI-based payments came to
0.945 of SOB indemnity before the calibration (§5.3). Adjusting for CPC (NCEI
pays 6–11% less by interval) would overshoot to about 1.03, or about 1.07
with the calibration. So no adjustment is made. From 2027, PRF is paid on
NCEI data, so the issue goes away.

### 5.3 Large-county calibration (optional)

Area weighting puts insured land evenly across a county. In large western
counties, insured liability sits in higher-paying, higher-rated grids. Backtest
indemnity falls from 0.996 of actual in counties with 6–10 grids to 0.918 in
counties with more than 50 (§6). The premium data independently show insured
liability concentrated in higher-rated grids.

[`fit_prf_calibration()`](R/prf_indemnity.R#L87) scales each county's
indemnity by its backtest ratio of actual to predicted indemnity, shrunk
toward the ratio for counties of its size class (by grids per county)
([R/prf_indemnity.R:126](R/prf_indemnity.R#L126)):

```
calibration_factor = (actual + k x size-class ratio) / (predicted + k)
```

- **Shrinkage.** k is in dollars of predicted indemnity. Counties whose
  predicted indemnity is small relative to k get mostly the size-class ratio.
- **Choosing k.** k is chosen by two-fold cross-validation (fit on even years,
  score on odd, and the reverse) to minimize county loss-cost error. On
  2013–2024 it selects k = \$8M.
- **Resulting factors.** Mean factors are 1.00–1.01 for counties with up to 10
  grids, 1.02 for 11–20, 1.06 for 21–50, and 1.10 for more than 50.
- **Out-of-sample performance** (exploration, with a regression size prior):
  this design brought the backtest from 0.963 to 0.996 overall and to 0.995
  in large counties.

**The calibration is modular.** It's a separate table passed to
`project_prf_book(calibration = ...)` ([R/prf_outlook.R:172](R/prf_outlook.R#L172)).
The default is `NULL`, which applies no calibration. To remove it, stop
passing it, or delete `fit_prf_calibration()` and `calibration_factors()`
along with the four lines that apply it.

The stronger version we explored, with weights tilted so ADM-implied premium
matches SOB premium, cut county error further but is harder to explain, so it
was not implemented.

### 5.4 Range of indemnity outcomes

Expected indemnity is a mean. The range comes from running the projected book
through each weather year of its index release's history.
- Counties are kept together within each weather year, so the spatial
  pattern of droughts is preserved
  ([R/prf_indemnity.R:134](R/prf_indemnity.R#L134)).
- Nowcast intervals are fixed at their realized values.
- The result is stored as attribute `indemnity_by_weather_year` on the
  projection and on the outlook.
- The outlook figure shades the middle 80% of these outcomes. This is the
  spread from rainfall alone; it excludes uncertainty in acreage, base
  values, and the model itself.

With acres growing toward the ceiling, the 10th–90th percentile range of
national indemnity is \$1.54–2.03B in 2026 (only October–December still
open), \$0.86–1.84B in 2027, and \$1.10–2.37B in 2035.

### 5.5 Output for arpcFCIPproj

[`prf_fcip_outlook()`](R/prf_outlook.R#L207) does the following:
- Stacks observed book years (`.source = "observed"`) with the projection
  (`"projected"`).
- Sums to county.
- Adds `plan_group = "prf"` and `unit_structure_code = "OU"`, matching
  arpcFCIPproj's preliminary outlook layout.

Projected rows include the baseline year, because arpcFCIPproj benchmarks
year-over-year changes.

### 5.6 Current projection (2025 baseline, acres toward ceiling)

| Outcome | 2025 | 2026 | 2030 | 2035 |
|---|---:|---:|---:|---:|
| Acres (million) | 300 | 312 | 355 | 399 |
| Liability (\$ billion) | 6.60 | 6.97 | 8.29 | 9.65 |
| Premium (\$ billion) | 1.47 | 1.54 | 1.67 | 1.93 |
| Subsidy (\$ billion) | 0.78 | 0.82 | 0.89 | 1.02 |
| Indemnity (\$ billion) | 1.39¹ | 1.76² | 1.50 | 1.72 |
| Loss ratio | 0.95¹ | 1.14² | 0.90 | 0.90 |

¹ Nowcast from realized 2025 rainfall. Observed 2025 indemnity was
\$1.49 billion. 2025 was paid on CPC data, which the nowcast can't use.

² Nowcast for January–September (intervals 625–632); expected values for
October–December.

## 6. Validation

### 6.1 Indemnity backtest

[`backtest_prf_book()`](R/prf_backtest.R#L48) predicts each observed year's
indemnity from that year's actual index. It uses the same weights and payment
mechanics as the projection, with values re-expressed against each year's own
normal ([R/prf_backtest.R:11](R/prf_backtest.R#L11)). By default it uses the
2026 CPC release, which is what 2013–2024 were paid on.

Results for 2013–2024, predicted ÷ SOB indemnity, before calibration:

- **Overall:** 0.963. Loss-cost correlation is 0.96 at county × year ×
  interval × coverage.
- **By grids per county:**

  | Grids per county | 1–5 | 6–10 | 11–20 | 21–50 | Over 50 |
  |---|---|---|---|---|---|
  | Predicted ÷ actual | 0.992 | 0.996 | 0.978 | 0.946 | 0.918 |

- **By state:** Texas 1.000, Kansas 1.002, Nevada 0.870, Wyoming 0.849.

The backtest is also the input to the calibration (§5.3). A calibrated
backtest would be in-sample, so the figures show the uncalibrated version.

**The backtest window shrinks with each baseline.** The 2026 CPC release ends
at 2024, and the book covers the 13 years through the baseline. So a 2027
baseline backtests 2015–2024 and a 2030 baseline 2018–2024. From a 2037
baseline no years overlap, and the backtest (and with it the calibration)
stops with an error. Later releases need to backtest the years paid on NCEI
data (2027 on) against an NCEI release.

### 6.2 What drives the large-county shortfall

- **Normals.** Rating each year against its own normal accounts for about a
  quarter of the gap, in the backtest only. Index revisions and rounding have
  no effect.
- **Premium signal.** Insured liability sits in higher-rated grids in large
  counties: SOB premium runs 0.7–2.4% above the area-weighted ADM premium.
  Across counties, this premium gap predicts the indemnity gap (slope 1.6,
  t = 24).
- **Persistence.** County ratios are persistent between even and odd years,
  which is why county credibility factors work out of sample.

### 6.3 Acreage backtest

These rolling-origin comparisons used scratch scripts, not package code:

- **From a 2025 origin:** partial adjustment projected 2026 acres at 1.005 of
  actual, against 0.968 for flat. County error was similar (0.089 against
  0.086).
- **From earlier origins (2021–2023):** every curve overshoots, because the
  fit windows include boom years. This is the main source of acreage forecast
  uncertainty.

## 7. Known limitations and open items

- **2027 ADM comes from RMA.** It requires a one-time 1.3 GB download. Switch
  back to rfcip when it carries 2027 PRF records.
- **Nowcast on the wrong source for CPC years.** The 2025 and 2026 nowcasts
  use NCEI data for years paid on CPC. On 2026's paid intervals this was 5%
  low before calibration.
- **Calibration is estimated on CPC-era payments.** It is applied unchanged to
  NCEI-era years.
- **Backtest needs to move to NCEI.** The CPC backtest covers fewer years
  with each baseline and none from a 2037 baseline (§6.1). Backtest 2027-on
  years against an NCEI release before then.
- **Acreage fit window.** The default three-year window ending in 2025
  includes the 2023 boom year. Fitting on 2024–2026 gives lower ceilings in
  Texas, Kansas, and Oklahoma, and about 380M acres in 2035 rather than 395M.
- **Denominator.** Census pastureland assigns land to an operation's
  principal county. State trust grazing leases are missing, so Arizona is
  still above 100% penetration.
- **No entry or exit.** Counties with no PRF in the baseline are not
  projected, and acres never decline.
- **Ranges reflect rainfall only.** They exclude acreage, base value, and
  model uncertainty.
- **No behavioral or weather response.** Interval and coverage mix, demand
  elasticity, and climate forecasts are deferred to later versions.

## 8. Figures

[R/prf_plots.R](R/prf_plots.R) follows the arpcFCIPproj price projection
style: minimal theme, observed solid, projected dashed.

- [`plot_prf_outlook()`](R/prf_plots.R#L45) shows national totals for one or
  more scenarios. The first scenario's indemnity and loss ratio are shaded
  over the middle 80% of weather-year outcomes (`range` argument; `NULL`
  turns the bands off).
- [`plot_prf_backtest()`](R/prf_plots.R#L146) shows the backtest by year,
  county, county size, or state.
- [200_prf_outlook_exhibits.R](data-raw/scripts/prf-outlook/200_prf_outlook_exhibits.R)
  draws the figures from the saved release files, so they can be redrawn
  without recomputing.

## 9. Building an outlook

The outlook is built by numbered scripts in
[data-raw/scripts/prf-outlook/](data-raw/scripts/prf-outlook/), following
arpcFCIPproj's `fcip-outlook` scripts. Each script saves its outputs to
`data-raw/releases/prf-outlook/` (gitignored). The next script reads those
files and stops if any are missing.

| Script | Does | Saves |
|---|---|---|
| [00_prf_outlook_setup_and_data.R](data-raw/scripts/prf-outlook/00_prf_outlook_setup_and_data.R) | Settings; SOB-TPU book of business | `prf_outlook_settings.rds`, `book.rds` |
| [01_prf_outlook_models.R](data-raw/scripts/prf-outlook/01_prf_outlook_models.R) | Indemnity backtest, large-county calibration, acreage model | `backtest.rds`, `calibration.rds`, `acreage_fit.rds` |
| [02_prf_outlook_projection.R](data-raw/scripts/prf-outlook/02_prf_outlook_projection.R) | Projection under the acreage scenarios in the settings (`main`; `flat_acres` is available but off for now); arpcFCIPproj county outlooks | `projection_<scenario>.rds`, `outlook_county_<scenario>.rds` |
| [03_prf_outlook_release.R](data-raw/scripts/prf-outlook/03_prf_outlook_release.R) | County, state, and national outlooks; national indemnity ranges; a record of the run | `final_prf_outlook_<level>.rds/.csv`, `prf_indemnity_ranges.csv`, `prf_outlook_run.rds` |
| [200_prf_outlook_exhibits.R](data-raw/scripts/prf-outlook/200_prf_outlook_exhibits.R) | Figures | `figures/*.png` |

**Settings.** These are set in script 00: baseline year (default
`prf_policy_year() - 1`), projection window, SOB history window, acreage fit
years, whether to use the nowcast and calibration, and which acreage
scenarios to release (`scenarios`; only `main` for now, add `flat_acres`
to release the flat-acres comparison too).

**Running it.**
[run_prf_outlook.R](data-raw/scripts/prf-outlook/run_prf_outlook.R) runs all
steps in order, each in a fresh R process:

```
Rscript data-raw/scripts/prf-outlook/run_prf_outlook.R
```

A first run downloads RMA index releases, NCEI precipitation, and the 2027 ADM
(cached afterwards). Later runs take about 15 minutes.

**The run record.** `prf_outlook_run.rds` records:
- The settings.
- The calibration k and acreage adjustment speed and ceilings.
- The ADM years read from RMA and the latest index release.
- Package versions.

**Rebuilding package datasets.** The datasets (`prf_grid_county`,
`prf_county_forage_acres`, `prf_county_allotment_acres`) come from the other
`data-raw/` scripts. Rerun them only when a source updates.

## References

- Dixon, R. 1980. "Hybrid Corn Revisited." *Econometrica* 48(6): 1451–1461.
- Goodrich, B., and K. Davidson. 2024. "Enrollment in Pasture, Rangeland, and
  Forage Rainfall Index Insurance: Awareness Matters." *Journal of
  Agricultural and Resource Economics*.
- Goodrich, B., J. Yu, and M. Vandeveer. 2020. "Participation Patterns of the
  Rainfall Index Insurance for Pasture, Rangeland and Forage Programme."
  *Geneva Papers on Risk and Insurance* 45: 29–51.
- Griliches, Z. 1957. "Hybrid Corn: An Exploration in the Economics of
  Technological Change." *Econometrica* 25(4): 501–522.
- Tsiboe, F., W. Davis, and D. Turner. 2025. "Pasture, Rangeland, and Forage
  (PRF) Insurance Expansion and Emerging Limits to Growth." ARPC Brief, North
  Dakota State University.
- Tsiboe, F., and W. Davis. 2026. "Continued Pasture, Rangeland, and Forage
  (PRF) Insurance Expansion in 2026." ARPC Brief, North Dakota State
  University. doi:10.22004/ag.econ.396375.
- Turner, D., and F. Tsiboe. 2024. "Pasture, Rangeland, and Forage Drive
  Increased Participation in Federal Crop Insurance Program." *Amber Waves*,
  USDA ERS.
