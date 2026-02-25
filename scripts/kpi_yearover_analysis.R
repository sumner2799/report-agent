# ==============================================================================
# Year-to-Year KPI Improvement & Performance Analysis
#
# Analyzes how players with elevated Chase Rate and middle-zone Groundball Rate
# improve year-to-year, and models the relationship between improvement levels
# and overall performance metrics (Barrel%, Hard-Hit%, wOBA).
#
# Configuration:
# - GB% threshold: 80th percentile or higher (middle-zone pitches)
# - Chase% threshold: 20th percentile or lower
# - Minimum sample: 50 pitches per player-season in middle zone
# - Weighting: Larger improvements weighted differently in binning analysis
# ==============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(stringr)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Thresholds
GB_PERCENTILE_THRESHOLD <- 0.80        # 80th percentile or higher
CHASE_PERCENTILE_THRESHOLD <- 0.20     # 20th percentile or lower
MIN_PITCHES_ZONE <- 50                 # Minimum pitches in middle zone per season

# Binning for improvements
IMPROVEMENT_BINS <- data.frame(
  bin_min = c(0, 5, 10, 25),
  bin_max = c(5, 10, 25, 100),
  bin_label = c("0-5%", "5-10%", "10-25%", "25%+")
)

# Data paths
WORKSPACE_ROOT <- here::here()
DATA_RAW <- file.path(WORKSPACE_ROOT, "data", "raw")
DATA_PROCESSED <- file.path(WORKSPACE_ROOT, "data", "processed")
REPORTS <- file.path(WORKSPACE_ROOT, "reports")

# Minor league evaluation (optional)
INCLUDE_MINOR_LEAGUE <- FALSE  # Set to TRUE to run separate minor league analysis
MINOR_LEAGUE_LEVEL <- NA       # e.g., "AAA", "AA", "A", or NA for all minor levels

# Create output directories if they don't exist
dir.create(DATA_PROCESSED, showWarnings = FALSE, recursive = TRUE)

df <- batter_perf %>%
    filter(handedness == "Overall", game_type == "R", level == "MLB")

# ==============================================================================
# THRESHOLD & COHORT IDENTIFICATION - LEFT OFF
# ==============================================================================

# identify_elevated_kpi_cohort <- function(metrics_df) {
  # Identify players in a season who meet BOTH criteria:
  # - GB% >= 80th percentile (middle zone)
  # - Chase% <= 20th percentile

  try <- df %>%
  filter(Location == "mid (h)", !is.na(`GB%`))
  
  # Calculate percentiles - NEED TO ADD IN SAMPLE THRESHOLDS
  gb_80th <- quantile(df$`GB%`[df$Location %in% c("mid (h)","mid (v)"),], GB_PERCENTILE_THRESHOLD, na.rm = TRUE)
  chase_20th <- quantile(metrics_df$chase_rate, CHASE_PERCENTILE_THRESHOLD, na.rm = TRUE)
  
  cat("\nThreshold Calculation:\n")
  cat(sprintf("  GB%% 80th percentile: %.1f%%\n", gb_80th))
  cat(sprintf("  Chase%% 20th percentile: %.1f%%\n", chase_20th))
  
  # Filter cohort
  cohort <- metrics_df %>%
    filter(gb_rate >= gb_80th, chase_rate <= chase_20th) %>%
    mutate(
      meets_gb_threshold = gb_rate >= gb_80th,
      meets_chase_threshold = chase_rate <= chase_20th
    )
  
  cat("\nCohort Identification:\n")
  cat(sprintf("  Total player-seasons in metrics: %d\n", nrow(metrics_df)))
  cat(sprintf("  Players meeting both thresholds: %d\n", nrow(cohort)))
  
  return(cohort)
# }

# ==============================================================================
# YEAR-TO-YEAR TRANSITIONS
# ==============================================================================

create_year_transitions <- function(cohort_df) {
  # For each player in cohort, match to following year(s) to create transitions
  
  transitions <- cohort_df %>%
    arrange(player, year) %>%
    group_by(player) %>%
    mutate(
      next_year_row = lead(1)
    ) %>%
    ungroup() %>%
    filter(!is.na(next_year_row)) %>%
    select(-next_year_row)
  
  # Join with next year data
  next_year_data <- cohort_df %>%
    select(player, year, contains("rate"), woba) %>%
    rename(
      current_year = year,
      current_chase_rate = chase_rate,
      current_gb_rate = gb_rate,
      current_barrel_rate = barrel_rate,
      current_hard_hit_rate = hard_hit_rate,
      current_woba = woba
    )
  
  transitions <- transitions %>%
    rename(
      prior_year = year,
      prior_chase_rate = chase_rate,
      prior_gb_rate = gb_rate,
      prior_barrel_rate = barrel_rate,
      prior_hard_hit_rate = hard_hit_rate,
      prior_woba = woba
    ) %>%
    mutate(current_year = prior_year + 1) %>%
    left_join(next_year_data, by = c("player", "current_year")) %>%
    filter(!is.na(current_chase_rate))  # Only keep if next year exists
  
  # Calculate improvements
  transitions <- transitions %>%
    mutate(
      gb_improvement_pct = if_else(
        prior_gb_rate > 0,
        ((prior_gb_rate - current_gb_rate) / prior_gb_rate) * 100,
        NA_real_
      ),
      chase_improvement_pct = if_else(
        prior_chase_rate > 0,
        ((prior_chase_rate - current_chase_rate) / prior_chase_rate) * 100,
        NA_real_
      ),
      barrel_change = current_barrel_rate - prior_barrel_rate,
      hard_hit_change = current_hard_hit_rate - prior_hard_hit_rate,
      woba_change = current_woba - prior_woba
    ) %>%
    select(
      player, prior_year, current_year,
      prior_chase_rate, prior_gb_rate, prior_barrel_rate, prior_hard_hit_rate, prior_woba,
      current_chase_rate, current_gb_rate, current_barrel_rate, current_hard_hit_rate, current_woba,
      gb_improvement_pct, chase_improvement_pct, barrel_change, hard_hit_change, woba_change
    )
  
  return(transitions)
}

# ==============================================================================
# EMPIRICAL BINNING ANALYSIS
# ==============================================================================

bin_by_improvement <- function(transitions_df, improvement_col = "gb_improvement_pct",
                               weight_by_magnitude = TRUE) {
  # Group transitions by improvement level and calculate mean/median performance metrics
  
  df <- transitions_df %>%
    filter(!is.na(!!sym(improvement_col)))
  
  binned_results <- list()
  
  for (i in seq_len(nrow(IMPROVEMENT_BINS))) {
    bin_min <- IMPROVEMENT_BINS$bin_min[i]
    bin_max <- IMPROVEMENT_BINS$bin_max[i]
    bin_label <- IMPROVEMENT_BINS$bin_label[i]
    
    bin_data <- df %>%
      filter(!!sym(improvement_col) >= bin_min & !!sym(improvement_col) < bin_max)
    
    if (nrow(bin_data) == 0) {
      next
    }
    
    if (weight_by_magnitude) {
      # Weight by the size of improvement
      weights <- bin_data[[improvement_col]]
      weights <- weights / sum(weights)  # Normalize
    } else {
      weights <- rep(1 / nrow(bin_data), nrow(bin_data))
    }
    
    result <- list(
      n_transitions = nrow(bin_data),
      improvement_range = sprintf("%d-%d%%", bin_min, bin_max),
      mean_barrel_change = sum(bin_data$barrel_change * weights, na.rm = TRUE),
      median_barrel_change = median(bin_data$barrel_change, na.rm = TRUE),
      mean_hard_hit_change = sum(bin_data$hard_hit_change * weights, na.rm = TRUE),
      median_hard_hit_change = median(bin_data$hard_hit_change, na.rm = TRUE),
      mean_woba_change = sum(bin_data$woba_change * weights, na.rm = TRUE),
      median_woba_change = median(bin_data$woba_change, na.rm = TRUE)
    )
    
    binned_results[[bin_label]] <- result
  }
  
  return(binned_results)
}

# ==============================================================================
# REGRESSION MODELING
# ==============================================================================

fit_regression_models <- function(transitions_df) {
  # Fit OLS models predicting performance metrics from KPI improvements
  
  df <- transitions_df %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct),
           !is.na(barrel_change), !is.na(hard_hit_change), !is.na(woba_change))
  
  if (nrow(df) < 5) {
    return(list(error = "Insufficient data for regression"))
  }
  
  models <- list()
  
  # Model 1: Barrel Rate
  model_barrel <- lm(barrel_change ~ gb_improvement_pct + chase_improvement_pct, data = df)
  models$barrel_rate <- list(
    gb_improvement_coef = coef(model_barrel)["gb_improvement_pct"],
    chase_improvement_coef = coef(model_barrel)["chase_improvement_pct"],
    intercept = coef(model_barrel)["(Intercept)"],
    r2_score = summary(model_barrel)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in barrel_rate",
      coef(model_barrel)["gb_improvement_pct"]
    )
  )
  
  # Model 2: Hard-Hit Rate
  model_hard_hit <- lm(hard_hit_change ~ gb_improvement_pct + chase_improvement_pct, data = df)
  models$hard_hit_rate <- list(
    gb_improvement_coef = coef(model_hard_hit)["gb_improvement_pct"],
    chase_improvement_coef = coef(model_hard_hit)["chase_improvement_pct"],
    intercept = coef(model_hard_hit)["(Intercept)"],
    r2_score = summary(model_hard_hit)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in hard_hit_rate",
      coef(model_hard_hit)["gb_improvement_pct"]
    )
  )
  
  # Model 3: wOBA
  model_woba <- lm(woba_change ~ gb_improvement_pct + chase_improvement_pct, data = df)
  models$woba <- list(
    gb_improvement_coef = coef(model_woba)["gb_improvement_pct"],
    chase_improvement_coef = coef(model_woba)["chase_improvement_pct"],
    intercept = coef(model_woba)["(Intercept)"],
    r2_score = summary(model_woba)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in woba",
      coef(model_woba)["gb_improvement_pct"]
    )
  )
  
  return(models)
}

# ==============================================================================
# CORRELATION & TRADEOFF ANALYSIS
# ==============================================================================

analyze_gb_impact_tradeoff <- function(transitions_df) {
  # For players who improved GB%, test if impact quality changed unexpectedly
  
  df <- transitions_df %>%
    filter(gb_improvement_pct > 0,  # GB% actually improved (reduced)
           !is.na(barrel_change),
           !is.na(hard_hit_change),
           !is.na(woba_change))
  
  if (nrow(df) < 3) {
    return(list(error = "Insufficient data for correlation analysis"))
  }
  
  # Calculate correlations and p-values
  corr_barrel <- cor(df$gb_improvement_pct, df$barrel_change, use = "complete.obs")
  corr_hard_hit <- cor(df$gb_improvement_pct, df$hard_hit_change, use = "complete.obs")
  corr_woba <- cor(df$gb_improvement_pct, df$woba_change, use = "complete.obs")
  
  # P-values
  test_barrel <- cor.test(df$gb_improvement_pct, df$barrel_change)
  test_hard_hit <- cor.test(df$gb_improvement_pct, df$hard_hit_change)
  test_woba <- cor.test(df$gb_improvement_pct, df$woba_change)
  
  result <- list(
    n_players_with_gb_improvement = nrow(df),
    correlations = list(
      gb_improvement_vs_barrel_change = list(
        r = corr_barrel,
        p_value = test_barrel$p.value
      ),
      gb_improvement_vs_hard_hit_change = list(
        r = corr_hard_hit,
        p_value = test_hard_hit$p.value
      ),
      gb_improvement_vs_woba_change = list(
        r = corr_woba,
        p_value = test_woba$p.value
      )
    ),
    interpretation = list(
      barrel = if (corr_barrel > 0) "positive" else if (corr_barrel < 0) "negative" else "none",
      hard_hit = if (corr_hard_hit > 0) "positive" else if (corr_hard_hit < 0) "negative" else "none",
      woba = if (corr_woba > 0) "positive" else if (corr_woba < 0) "negative" else "none"
    )
  )
  
  return(result)
}

# ==============================================================================
# EXEMPLAR IDENTIFICATION
# ==============================================================================

identify_exemplars <- function(transitions_df, n_exemplars = 3) {
  # Identify 2-3 key player transitions representing different patterns
  
  df <- transitions_df %>%
    mutate(impact_quality_score = (barrel_change + hard_hit_change) / 2,
           overall_improvement = gb_improvement_pct + chase_improvement_pct)
  
  exemplars <- list()
  
  # Pattern 1: GB% improved + impact quality improved
  pattern1 <- df %>%
    filter(gb_improvement_pct > 0, impact_quality_score > 0) %>%
    arrange(desc(gb_improvement_pct)) %>%
    slice(1)
  
  if (nrow(pattern1) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "Improved GB% with improved impact quality",
      data = as.list(pattern1)
    )
  }
  
  # Pattern 2: GB% improved but impact quality degraded
  pattern2 <- df %>%
    filter(gb_improvement_pct > 0, impact_quality_score < 0) %>%
    arrange(desc(gb_improvement_pct)) %>%
    slice(1)
  
  if (nrow(pattern2) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "Improved GB% but degraded impact quality",
      data = as.list(pattern2)
    )
  }
  
  # Pattern 3: Largest overall improvement
  pattern3 <- df %>%
    arrange(desc(overall_improvement)) %>%
    slice(1)
  
  if (nrow(pattern3) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "Largest overall KPI improvement",
      data = as.list(pattern3)
    )
  }
  
  return(exemplars)
}

# ==============================================================================
# REPORTING
# ==============================================================================

generate_report <- function(metrics_df, cohort_df, transitions_df, analysis_results) {
  # Generate markdown report with all analysis results
  
  report <- character()
  
  report <- c(report, "# Year-to-Year KPI Improvement Analysis Report")
  report <- c(report, sprintf("\n**Generated:** %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
  
  # Configuration
  report <- c(report, "## Configuration")
  report <- c(report, sprintf("- **GB%% Threshold:** %dth percentile or higher", GB_PERCENTILE_THRESHOLD * 100))
  report <- c(report, sprintf("- **Chase%% Threshold:** %dth percentile or lower", CHASE_PERCENTILE_THRESHOLD * 100))
  report <- c(report, sprintf("- **Minimum Sample:** %d pitches in middle zone per season", MIN_PITCHES_ZONE))
  report <- c(report, "- **Improvement Weighting:** Enabled\n")
  
  # Data summary
  report <- c(report, "## Dataset Overview")
  report <- c(report, sprintf("- **Total Player-Seasons:** %d", nrow(metrics_df)))
  report <- c(report, sprintf("- **Cohort Size (both KPIs elevated):** %d", nrow(cohort_df)))
  report <- c(report, sprintf("- **Year-to-Year Transitions:** %d\n", nrow(transitions_df)))
  
  # Cohort characteristics
  if (nrow(cohort_df) > 0) {
    report <- c(report, "## Cohort Characteristics")
    report <- c(report, sprintf("- **Mean Chase Rate:** %.1f%%", mean(cohort_df$chase_rate, na.rm = TRUE)))
    report <- c(report, sprintf("- **Mean GB Rate:** %.1f%%", mean(cohort_df$gb_rate, na.rm = TRUE)))
    report <- c(report, sprintf("- **Mean Barrel Rate:** %.1f%%", mean(cohort_df$barrel_rate, na.rm = TRUE)))
    report <- c(report, sprintf("- **Mean Hard-Hit Rate:** %.1f%%\n", mean(cohort_df$hard_hit_rate, na.rm = TRUE)))
  }
  
  # Empirical binning results
  if (!is.null(analysis_results$binning_gb)) {
    report <- c(report, "## Empirical Binning: GB% Improvement Impact")
    report <- c(report, "*Transitions grouped by GB% improvement, with weighted aggregation by improvement magnitude*\n")
    report <- c(report, "| Improvement | N | Avg Barrel Δ | Avg Hard-Hit Δ | Avg wOBA Δ |")
    report <- c(report, "|---|---|---|---|---|")
    
    for (bin_label in names(analysis_results$binning_gb)) {
      results <- analysis_results$binning_gb[[bin_label]]
      report <- c(report, sprintf(
        "| %s | %d | %+.2f | %+.2f | %+.2f |",
        bin_label,
        results$n_transitions,
        results$mean_barrel_change,
        results$mean_hard_hit_change,
        results$mean_woba_change
      ))
    }
    report <- c(report, "")
  }
  
  # Regression results
  if (!is.null(analysis_results$regression) && !"error" %in% names(analysis_results$regression)) {
    report <- c(report, "## Regression Models")
    report <- c(report, "*Predicting performance metric changes from KPI improvements*\n")
    
    for (metric in names(analysis_results$regression)) {
      model_results <- analysis_results$regression[[metric]]
      report <- c(report, sprintf("### %s", toupper(metric)))
      report <- c(report, sprintf("- **R² Score:** %.3f", model_results$r2_score))
      report <- c(report, sprintf("- **GB%% Improvement Coef:** %+.4f", model_results$gb_improvement_coef))
      report <- c(report, sprintf("- **Chase%% Improvement Coef:** %+.4f", model_results$chase_improvement_coef))
      report <- c(report, sprintf("- **Interpretation:** %s\n", model_results$interpretation))
    }
  }
  
  # Correlation analysis
  if (!is.null(analysis_results$tradeoff_analysis) && !"error" %in% names(analysis_results$tradeoff_analysis)) {
    tradeoff <- analysis_results$tradeoff_analysis
    report <- c(report, "## GB% Improvement ↔ Impact Quality Tradeoff Analysis")
    report <- c(report, sprintf("*N = %d players with GB%% improvement*\n", tradeoff$n_players_with_gb_improvement))
    report <- c(report, "| Metric | Correlation | P-Value | Direction |")
    report <- c(report, "|---|---|---|---|")
    
    for (metric_name in names(tradeoff$correlations)) {
      corr_data <- tradeoff$correlations[[metric_name]]
      metric_label <- gsub("gb_improvement_vs_", "", metric_name)
      metric_label <- gsub("_change", "", metric_label)
      direction_key <- gsub("_.*", "", metric_label)
      direction <- tradeoff$interpretation[[direction_key]]
      
      report <- c(report, sprintf(
        "| %s | %.3f | %.4f | %s |",
        metric_label,
        corr_data$r,
        corr_data$p_value,
        direction
      ))
    }
    report <- c(report, "")
  }
  
  # Exemplars
  if (!is.null(analysis_results$exemplars)) {
    report <- c(report, "## Key Player-Season Exemplars\n")
    for (i in seq_along(analysis_results$exemplars)) {
      exemplar <- analysis_results$exemplars[[i]]
      data <- exemplar$data
      report <- c(report, sprintf("### Pattern %d: %s", i, exemplar$pattern))
      report <- c(report, sprintf("- **Player:** %s", data$player[1]))
      report <- c(report, sprintf("- **Transition:** %d → %d", data$prior_year[1], data$current_year[1]))
      report <- c(report, sprintf("- **GB%% Change:** %+.1f%%", data$gb_improvement_pct[1]))
      report <- c(report, sprintf("- **Chase%% Change:** %+.1f%%", data$chase_improvement_pct[1]))
      report <- c(report, sprintf("- **Barrel Δ:** %+.2f pts", data$barrel_change[1]))
      report <- c(report, sprintf("- **Hard-Hit Δ:** %+.2f pts", data$hard_hit_change[1]))
      report <- c(report, sprintf("- **wOBA Δ:** %+.3f\n", data$woba_change[1]))
    }
  }
  
  return(paste(report, collapse = "\n"))
}

# ==============================================================================
# MAIN PIPELINE
# ==============================================================================

main <- function() {
  cat("================================================================================\n")
  cat("Year-to-Year KPI Improvement & Performance Analysis\n")
  cat("================================================================================\n\n")
  
  # Step 1: Load data
  cat("[1/8] Loading Statcast data...\n")
  tryCatch({
    raw_data <- load_statcast_data()
    raw_data <- parse_game_date(raw_data)
    cat(sprintf("Total records: %d\n", nrow(raw_data)))
  }, error = function(e) {
    stop(sprintf("ERROR loading data: %s", e$message))
  })
  
  # Step 1b: Optional filter by league level (for minor league comparison)
  if (INCLUDE_MINOR_LEAGUE && !is.na(MINOR_LEAGUE_LEVEL)) {
    cat("\n[1b/8] Filtering to league level...\n")
    raw_data <- filter_by_level(raw_data, league = MINOR_LEAGUE_LEVEL)
    cat(sprintf("Records after level filter: %d\n", nrow(raw_data)))
    cat(sprintf("Analysis level: %s\n", MINOR_LEAGUE_LEVEL))
  } else if (!INCLUDE_MINOR_LEAGUE) {
    cat("\n[Note] Minor league analysis disabled. Set INCLUDE_MINOR_LEAGUE=TRUE to compare levels.\n")
  }
  
  # Step 2: Filter to middle zone
  cat("\n[2/8] Filtering to middle zone pitches...\n")
  middle_zone_data <- filter_to_middle_zone(raw_data)
  
  # Step 3: Aggregate metrics by player-season
  cat("\n[3/8] Aggregating player-season metrics...\n")
  metrics_df <- aggregate_player_season_metrics(middle_zone_data, player_col = "batter")
  cat(sprintf("Player-seasons with sufficient sample: %d\n", nrow(metrics_df)))
  
  if (nrow(metrics_df) == 0) {
    stop("ERROR: No valid player-seasons found")
  }
  
  # Step 4: Identify elevated KPI cohort
  cat("\n[4/8] Identifying elevated KPI cohort...\n")
  cohort_df <- identify_elevated_kpi_cohort(metrics_df)
  
  if (nrow(cohort_df) == 0) {
    stop("ERROR: No players found meeting both KPI thresholds")
  }
  
  # Step 5: Create year-to-year transitions
  cat("\n[5/8] Creating year-to-year transitions...\n")
  transitions_df <- create_year_transitions(cohort_df)
  cat(sprintf("Valid transitions: %d\n", nrow(transitions_df)))
  
  if (nrow(transitions_df) == 0) {
    stop("ERROR: No year-to-year transitions found")
  }
  
  # Step 6: Run analysis
  cat("\n[6/8] Running analysis...\n")
  analysis_results <- list()
  
  # Binning
  analysis_results$binning_gb <- bin_by_improvement(transitions_df, improvement_col = "gb_improvement_pct")
  cat(sprintf("  ✓ Empirical binning complete (%d bins)\n", length(analysis_results$binning_gb)))
  
  # Regression
  analysis_results$regression <- fit_regression_models(transitions_df)
  cat("  ✓ Regression models fit\n")
  
  # Correlation/tradeoff
  analysis_results$tradeoff_analysis <- analyze_gb_impact_tradeoff(transitions_df)
  cat("  ✓ Tradeoff analysis complete\n")
  
  # Exemplars
  analysis_results$exemplars <- identify_exemplars(transitions_df)
  cat(sprintf("  ✓ Identified %d exemplars\n", length(analysis_results$exemplars)))
  
  # Step 7: Generate report
  cat("\n[7/8] Generating report...\n")
  report <- generate_report(metrics_df, cohort_df, transitions_df, analysis_results)
  
  # Save outputs
  level_suffix <- if (!is.na(MINOR_LEAGUE_LEVEL)) sprintf("_%s", MINOR_LEAGUE_LEVEL) else ""
  report_path <- file.path(DATA_PROCESSED, sprintf("kpi_analysis_report%s.md", level_suffix))
  writeLines(report, report_path)
  cat(sprintf("  ✓ Report saved: %s\n", report_path))
  
  # Save intermediate data
  write_csv(metrics_df, file.path(DATA_PROCESSED, sprintf("metrics_by_player_season%s.csv", level_suffix)))
  write_csv(cohort_df, file.path(DATA_PROCESSED, sprintf("elevated_kpi_cohort%s.csv", level_suffix)))
  write_csv(transitions_df, file.path(DATA_PROCESSED, sprintf("year_transitions%s.csv", level_suffix)))
  cat(sprintf("  ✓ Data files saved to %s\n", DATA_PROCESSED))
  
  # Step 8: Minor league comparison guidance
  cat("\n[8/8] Minor league analysis guidance...\n")
  if (!INCLUDE_MINOR_LEAGUE) {
    cat("  ℹ To run minor league analysis:\n")
    cat("    1. Set INCLUDE_MINOR_LEAGUE <- TRUE at top of script\n")
    cat("    2. Set MINOR_LEAGUE_LEVEL <- \"AAA\" (or \"AA\", \"A\")\n")
    cat("    3. Re-run script to generate separate analysis\n")
    cat("    4. Compare results between levels to validate findings\n")
  } else {
    cat(sprintf("  ✓ Minor league analysis complete for level: %s\n", MINOR_LEAGUE_LEVEL))
  }
  
  # Summary
  cat("\n================================================================================\n")
  cat("ANALYSIS COMPLETE\n")
  cat("================================================================================\n\n")
  cat("Key Findings:\n")
  cat(sprintf("  • Cohort: %d player-seasons with elevated GB%% and low Chase%%\n", nrow(cohort_df)))
  cat(sprintf("  • Transitions: %d year-to-year improvements to analyze\n", nrow(transitions_df)))
  cat(sprintf("  • Exemplars: %d patterns identified\n\n", length(analysis_results$exemplars)))
  cat("Next Steps:\n")
  cat(sprintf("  1. Review %s\n", report_path))
  cat(sprintf("  2. Analyze %s for detailed transitions\n", file.path(DATA_PROCESSED, "year_transitions.csv")))
  cat("  3. Refine thresholds based on cohort size and findings\n")
}

# Run the analysis
if (!interactive()) {
  main()
}
