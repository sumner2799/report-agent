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
library(ggplot2)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Thresholds
GB_PERCENTILE_THRESHOLD <- 0.80        # 80th percentile or higher
CHASE_PERCENTILE_THRESHOLD <- 0.80     # 20th percentile or lower
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
# THRESHOLD & COHORT IDENTIFICATION
# ==============================================================================

# identify_elevated_kpi_cohort <- function(metrics_df) {
  # Identify players in a season who meet BOTH criteria:
  # - GB% >= 80th percentile (middle zone)
  # - Chase% <= 20th percentile

  try <- df %>%
  filter(season == "2024", last_first_name == "Diaz, Yainer", Location == "overall", breakdown == "total")
  # filter(Location %in% c("mid (h)","mid (v)"), BIP >= 60)

  ta <- df %>%
  filter(last_first_name == "Anderson, Tim",season == "2023", Location %in% c("overall","mid (h)","mid (v)"))

  gimmy <- df %>%
    filter(last_first_name == "Giménez, Andrés", season %in% c("2024","2025"),Location == "mid (h)")
  
  # Calculate percentiles - NEED TO ADD IN SAMPLE THRESHOLDS
  gb_80th <- quantile(df$`GB%`[df$Location %in% c("mid (h)","mid (v)") & df$BIP >= 60], GB_PERCENTILE_THRESHOLD, na.rm = TRUE)
  chase_20th <- quantile(df$`Chase%`[df$breakdown == "total" & df$Location == "overall"], CHASE_PERCENTILE_THRESHOLD, na.rm = TRUE)
  
  cat("\nThreshold Calculation:\n")
  cat(sprintf("  GB%% 80th percentile: %.1f%%\n", gb_80th))
  cat(sprintf("  Chase%% 20th percentile: %.1f%%\n", chase_20th))
  
  # Filter cohort
  cohort <- df %>%
    filter(((`GB%` >= gb_80th & Location %in% c("mid (h)","mid (v)")) | (`Chase%` >= chase_20th & Location == "overall")),BIP >= 60) %>%
    mutate(
      meets_gb_threshold = `GB%` >= gb_80th,
      meets_chase_threshold = `Chase%` >= chase_20th
    )

    cohort2 <- cohort %>%
    group_by(last_first_name,season,breakdown) %>%
    summarise(tot = n()) %>%
    mutate(count_break = 1) %>%
    group_by(last_first_name,season) %>%
    summarise(both_criteria = n()) %>%
    filter(both_criteria > 1)


    cohort_df <- inner_join(cohort,cohort2,by=c("last_first_name","season"))

  
  # cat("\nCohort Identification:\n")
  # cat(sprintf("  Total player-seasons in metrics: %d\n", nrow(metrics_df)))
  # cat(sprintf("  Players meeting both thresholds: %d\n", nrow(cohort2)))
  
  return(cohort)
# }

# altuve <- df %>%
#   filter(last_first_name == "Altuve, Jose", season == "2025")

# test_year <- df %>%
#   filter(Location %in% c("mid (h)","mid (v)"), BIP >= 60, season == "2025") %>%
#   group_by(last_first_name, season) %>%
#   summarise(tot = n())

# ==============================================================================
# YEAR-TO-YEAR TRANSITIONS
# ==============================================================================

# create_year_transitions <- function(cohort_df) {
  # For each player in cohort, match to following year(s) to create transitions

  y2y_data <- df %>% 
    filter(Location %in% c("mid (v)","mid (h)","overall"), BIP >= 60)
  
  transitions <- y2y_data %>%
    arrange(last_first_name, season, Location) %>%
    group_by(last_first_name, Location) %>%
    mutate(
      next_year_row = lead(season, n = 1)
    ) %>%
    ungroup() %>%
    filter(!is.na(next_year_row)) %>%
    select(-next_year_row)

  
  # Join with next year data
  next_year_data <- y2y_data %>%
    select(last_first_name, season, Location, `Chase%`, `GB%`, `Whiff%`,`HH%`,`Sweet Spot%`, SLGcon) %>%
    rename(
      current_year = season,
      current_chase_rate = `Chase%`,
      current_gb_rate = `GB%`,
      current_whiff_rate = `Whiff%`,
      current_hard_hit_rate = `HH%`,
      current_sweet_spot_rate = `Sweet Spot%`,
      current_SLG = SLGcon
    )
  
  transitions <- transitions %>%
    rename(
      prior_year = season,
      prior_chase_rate = `Chase%`,
      prior_gb_rate = `GB%`,
      prior_whiff_rate = `Whiff%`,
      prior_hard_hit_rate = `HH%`,
      prior_sweet_spot_rate = `Sweet Spot%`,
      prior_SLG = SLGcon
    ) %>%
    mutate(current_year = prior_year + 1) %>%
    left_join(next_year_data, by = c("last_first_name", "current_year", "Location")) %>%
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
      gb_change = current_gb_rate - prior_gb_rate,
      chase_change = current_chase_rate - prior_chase_rate,
      whiff_change = current_whiff_rate - prior_whiff_rate,
      hard_hit_change = current_hard_hit_rate - prior_hard_hit_rate,
      slg_change = current_SLG - prior_SLG,
      sweet_spot_change = current_sweet_spot_rate - prior_sweet_spot_rate
    ) %>%
    select(
      last_first_name, prior_year, current_year, Location, BIP, 
      prior_chase_rate, prior_gb_rate, prior_whiff_rate, prior_hard_hit_rate, prior_SLG, prior_sweet_spot_rate,
      current_chase_rate, current_gb_rate, current_whiff_rate, current_hard_hit_rate, current_SLG, current_sweet_spot_rate,
      gb_change, gb_improvement_pct, chase_change, chase_improvement_pct, whiff_change, hard_hit_change, slg_change, sweet_spot_change
    )

    transitions_df <- transitions

    # ts <- transitions_df %>%
    #   filter(((current_gb_rate < gb_80th) & Location %in% c("mid (h)","mid (v)")) | 
    #   ((current_chase_rate < chase_20th)& Location =="overall"))


  
#   return(transitions)
# }

# ==============================================================================
# EMPIRICAL BINNING ANALYSIS
# ==============================================================================

# bin_by_improvement <- function(transitions_df, improvement_col = "gb_improvement_pct",
#                                weight_by_magnitude = TRUE) {
  # Group transitions by improvement level and calculate mean/median performance metrics

  binning_df <- inner_join(transitions_df,cohort2,by=c("last_first_name","prior_year"="season"))

  
  binning_df2 <- binning_df %>%
    filter(
      !is.na(!!sym(improvement_col)),
      # Location %in% c("mid (h)", "mid (v)")
      Location == "overall"
    )
  
  binned_results_chase <- list()
  
  for (i in seq_len(nrow(IMPROVEMENT_BINS))) {
    bin_min <- IMPROVEMENT_BINS$bin_min[i]
    bin_max <- IMPROVEMENT_BINS$bin_max[i]
    bin_label <- IMPROVEMENT_BINS$bin_label[i]
    
    bin_data <- binning_df2 %>%
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
      mean_whiff_change = sum(bin_data$whiff_change * weights, na.rm = TRUE),
      median_whiff_change = median(bin_data$whiff_change, na.rm = TRUE),
      mean_hard_hit_change = sum(bin_data$hard_hit_change * weights, na.rm = TRUE),
      median_hard_hit_change = median(bin_data$hard_hit_change, na.rm = TRUE),
      mean_slg_change = sum(bin_data$slg_change * weights, na.rm = TRUE),
      median_slg_change = median(bin_data$slg_change, na.rm = TRUE),
      mean_sweet_spot_change = sum(bin_data$sweet_spot_change * weights, na.rm = TRUE),
      median_sweet_spot_change = median(bin_data$sweet_spot_change, na.rm = TRUE)
    )
    
    binned_results_chase[[bin_label]] <- result
  }
  
  # return(binned_results)
# }

# ==============================================================================
# REGRESSION MODELING
# ==============================================================================

## 3 buckets of models:
# 1. impact of KPIs on pitches in the middle of zone from improvied GB%
# 2. Impact of kPIs from an overall improved Chase%
# 3. Specific impacts from combo of improved GB% (middle) + Chase% (overall)
# - All KPIs from middle pitches
# - Overall Slug

# fit_regression_models <- function(transitions_df) {
  # Fit OLS models predicting performance metrics from KPI improvements
  
  df <- transitions_df %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct),
           !is.na(whiff_change), !is.na(hard_hit_change), !is.na(slg_change),
           !is.na(sweet_spot_change), !is.na(gb_change), !is.na(chase_change),
           , Location %in% c("mid (h)", "mid (v)")
          #  , Location == "overall"
           )

  df_chase <- transitions_df %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct),
           !is.na(whiff_change), !is.na(hard_hit_change), !is.na(slg_change),
           !is.na(sweet_spot_change), !is.na(gb_change), !is.na(chase_change),
          #  , Location %in% c("mid (h)", "mid (v)")
           , Location == "overall"
           )
  
  if (nrow(df) < 5) {
    return(list(error = "Insufficient data for regression"))
  }
  
  models_gb <- list()
  
  # Model 1: whiff Rate - GB
  models_gb_whiff <- lm(whiff_change ~ gb_improvement_pct, data = df)
  models_gb$whiff_rate <- list(
    gb_improvement_coef = coef(models_gb_whiff)["gb_improvement_pct"],
    # chase_improvement_coef = coef(models_gb_whiff)["chase_improvement_pct"],
    intercept = coef(models_gb_whiff)["(Intercept)"],
    r2_score = summary(models_gb_whiff)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in whiff_rate",
      coef(models_gb_whiff)["gb_improvement_pct"]
    )
  )
  
  # Model 2: Hard-Hit Rate - GB
  models_gb_hard_hit <- lm(hard_hit_change ~ gb_improvement_pct, data = df)
  models_gb$hard_hit_rate <- list(
    gb_improvement_coef = coef(models_gb_hard_hit)["gb_improvement_pct"],
    # chase_improvement_coef = coef(models_gb_hard_hit)["chase_improvement_pct"],
    intercept = coef(models_gb_hard_hit)["(Intercept)"],
    r2_score = summary(models_gb_hard_hit)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in hard_hit_rate",
      coef(models_gb_hard_hit)["gb_improvement_pct"]
    )
  )
  
  # Model 3: slg - GB
  models_gb_slg <- lm(slg_change ~ gb_improvement_pct, data = df)
  models_gb$slg <- list(
    gb_improvement_coef = coef(models_gb_slg)["gb_improvement_pct"],
    # chase_improvement_coef = coef(models_gb_slg)["chase_improvement_pct"],
    intercept = coef(models_gb_slg)["(Intercept)"],
    r2_score = summary(models_gb_slg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in slg",
      coef(models_gb_slg)["gb_improvement_pct"]
    )
  )

    # Model 4: Sweet-Spot% - GB
  models_gb_sweet_spot <- lm(sweet_spot_change ~ gb_improvement_pct, data = df)
  models_gb$sweet_spot <- list(
    gb_improvement_coef = coef(models_gb_sweet_spot)["gb_improvement_pct"],
    # chase_improvement_coef = coef(models_gb_sweet_spot)["chase_improvement_pct"],
    intercept = coef(models_gb_sweet_spot)["(Intercept)"],
    r2_score = summary(models_gb_sweet_spot)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in sweet_spot",
      coef(models_gb_sweet_spot)["gb_improvement_pct"]
    )
  )

models_gb_reg <- list()
  
  # Model 1: whiff Rate - GB
  models_gb_whiff_reg <- lm(whiff_change ~ gb_change, data = df)
  models_gb_reg$whiff_rate <- list(
    gb_improvement_coef = coef(models_gb_whiff_reg)["gb_change"],
    # chase_improvement_coef = coef(models_gb_whiff_reg)["chase_improvement_pct"],
    intercept = coef(models_gb_whiff_reg)["(Intercept)"],
    r2_score = summary(models_gb_whiff_reg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in whiff_rate",
      coef(models_gb_whiff_reg)["gb_change"]
    )
  )
  
  # Model 2: Hard-Hit Rate - GB
  models_gb_hard_hit_reg <- lm(hard_hit_change ~ gb_change, data = df)
  models_gb_reg$hard_hit_rate <- list(
    gb_improvement_coef = coef(models_gb_hard_hit_reg)["gb_change"],
    # chase_improvement_coef = coef(models_gb_hard_hit_reg)["chase_improvement_pct"],
    intercept = coef(models_gb_hard_hit_reg)["(Intercept)"],
    r2_score = summary(models_gb_hard_hit_reg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in hard_hit_rate",
      coef(models_gb_hard_hit_reg)["gb_change"]
    )
  )
  
  # Model 3: slg - GB
  models_gb_slg_reg <- lm(slg_change ~ gb_change, data = df)
  models_gb_reg$slg <- list(
    gb_improvement_coef = coef(models_gb_slg_reg)["gb_change"],
    # chase_improvement_coef = coef(models_gb_slg_reg)["chase_improvement_pct"],
    intercept = coef(models_gb_slg_reg)["(Intercept)"],
    r2_score = summary(models_gb_slg_reg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in slg",
      coef(models_gb_slg_reg)["gb_change"]
    )
  )

    # Model 4: Sweet-Spot% - GB
  models_gb_sweet_spot_reg <- lm(sweet_spot_change ~ gb_change, data = df)
  models_gb_reg$sweet_spot <- list(
    gb_improvement_coef = coef(models_gb_sweet_spot_reg)["gb_change"],
    # chase_improvement_coef = coef(models_gb_sweet_spot_reg)["chase_improvement_pct"],
    intercept = coef(models_gb_sweet_spot_reg)["(Intercept)"],
    r2_score = summary(models_gb_sweet_spot_reg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in sweet_spot",
      coef(models_gb_sweet_spot_reg)["gb_change"]
    )
  )

models_chase <- list()
  
  # Model 1: whiff Rate - GB
  models_chase_whiff <- lm(whiff_change ~ chase_improvement_pct, data = df_chase)
  models_chase$whiff_rate <- list(
    # gb_improvement_coef = coef(models_chase_whiff)["gb_improvement_pct"],
    chase_improvement_coef = coef(models_chase_whiff)["chase_improvement_pct"],
    intercept = coef(models_chase_whiff)["(Intercept)"],
    r2_score = summary(models_chase_whiff)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in whiff_rate",
      coef(models_chase_whiff)["gb_improvement_pct"]
    )
  )
  
  # Model 2: Hard-Hit Rate - GB
  models_chase_hard_hit <- lm(hard_hit_change ~ chase_improvement_pct, data = df_chase)
  models_chase$hard_hit_rate <- list(
    # gb_improvement_coef = coef(models_chase_hard_hit)["gb_improvement_pct"],
    chase_improvement_coef = coef(models_chase_hard_hit)["chase_improvement_pct"],
    intercept = coef(models_chase_hard_hit)["(Intercept)"],
    r2_score = summary(models_chase_hard_hit)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in hard_hit_rate",
      coef(models_chase_hard_hit)["gb_improvement_pct"]
    )
  )
  
  # Model 3: slg - GB
  models_chase_slg <- lm(slg_change ~ chase_improvement_pct, data = df_chase)
  models_chase$slg <- list(
    # gb_improvement_coef = coef(models_chase_slg)["gb_improvement_pct"],
    chase_improvement_coef = coef(models_chase_slg)["chase_improvement_pct"],
    intercept = coef(models_chase_slg)["(Intercept)"],
    r2_score = summary(models_chase_slg)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in slg",
      coef(models_chase_slg)["gb_improvement_pct"]
    )
  )

    # Model 4: Sweet-Spot% - GB
  models_chase_sweet_spot <- lm(sweet_spot_change ~ chase_improvement_pct, data = df_chase)
  models_chase$sweet_spot <- list(
    # gb_improvement_coef = coef(models_chase_sweet_spot)["gb_improvement_pct"],
    chase_improvement_coef = coef(models_chase_sweet_spot)["chase_improvement_pct"],
    intercept = coef(models_chase_sweet_spot)["(Intercept)"],
    r2_score = summary(models_chase_sweet_spot)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "1%% improvement in GB%% → %.3f point change in sweet_spot",
      coef(models_chase_sweet_spot)["gb_improvement_pct"]
    )
  )

  df_combo <- transitions_df %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct),
           !is.na(whiff_change), !is.na(hard_hit_change), !is.na(slg_change),
           !is.na(sweet_spot_change)
          #  , Location %in% c("mid (h)", "mid (v)")
          #  , Location == "overall"
           ) %>%
    group_by(last_first_name,prior_year,current_year) %>%
    summarise(
      gb_improvement = gb_improvement_pct[Location == "mid (v)"],
      chase_improvement = chase_improvement_pct[Location == "overall"],
      ovr_slg_change = slg_change[Location == "overall"],
      mid_slg_change = slg_change[Location == "mid (v)"],
      mid_whiff_change = whiff_change[Location == "mid (v)"],
      mid_hh_change = hard_hit_change[Location == "mid (v)"],
      mid_swspot_change = sweet_spot_change[Location == "mid (v)"]
    )

    models_combo <- list()
  
  # Model 1: whiff Rate - Combo
  models_combo_whiff <- lm(mid_whiff_change ~ gb_improvement + chase_improvement, data = df_combo)
  models_combo$whiff_rate <- list(
    gb_improvement_coef = coef(models_combo_whiff)["gb_improvement"],
    chase_improvement_coef = coef(models_combo_whiff)["chase_improvement"],
    intercept = coef(models_combo_whiff)["(Intercept)"],
    r2_score = summary(models_combo_whiff)$r.squared,
    n_observations = nrow(df_combo),
    interpretation = sprintf(
      "GB%%: 1%% improvement → %.3f pt change | Chase%%: 1%% improvement → %.3f pt change",
      coef(models_combo_whiff)["gb_improvement"],
      coef(models_combo_whiff)["chase_improvement"]
    )
  )
  
  # Model 2: Hard-Hit Rate - Combo
  models_combo_hard_hit <- lm(mid_hh_change ~ gb_improvement + chase_improvement, data = df_combo)
  models_combo$hard_hit_rate <- list(
    gb_improvement_coef = coef(models_combo_hard_hit)["gb_improvement"],
    chase_improvement_coef = coef(models_combo_hard_hit)["chase_improvement"],
    intercept = coef(models_combo_hard_hit)["(Intercept)"],
    r2_score = summary(models_combo_hard_hit)$r.squared,
    n_observations = nrow(df),
    interpretation = sprintf(
      "GB%%: 1%% improvement → %.3f pt change | Chase%%: 1%% improvement → %.3f pt change",
      coef(models_combo_hard_hit)["gb_improvement"],
      coef(models_combo_hard_hit)["chase_improvement"]
    )
  )
  
  # Model 3: slg - Combo
  models_combo_slg_mid <- lm(mid_slg_change ~ gb_improvement + chase_improvement, data = df_combo)
  models_combo$slg_mid <- list(
    gb_improvement_coef = coef(models_combo_slg_mid)["gb_improvement_pct"],
    chase_improvement_coef = coef(models_combo_slg_mid)["chase_improvement"],
    intercept = coef(models_combo_slg_mid)["(Intercept)"],
    r2_score = summary(models_combo_slg_mid)$r.squared,
    n_observations = nrow(df_combo),
    interpretation = sprintf(
      "GB%%: 1%% improvement → %.3f pt change | Chase%%: 1%% improvement → %.3f pt change",
      coef(models_combo_slg_mid)["gb_improvement_pct"],
      coef(models_combo_slg_mid)["chase_improvement"]
    )
  )

  models_combo_slg_ovr <- lm(ovr_slg_change ~ gb_improvement + chase_improvement, data = df_combo)
  models_combo$slg_ovr <- list(
    gb_improvement_coef = coef(models_combo_slg_ovr)["gb_improvement"],
    chase_improvement_coef = coef(models_combo_slg_ovr)["chase_improvement"],
    intercept = coef(models_combo_slg_ovr)["(Intercept)"],
    r2_score = summary(models_combo_slg_ovr)$r.squared,
    n_observations = nrow(df_combo),
    interpretation = sprintf(
      "GB%%: 1%% improvement → %.3f pt change | Chase%%: 1%% improvement → %.3f pt change",
      coef(models_combo_slg_ovr)["gb_improvement"],
      coef(models_combo_slg_ovr)["chase_improvement"]
    )
  )

    # Model 4: Sweet-Spot% - Combo
  models_combo_sweet_spot <- lm(mid_swspot_change ~ gb_improvement + chase_improvement, data = df_combo)
  models_combo$sweet_spot <- list(
    gb_improvement_coef = coef(models_combo_sweet_spot)["gb_improvement"],
    chase_improvement_coef = coef(models_combo_sweet_spot)["chase_improvement"],
    intercept = coef(models_combo_sweet_spot)["(Intercept)"],
    r2_score = summary(models_combo_sweet_spot)$r.squared,
    n_observations = nrow(df_combo),
    interpretation = sprintf(
      "GB%%: 1%% improvement → %.3f pt change | Chase%%: 1%% improvement → %.3f pt change",
      coef(models_combo_sweet_spot)["gb_improvement"],
      coef(models_combo_sweet_spot)["chase_improvement"]
    )
  )
  
#   return(models)
# }

# ==============================================================================
# CORRELATION & TRADEOFF ANALYSIS
# ==============================================================================

# analyze_gb_impact_tradeoff <- function(transitions_df) {
  # For players who improved GB%, test if impact quality changed unexpectedly
  
  df <- transitions_df %>%
    filter(gb_improvement_pct > 0,  # GB% actually improved (reduced)
           !is.na(whiff_change),
           !is.na(hard_hit_change),
           !is.na(slg_change),
           !is.na(sweet_spot_change),
           Location %in% c("mid (h)", "mid (v)"))
  
  if (nrow(df) < 3) {
    return(list(error = "Insufficient data for correlation analysis"))
  }
  
  # Calculate correlations and p-values
  corr_whiff <- cor(df$gb_improvement_pct, df$whiff_change, use = "complete.obs")
  corr_hard_hit <- cor(df$gb_improvement_pct, df$hard_hit_change, use = "complete.obs")
  corr_slg <- cor(df$gb_improvement_pct, df$slg_change, use = "complete.obs")
  corr_sweet_spot <- cor(df$gb_improvement_pct, df$sweet_spot_change, use = "complete.obs")

  corr_whiff_pp <- cor(df$gb_change, df$whiff_change, use = "complete.obs")
  corr_hard_hit_pp <- cor(df$gb_change, df$hard_hit_change, use = "complete.obs")
  corr_slg_pp <- cor(df$gb_change, df$slg_change, use = "complete.obs")
  corr_sweet_spot_pp <- cor(df$gb_change, df$sweet_spot_change, use = "complete.obs")
  
  # P-values
  test_whiff <- cor.test(df$gb_improvement_pct, df$whiff_change)
  test_hard_hit <- cor.test(df$gb_improvement_pct, df$hard_hit_change)
  test_slg <- cor.test(df$gb_improvement_pct, df$slg_change)
  test_sweet_spot <- cor.test(df$gb_improvement_pct, df$sweet_spot_change)

  test_whiff_pp <- cor.test(df$gb_change, df$whiff_change)
  test_hard_hit_pp <- cor.test(df$gb_change, df$hard_hit_change)
  test_slg_pp <- cor.test(df$gb_change, df$slg_change)
  test_sweet_spot_pp <- cor.test(df$gb_change, df$sweet_spot_change)
  
  result <- list(
    n_players_with_gb_improvement = nrow(df),
    correlations = list(
      gb_improvement_vs_whiff_change = list(
        r = corr_whiff,
        p_value = test_whiff$p.value
      ),
      gb_improvement_vs_hard_hit_change = list(
        r = corr_hard_hit,
        p_value = test_hard_hit$p.value
      ),
      gb_improvement_vs_slg_change = list(
        r = corr_slg,
        p_value = test_slg$p.value
      ),
      gb_improvement_vs_sweet_spot_change = list(
        r = corr_sweet_spot,
        p_value = test_sweet_spot$p.value
      )
    ),
    interpretation = list(
      barrel = if (corr_whiff > 0) "positive" else if (corr_whiff < 0) "negative" else "none",
      hard_hit = if (corr_hard_hit > 0) "positive" else if (corr_hard_hit < 0) "negative" else "none",
      sweet_spot = if (corr_sweet_spot > 0) "positive" else if (corr_sweet_spot < 0) "negative" else "none",
      slg = if (corr_slg > 0) "positive" else if (corr_slg < 0) "negative" else "none"
    )
  )
  
#   return(result)
# }

# ==============================================================================
# FREQUENCY ANALYSIS: How Often Do Players Improve?
# ==============================================================================

# analyze_improvement_frequency <- function(transitions_df, cohort_df) {
  # Analyze how often players in the cohort actually improve both KPIs
  # (GB% and Chase Rate), and among those who improve both, how many see
  # corresponding performance benefits
  
  # Get baseline cohort size
  cohort_size <- nrow(cohort_df %>% 
                      distinct(last_first_name, season))
  
  # Get transitions from cohort
  transitions_from_cohort <- transitions_df %>%
    semi_join(df %>% 
              select(last_first_name, season) %>%
              rename(prior_year = season),
              by = c("last_first_name", "prior_year"))
  
  transition_count <- nrow(transitions_from_cohort %>% distinct(last_first_name, prior_year, current_year))
  
  # Get GB% data (mid-zone vertical)
  gb_transitions <- transitions_from_cohort %>%
    filter(Location == "mid (v)") %>%
    select(last_first_name, prior_year, current_year, gb_improvement_pct, hard_hit_change, sweet_spot_change, slg_change)
  
  # Get Chase Rate data (overall)
  chase_transitions <- transitions_from_cohort %>%
    filter(Location == "overall") %>%
    select(last_first_name, prior_year, current_year, chase_improvement_pct)
  
  # Join to get both metrics for same transitions
  both_kpi_transitions <- gb_transitions %>%
    left_join(chase_transitions, by = c("last_first_name", "prior_year", "current_year")) %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct))
  
  # Count those who improved BOTH GB% AND Chase Rate
  both_improved <- both_kpi_transitions %>%
    filter(gb_improvement_pct > 0,  # GB% improvement (lower is better)
           chase_improvement_pct > 0)  # Chase% improvement (lower is better)
  
  both_improved_count <- nrow(both_improved)
  
  # Among those who improved BOTH KPIs, how many also improved performance?
  # Define performance improvement as positive change in at least 2 of: hard_hit, sweet_spot, or slg
  both_improved_with_perf_gain <- both_improved %>%
    mutate(
      perf_metrics_improved = (if_else(hard_hit_change > 0, 1, 0)) +
                             (if_else(sweet_spot_change > 0, 1, 0)) +
                             (if_else(slg_change > 0, 1, 0))
    ) %>%
    filter(perf_metrics_improved >= 2)
  
  perf_gain_count <- nrow(both_improved_with_perf_gain)
  
  # Calculate percentages
  pct_both_improved <- if (transition_count > 0) (both_improved_count / transition_count) * 100 else 0
  pct_with_perf_benefit <- if (both_improved_count > 0) (perf_gain_count / both_improved_count) * 100 else 0
  
  result <- list(
    cohort_size = cohort_size,
    total_transitions = transition_count,
    both_kpi_improvements = both_improved_count,
    both_kpi_with_perf_gain = perf_gain_count,
    pct_both_improved = pct_both_improved,
    pct_both_with_benefit = pct_with_perf_benefit,
    summary = sprintf(
      "Of %d player-seasons in the elevated KPI cohort, %d (%.1f%%) improved both GB%% and Chase Rate in the following year. Among those who improved both KPIs, %d (%.1f%%) also gained in performance quality (2+ metrics improved).",
      cohort_size,
      both_improved_count,
      pct_both_improved,
      perf_gain_count,
      pct_with_perf_benefit
    )
  )
  
  return(result)

    specific_gb <- transitions_df %>%
    filter(Location %in% c("mid (v)","mid (h)")
    # ,gb_change <= -5.0
    ) %>%
    group_by(last_first_name,prior_year,current_year) %>%
    summarise(tot = n())

# 342
# 969
# }

# ==============================================================================
# EXEMPLAR IDENTIFICATION
# ==============================================================================

# identify_exemplars <- function(transitions_df, n_exemplars = 3) {
  # Identify 2-3 key player transitions representing different patterns

  df <- transitions_df %>%
    filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct),
           !is.na(whiff_change), !is.na(hard_hit_change), !is.na(slg_change),
           !is.na(sweet_spot_change)
          #  , Location %in% c("mid (h)", "mid (v)")
          #  , Location == "overall"
           ) %>%
    group_by(last_first_name,prior_year,current_year) %>%
    summarise(
      gb_improvement = gb_change[Location == "mid (v)"],
      chase_improvement = chase_improvement_pct[Location == "overall"],
      ovr_slg_change = slg_change[Location == "overall"],
      mid_slg_change = slg_change[Location == "mid (v)"],
      mid_whiff_change = whiff_change[Location == "mid (v)"],
      mid_hh_change = hard_hit_change[Location == "mid (v)"],
      mid_swspot_change = sweet_spot_change[Location == "mid (v)"]
    ) %>%
    mutate(impact_quality_score = (mid_slg_change + mid_hh_change + mid_swspot_change) / 3,
           overall_improvement = gb_improvement + chase_improvement)
  # df <- transitions_df %>%
  #   mutate(impact_quality_score = (slg_change + hard_hit_change + sweet_spot_change) / 3,
  #          overall_improvement = gb_improvement_pct + chase_improvement_pct)
  
  # Create scatter plot: sweet_spot_change vs gb_change
  
  # if (nrow(df) > 0) {
    exemplar_plot <- ggplot(df, aes(x = gb_improvement, y = mid_swspot_change, 
                                          color = mid_slg_change, shape = factor(prior_year),
                                          label = last_first_name)) +
      geom_point(size = 3, alpha = 0.6) +
      geom_text(vjust = -0.5, size = 2.5, check_overlap = TRUE) +
      labs(
        title = "GB% Change vs Sweet Spot Change (Mid-Zone)",
        x = "GB% Change (pp)",
        y = "Sweet Spot% Change (pp)",
        color = "SLG Change",
        shape = "Prior Year"
      ) +
      scale_color_gradient2(low = "red", mid = "white", high = "green", midpoint = 0) +
      theme_minimal() +
      theme(
        plot.title = element_text(face = "bold"),
        axis.title = element_text(face = "bold"),
        legend.position = "right"
      )
    
  #   print(exemplar_plot)
  # }
  
  exemplars <- list()
  
  # Pattern 1: GB% improved + impact quality improved
  pattern1 <- df %>%
    filter(gb_improvement > 0, impact_quality_score > 0) %>%
    arrange(desc(gb_improvement)) %>%
    slice(1)
  
  if (nrow(pattern1) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "Improved GB% with improved impact quality",
      data = as.list(pattern1)
    )
  }
  
  # Pattern 2: GB% improved but impact quality degraded
  pattern2 <- df %>%
    filter(gb_improvement > 0, impact_quality_score < 0) %>%
    arrange(desc(gb_improvement)) %>%
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
  
  # Pattern 4: Significant GB% improvement with minimal SLG/hard-hit change
  # Define "minimal" as within -1 to +1 pp for both metrics, "significant" as >2 pp GB improvement
  pattern4 <- df %>%
    filter(gb_improvement < -10
           ,abs(mid_slg_change) <= 0.045
           ,abs(mid_hh_change) <= 5
           ) %>%
    arrange(desc(gb_improvement)) %>%
    slice(1)
  
  if (nrow(pattern4) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "Significant GB% improvement with stable SLG/hard-hit",
      data = as.list(pattern4)
    )
  }
  
  # Pattern 5: Strong GB%/Sweet Spot relationship (exemplifies the R²=0.23 correlation)
  # Look for player with both notable GB% improvement AND corresponding sweet spot improvement
  pattern5 <- df %>%
    filter(gb_improvement < -3,  # Meaningful GB% reduction (negative = improvement)
           mid_swspot_change > 2) %>%  # Meaningful sweet spot gain
    arrange(desc(mid_swspot_change)) %>%
    slice(1)
  
  if (nrow(pattern5) > 0) {
    exemplars[[length(exemplars) + 1]] <- list(
      pattern = "GB% improvement with accompanying sweet spot improvement (correlation exemplar)",
      data = as.list(pattern5)
    )
  }
  
#   return(exemplars)
# }

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
  
  # Frequency analysis
  if (!is.null(analysis_results$frequency)) {
    report <- c(report, "## Improvement Frequency Analysis")
    freq <- analysis_results$frequency
    report <- c(report, sprintf("**%s**\n", freq$summary))
    report <- c(report, sprintf("- **Cohort baseline:** %d player-seasons", freq$cohort_size))
    report <- c(report, sprintf("- **With year-to-year transition:** %d", freq$total_transitions))
    report <- c(report, sprintf("- **Both KPIs improved next year:** %d (%.1f%%)", freq$both_kpi_improvements, freq$pct_both_improved))
    report <- c(report, sprintf("- **Of those, gained in performance:** %d (%.1f%%)\n", freq$both_kpi_with_perf_gain, freq$pct_both_with_benefit))
  }
  
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
  
  # Frequency analysis
  analysis_results$frequency <- analyze_improvement_frequency(transitions_df, cohort_df)
  cat(sprintf("  ✓ Frequency analysis complete\n"))
  cat(sprintf("    - %d/%d (%.1f%%) improved BOTH GB%% and Chase Rate\n", 
              analysis_results$frequency$both_kpi_improvements,
              analysis_results$frequency$total_transitions,
              analysis_results$frequency$pct_both_improved))
  
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
