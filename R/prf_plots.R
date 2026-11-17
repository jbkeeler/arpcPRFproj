# Figures for the PRF outlook and backtest, styled like the arpcFCIPproj
# price projection figures: minimal theme, history solid and projections
# dashed, legend at the bottom. Each function returns a ggplot object.

theme_prf <- function() {
  theme_minimal(base_size = 10) +
    theme(legend.position = "bottom", legend.box = "vertical")
}

# Time-series axes: a label for every year, y starting at 0.
yearly_axes <- function(years) {
  list(scale_x_continuous(breaks = seq(min(years), max(years))),
       expand_limits(y = 0),
       theme(axis.text.x = element_text(angle = 90, vjust = 0.5),
             panel.grid.minor.x = element_blank()))
}

prf_outlook_labels <- c(
  insured_acres = "Net reported acres\n(million)",
  liability_amount = "Liability\n(billion dollars)",
  total_premium_amount = "Total premium\n(billion dollars)",
  subsidy_amount = "Subsidy\n(billion dollars)",
  indemnity_amount = "Indemnity\n(billion dollars)",
  loss_ratio = "Loss ratio\n(indemnity / total premium)"
)

#' Plot the PRF outlook
#'
#' National totals by commodity year: net reported acres, liability,
#' premium, subsidy, indemnity, and loss ratio. Observed years are solid and
#' projected years dashed. Pass a named list of outlooks to compare
#' scenarios; each gets its own color.
#'
#' Projected indemnity and loss ratio of the first scenario are shaded over
#' the central `range` of outcomes across the weather years of the index
#' history (attribute `indemnity_by_weather_year` of the projection): the
#' spread from rainfall alone, not from acreage, prices, or model error.
#'
#' @param outlook Outlook from [prf_fcip_outlook()], or a named list of them.
#' @param first_year First commodity year to show. Defaults to all years.
#' @param range Share of weather years inside the shaded band, or `NULL` for
#'   no band.
#'
#' @return A ggplot object.
#' @examples
#' \dontrun{
#' plot_prf_outlook(list(
#'   "Flat acres" = prf_fcip_outlook(book, project_prf_book(book, acreage_fit = NULL)),
#'   "Acres toward ceiling" = prf_fcip_outlook(book, project_prf_book(book))
#' ), first_year = 2015)
#' }
#' @export
plot_prf_outlook <- function(outlook, first_year = NULL, range = 0.8) {
  if (is.data.frame(outlook)) outlook <- list(Projected = outlook)
  national <- rbindlist(lapply(outlook, function(x) {
    as.data.table(x)[, lapply(.SD, sum), by = .(commodity_year, .source),
                     .SDcols = prf_outcome_cols]
  }), idcol = "scenario")
  if (!is.null(first_year)) national <- national[commodity_year >= first_year]
  national[, loss_ratio := indemnity_amount / total_premium_amount]

  long <- melt(national, id.vars = c("scenario", "commodity_year", ".source"),
               variable.name = "outcome", variable.factor = FALSE)
  long[, value := value / prf_outlook_scale(outcome)]
  long[, outcome := factor(prf_outlook_labels[outcome], levels = prf_outlook_labels)]
  long[, line_type := fifelse(.source == "observed", "Observed", "Projected")]
  # Observed years are the same in every scenario; draw them once.
  long <- long[line_type == "Projected" | scenario == names(outlook)[1]]
  long[line_type == "Observed", scenario := "Observed"]

  colors <- c(Observed = "grey30",
              stats::setNames(unname(ndsu_colors)[seq_along(outlook)], names(outlook)))
  baseline_year <- min(long[line_type == "Projected", commodity_year])
  subtitle <- paste0("Observed (RMA Summary of Business) solid; projected from the ",
                     baseline_year, " book dashed. Nominal dollars.")

  figure <- ggplot(long, aes(commodity_year, value, color = scenario))
  bands <- if (is.null(range)) NULL else weather_bands(outlook, national, range)
  if (!is.null(bands) && nrow(bands)) {
    figure <- figure +
      geom_ribbon(data = bands, aes(commodity_year, ymin = low, ymax = high, fill = scenario),
                  inherit.aes = FALSE, alpha = 0.15) +
      scale_fill_manual(values = colors, guide = "none")
    subtitle <- paste0(subtitle, "\nShaded: middle ", round(100 * range),
                       "% of outcomes across past rainfall years.")
  }

  figure +
    geom_line(aes(linetype = line_type, group = interaction(scenario, line_type))) +
    facet_wrap(~outcome, scales = "free_y") +
    yearly_axes(long$commodity_year) +
    scale_color_manual(values = colors, breaks = names(colors)) +
    scale_linetype_manual(values = c(Observed = "solid", Projected = "dashed"), guide = "none") +
    labs(title = "PRF outlook, national totals", subtitle = subtitle,
         x = NULL, y = NULL, color = NULL, linetype = NULL) +
    theme_prf() +
    theme(axis.text.x = element_text(angle = 90, vjust = 0.5),
             panel.grid.minor.x = element_blank())
}

prf_outlook_scale <- function(outcome) {
  fcase(outcome == "insured_acres", 1e6, outcome == "loss_ratio", 1, default = 1e9)
}

# Quantile bands of national indemnity and loss ratio across weather years,
# for the first scenario.
weather_bands <- function(outlook, national, range) {
  probs <- c((1 - range) / 2, 1 - (1 - range) / 2)
  bands <- rbindlist(lapply(names(outlook)[1], function(name) {
    by_weather <- attr(outlook[[name]], "indemnity_by_weather_year")
    if (is.null(by_weather)) return(NULL)
    by_weather <- merge(by_weather, national[scenario == name & .source == "projected",
                                             .(commodity_year, total_premium_amount)],
                        by = "commodity_year")
    by_weather[, loss_ratio := indemnity_amount / total_premium_amount]
    melt(by_weather, id.vars = "commodity_year", measure.vars = c("indemnity_amount", "loss_ratio"),
         variable.name = "outcome", variable.factor = FALSE)[
      , .(low = stats::quantile(value, probs[1]), high = stats::quantile(value, probs[2])),
      by = .(commodity_year, outcome)][, scenario := name]
  }))
  if (!nrow(bands)) return(bands)
  bands[, `:=`(low = low / prf_outlook_scale(outcome), high = high / prf_outlook_scale(outcome))]
  bands[, outcome := factor(prf_outlook_labels[outcome], levels = prf_outlook_labels)]
}

# Grids per county, in size classes.
county_grid_classes <- function(crosswalk) {
  crosswalk[, .(grids = .N), by = .(state_code, county_code)][
    , grid_class := cut(grids, c(0, 5, 10, 20, 50, Inf),
                        labels = c("1-5", "6-10", "11-20", "21-50", "Over 50"))]
}

#' Plot a PRF indemnity backtest
#'
#' Compares predicted and SOB indemnities from [backtest_prf_book()].
#'
#' * `"year"`: national indemnity and loss cost (indemnity / liability) by year.
#' * `"county"`: county loss cost over all backtest years, predicted against
#'   actual, sized by liability and colored by grids per county.
#' * `"grids"`: predicted / actual indemnity by grids per county.
#' * `"state"`: predicted / actual indemnity for the states with the most
#'   liability.
#'
#' @param backtest Output of [backtest_prf_book()].
#' @param type Which figure to draw; see Details.
#' @param crosswalk Grid-to-county weights used to count grids per county.
#' @param states Number of states to show for `type = "state"`.
#'
#' @return A ggplot object.
#' @examples
#' \dontrun{
#' backtest <- backtest_prf_book(book)
#' plot_prf_backtest(backtest, "year")
#' plot_prf_backtest(backtest, "grids")
#' }
#' @export
plot_prf_backtest <- function(backtest, type = c("year", "county", "grids", "state"),
                              crosswalk = prf_grid_county, states = 15) {
  type <- match.arg(type)
  backtest <- as.data.table(backtest)
  years <- range(backtest$commodity_year)
  subtitle <- paste0("Actual: RMA Summary of Business, ", years[1], "-", years[2],
                     ". Predicted: liability x area-weighted grid payment factor.")
  bar_fill <- ndsu_colors[["ndsu_green"]]
  ratio_axis <- "Predicted / actual indemnity"

  figure <- switch(type,
    year = {
      national <- backtest[, .(Actual = sum(indemnity_amount),
                               Predicted = sum(predicted_indemnity),
                               liability = sum(liability_amount)), by = commodity_year]
      long <- melt(national, id.vars = c("commodity_year", "liability"),
                   variable.name = "series", variable.factor = FALSE)
      long <- rbind(
        long[, .(commodity_year, series, value = value / 1e9,
                 panel = "Indemnity\n(billion dollars)")],
        long[, .(commodity_year, series, value = value / liability,
                 panel = "Loss cost\n(indemnity / liability)")]
      )
      ggplot(long, aes(commodity_year, value, color = series)) +
        geom_line() +
        facet_wrap(~panel, scales = "free_y") +
        yearly_axes(years) +
        scale_color_manual(values = c(Actual = "grey30",
                                      Predicted = ndsu_colors[["ndsu_green"]])) +
        labs(title = "PRF indemnity backtest by year", x = NULL, y = NULL, color = NULL)
    },
    county = {
      county <- backtest[, .(actual = sum(indemnity_amount) / sum(liability_amount),
                             predicted = sum(predicted_indemnity) / sum(liability_amount),
                             liability = sum(liability_amount) / 1e6),
                         by = .(state_code, county_code)]
      county <- merge(county, county_grid_classes(crosswalk), by = c("state_code", "county_code"))
      limit <- max(county$actual, county$predicted)
      ggplot(county, aes(actual, predicted, size = liability, color = grid_class)) +
        geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey40") +
        geom_point(alpha = 0.5) +
        coord_equal(xlim = c(0, limit), ylim = c(0, limit)) +
        scale_color_manual(values = unname(ndsu_colors[c("ndsu_sage", "ndsu_teal", "ndsu_green",
                                                         "ndsu_yellow", "ndsu_rust")])) +
        scale_size_area(max_size = 6) +
        guides(color = guide_legend(override.aes = list(size = 3, alpha = 1))) +
        labs(title = "PRF indemnity backtest by county",
             x = "Actual loss cost (indemnity / liability)", y = "Predicted loss cost",
             color = "Grids per county", size = "Liability ($ million)")
    },
    grids = {
      by_class <- merge(backtest, county_grid_classes(crosswalk),
                        by = c("state_code", "county_code"))[
        , .(ratio = sum(predicted_indemnity) / sum(indemnity_amount),
            liability = sum(liability_amount)), keyby = grid_class]
      by_class[, label := sprintf("%.3f\n%.0f%% of liability", ratio,
                                  100 * liability / sum(liability))]
      ggplot(by_class, aes(grid_class, ratio)) +
        geom_col(fill = bar_fill, width = 0.7) +
        geom_hline(yintercept = 1, linetype = "dashed", color = "grey40") +
        geom_text(aes(label = label), vjust = 1.4, size = 3, color = "white") +
        labs(title = "PRF indemnity backtest by county size",
             x = "Grids per county", y = ratio_axis)
    },
    state = {
      by_state <- backtest[, .(ratio = sum(predicted_indemnity) / sum(indemnity_amount),
                               liability = sum(liability_amount)), by = state_abbreviation]
      by_state <- by_state[order(-liability)][seq_len(min(states, .N))]
      by_state[, state_abbreviation := stats::reorder(state_abbreviation, ratio)]
      ggplot(by_state, aes(ratio, state_abbreviation)) +
        geom_col(fill = bar_fill, width = 0.7) +
        geom_vline(xintercept = 1, linetype = "dashed", color = "grey40") +
        geom_text(aes(label = sprintf("%.3f", ratio)), hjust = 1.15, size = 3, color = "white") +
        labs(title = paste("PRF indemnity backtest, the", nrow(by_state),
                           "states with the most liability"),
             x = ratio_axis, y = NULL)
    }
  )

  figure <- figure + labs(subtitle = subtitle) + theme_prf()
  # theme_prf() is a complete theme; restore the rotated year labels.
  if (type == "year") figure <- figure + theme(axis.text.x = element_text(angle = 90, vjust = 0.5),
             panel.grid.minor.x = element_blank())
  figure
}
