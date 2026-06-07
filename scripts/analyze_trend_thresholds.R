# Trend Report Threshold Calibration Analysis
# Analyzes month-to-month percentile changes to inform threshold setting
# 
# Usage:
# 1. Load your MLB statcast data into a dataframe called 'data'
# 2. Run this script to analyze percentile change distributions

library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)
library(RMySQL)
library(baseballr)
library(stringr)
library(lubridate)

# =============================================================================
# LOAD YOUR DATA HERE
# =============================================================================
conn <- dbConnect(
  MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

    hitter_data <- dbGetQuery(conn,glue::glue(
    "
    with cte1 as (
    select
    batter,
    month(game_date) as season_month,
    year(game_date) as season_year,
    count(*) as tot
    from sc_mlb 
    where 
    game_year in (2024,2025)
    and game_type = 'R'
    and description = 'hit_into_play'
    and month(game_date) IN (3,4,5)
    group by batter, month(game_date), year(game_date)
    )

    , cte2 as (select 
    batter,
    season_year,
    sum(tot) as bip
    from cte1
    group by batter, season_year
    )

    select
    m.*
    from sc_mlb m 
    join cte2 t 
    on m.batter = t.batter
    and m.game_year = t.season_year
    and t.bip >= 100
    and m.game_type = 'R'
    ",
    .con = conn
    )
    )

hitter_data$launch_speed <- as.numeric(hitter_data$launch_speed)
hitter_data$launch_angle <- as.numeric(hitter_data$launch_angle)
hitter_data$estimated_woba_using_speedangle <- as.numeric(hitter_data$estimated_woba_using_speedangle)
hitter_data$estimated_slg_using_speedangle <- as.numeric(hitter_data$estimated_slg_using_speedangle)
hitter_data$woba_value <- as.numeric(hitter_data$woba_value)
hitter_data$hc_x <- as.numeric(hitter_data$hc_x)
hitter_data$hc_y <- as.numeric(hitter_data$hc_y)

pitcher_data <- dbGetQuery(conn,glue::glue(
  "
  with cte1 as (
select
pitcher,
month(game_date) as season_month,
year(game_date) as season_year,
count(*) as tot
from sc_mlb 
where 
game_year in (2024,2025)
and game_type = 'R'
and description = 'hit_into_play'
and month(game_date) IN (3,4,5)
group by pitcher, month(game_date), year(game_date)
)

, cte2 as (select 
pitcher,
season_year,
sum(tot) as bip
from cte1
group by pitcher, season_year
)

select
m.*
from sc_mlb m 
join cte2 t 
on m.pitcher = t.pitcher
and m.game_year = t.season_year
and t.bip >= 100
and m.game_type = 'R'
  ",
  .con = conn
  )
)

pitcher_data$launch_speed <- as.numeric(pitcher_data$launch_speed)
pitcher_data$launch_angle <- as.numeric(pitcher_data$launch_angle)
pitcher_data$estimated_woba_using_speedangle <- as.numeric(pitcher_data$estimated_woba_using_speedangle)
pitcher_data$estimated_slg_using_speedangle <- as.numeric(pitcher_data$estimated_slg_using_speedangle)
pitcher_data$woba_value <- as.numeric(pitcher_data$woba_value)
# 
# The script expects data in statcast format with columns like:
# Pitcher data: game_date, pitcher, player_name, release_speed, etc.
# Hitter data: game_date, batter, release_speed, plate_x, plate_z, etc.
# 
# After loading both dataframes, run the rest of the script below.

# =============================================================================
# Load percentile rank data
# =============================================================================
pitcher_overall_percentiles <- read_csv("data/supporting/pitcher_overall_overall.csv", show_col_types = FALSE) %>%
rename(
  swing_pct = "Swing%",
  strike_pct = "Strike%",
  zone_pct = "Zone%",
  chase_pct = "Chase%",
  whiff_pct = "Whiff%",
  iz_whiff = "IZ Whiff",
  oz_whiff = "OZ Whiff",
  gb_pct = "GB%",
  hh_pct = "HH%"
)
batter_overall_percentiles <- read_csv("data/supporting/batter_overall_overall.csv", show_col_types = FALSE)

# =============================================================================
# Source metric calculation functions
# =============================================================================
source("scripts/calculate_metrics.R")

# Set up data references for analysis
pitcher_data_mlb <- pitcher_data
hitter_data_mlb <- hitter_data

# =============================================================================
# Helper function: Get percentile rank for a metric value
# =============================================================================
# get_percentile(prev_val, metric, "pitcher", pitcher_overall_percentiles)

get_percentile <- function(value, metric, player_type, percentile_data) {
  # Returns the percentile rank (0-100) for a given metric value
  if (is.na(value)) return(NA)
  
  metric_col <- paste0(metric, "_pct")
  value_col <- paste0(metric, "_value")
  
  if (!metric %in% colnames(percentile_data)) {
    return(NA)
  }
  
  # Find the closest value in the percentile table
  percentile_data <- percentile_data %>% filter(!is.na(!!sym(value_col)))
  
  if (value <= min(percentile_data[[value_col]], na.rm = TRUE)) return(0)
  if (value >= max(percentile_data[[value_col]], na.rm = TRUE)) return(100)
  
  # Linear interpolation between closest values
  lower <- percentile_data %>% filter(!!sym(value_col) <= value) %>% slice_max(!!sym(value_col), n=1)
  upper <- percentile_data %>% filter(!!sym(value_col) >= value) %>% slice_min(!!sym(value_col), n=1)
  
  if (nrow(lower) == 0 || nrow(upper) == 0) return(NA)
  
  lower_val <- lower[[value_col]][1]
  upper_val <- upper[[value_col]][1]
  lower_pct <- lower[[metric_col]][1]
  upper_pct <- upper[[metric_col]][1]
  
  if (lower_val == upper_val) return(lower_pct)
  
  # Linear interpolation
  pct <- lower_pct + (value - lower_val) / (upper_val - lower_val) * (upper_pct - lower_pct)
  return(pct)
}

# =============================================================================
# PITCHER ANALYSIS
# =============================================================================

cat("\n========== PITCHER TREND THRESHOLD ANALYSIS ==========\n\n")

# pitcher_metrics <- list(
#   "Swing%",
#   "Strike%",
#   "Zone%",
#   "Chase%",
#   "Whiff%",
#   "IZ Whiff",
#   "OZ Whiff",
#   "GB%",
#   "HH%"
# )

pitcher_metrics <- list(
  swing_pct = "Swing%",
  strike_pct = "Strike%",
  zone_pct = "Zone%",
  chase_pct = "Chase%",
  whiff_pct = "Whiff%",
  iz_whiff = "IZ Whiff",
  oz_whiff = "OZ Whiff",
  gb_pct = "GB%",
  hh_pct = "HH%"
)

# Get unique years in data (for season-level analysis)
pitcher_data_mlb <- pitcher_data_mlb %>% mutate(game_date = as.Date(game_date))
hitter_data_mlb <- hitter_data_mlb %>% mutate(game_date = as.Date(game_date))

# Extract year and get list of years
years_available <- unique(c(
  pitcher_data_mlb %>% mutate(year = year(game_date)) %>% pull(year) %>% unique(),
  hitter_data_mlb %>% mutate(year = year(game_date)) %>% pull(year) %>% unique()
)) %>% sort()

cat("Data years available:", paste(years_available, collapse = ", "), "\n\n")

if (length(years_available) < 1) {
  cat("No data available for analysis.\n")
} else {
  
  # Build pitcher YTD cumulative comparisons (same logic as process_statcast)
  pitcher_deltas_all <- tibble()
  
  # For each year in data, create month-to-month YTD comparisons
  for (year in years_available) {
    # Get all months in this year
    months_in_year <- pitcher_data_mlb %>%
      filter(year(game_date) == year) %>%
      mutate(month = month(game_date)) %>%
      pull(month) %>%
      unique() %>%
      sort()
    
    # Need at least 3 months to do comparisons (month 1 for baseline, then compare 2 vs 1, 3 vs 2, etc.)
    if (length(months_in_year) < 3) next
    
    # Compare each consecutive pair: (YTD through month i-2) vs (YTD through month i-1)
    # Only analyze June-September window (months 5-9, comparing May-June through Aug-Sept)
    for (i in 3:length(months_in_year)) {
      prev_month <- months_in_year[i-2]
      curr_month <- months_in_year[i-1]
      
      # Skip if not in the June-September analysis window
      if (!(prev_month >= 5 && curr_month <= 9)) next
      
      year_start <- as.Date(paste0(year, "-01-01"))
      prev_period_end <- as.Date(paste0(year, "-", sprintf("%02d", prev_month), "-28")) %>%
        ceiling_date("month") - days(1)
      curr_period_end <- as.Date(paste0(year, "-", sprintf("%02d", curr_month), "-28")) %>%
        ceiling_date("month") - days(1)
      
      # Get pitchers with 50+ pitches in BOTH YTD periods
      prev_pitchers <- pitcher_data_mlb %>%
        filter(between(game_date, year_start, prev_period_end)) %>%
        group_by(pitcher, player_name) %>%
        summarise(pitch_count = n(), .groups = "drop") %>%
        filter(pitch_count >= 50)
      
      curr_pitchers <- pitcher_data_mlb %>%
        filter(between(game_date, year_start, curr_period_end)) %>%
        group_by(pitcher, player_name) %>%
        summarise(pitch_count = n(), .groups = "drop") %>%
        filter(pitch_count >= 50)
      
      # Find overlap
      overlap_pitchers <- intersect(prev_pitchers$pitcher, curr_pitchers$pitcher)
      
      if (length(overlap_pitchers) == 0) next
      
      for (pid in overlap_pitchers) {
        pname <- prev_pitchers %>% filter(pitcher == pid) %>% pull(player_name) %>% first()
        
        # YTD through previous period end date
        prev_data <- pitcher_data_mlb %>%
          filter(pitcher == pid, between(game_date, year_start, prev_period_end))
        
        # YTD through current period end date
        curr_data <- pitcher_data_mlb %>%
          filter(pitcher == pid, between(game_date, year_start, curr_period_end))
        
        prev_metrics <- calculate_pitcher_overall_perf(prev_data)
        curr_metrics <- calculate_pitcher_overall_perf(curr_data)
        
        # Calculate percentiles and deltas
        for (metric in names(pitcher_metrics)) {
          prev_val <- prev_metrics[[metric]]
          curr_val <- curr_metrics[[metric]]
          
          if (is.na(prev_val) || is.na(curr_val)) next
          
          prev_pct <- get_percentile(prev_val, metric, "pitcher", pitcher_overall_percentiles)
          curr_pct <- get_percentile(curr_val, metric, "pitcher", pitcher_overall_percentiles)
          
          if (is.na(prev_pct) || is.na(curr_pct)) next
          
          delta_pct <- curr_pct - prev_pct
          
          pitcher_deltas_all <- rbind(pitcher_deltas_all, tibble(
            pitcher = pid,
            player_name = pname,
            comparison = sprintf("YTD through %s vs %s", month.abb[prev_month], month.abb[curr_month]),
            metric = metric,
            metric_name = pitcher_metrics[[metric]],
            prev_value = prev_val,
            curr_value = curr_val,
            prev_percentile = prev_pct,
            curr_percentile = curr_pct,
            delta_percentile = delta_pct,
            delta_absolute = curr_val - prev_val
          ))
        }
      }
    }
  }
  
  # Analyze distributions
  if (nrow(pitcher_deltas_all) > 0) {
    cat("Total pitcher-metric month-pairs analyzed:", nrow(pitcher_deltas_all), "\n\n")
    
    for (metric in names(pitcher_metrics)) {
      metric_data <- pitcher_deltas_all %>% filter(metric == !!metric)
      
      if (nrow(metric_data) == 0) next
      
      cat(sprintf("%-15s (n=%4d)\n", pitcher_metrics[[metric]], nrow(metric_data)))
      cat("  Percentile Delta Distribution:\n")
      
      # Create bins for percentile deltas
      bins <- c(0, 2, 5, 10, 15, 20, Inf)
      bin_labels <- c("0-2pp", "2-5pp", "5-10pp", "10-15pp", "15-20pp", "20pp+")
      
      for (j in 1:(length(bins)-1)) {
        lower <- bins[j]
        upper <- bins[j+1]
        count <- nrow(metric_data %>% filter(abs(delta_percentile) >= lower & abs(delta_percentile) < upper))
        pct <- 100 * count / nrow(metric_data)
        
        cat(sprintf("    %8s: %3d cases (%5.1f%%)\n", bin_labels[j], count, pct))
      }
      
      cat(sprintf("    Mean: %+.2f pp, Median: %+.2f pp, SD: %.2f pp\n",
                  mean(metric_data$delta_percentile, na.rm=TRUE),
                  median(metric_data$delta_percentile, na.rm=TRUE),
                  sd(metric_data$delta_percentile, na.rm=TRUE)))
      cat("\n")
    }
  }
}

# =============================================================================
# PITCHER ARSENAL ANALYSIS
# =============================================================================

cat("\n========== PITCHER ARSENAL THRESHOLD ANALYSIS ==========\n\n")

pitcher_arsenal_metrics <- list(
  velo = "Velocity (mph)",
  rel_side = "Release Side (ft)",
  rel_height = "Release Height (ft)",
  hb = "H-Break (in)",
  vb = "V-Break (in)",
  spin = "Spin Rate (rpm)"
)

if (nrow(pitcher_deltas_all) > 0) {
  
  pitcher_arsenal_deltas <- tibble()
  
  for (year in years_available) {
    months_in_year <- pitcher_data_mlb %>%
      filter(year(game_date) == year) %>%
      mutate(month = month(game_date)) %>%
      pull(month) %>%
      unique() %>%
      sort()
    
    if (length(months_in_year) < 3) next
    
    for (i in 3:length(months_in_year)) {
      prev_month <- months_in_year[i-2]
      curr_month <- months_in_year[i-1]
      
      if (!(prev_month >= 5 && curr_month <= 9)) next
      
      year_start <- as.Date(paste0(year, "-01-01"))
      prev_period_end <- as.Date(paste0(year, "-", sprintf("%02d", prev_month), "-28")) %>%
        ceiling_date("month") - days(1)
      curr_period_end <- as.Date(paste0(year, "-", sprintf("%02d", curr_month), "-28")) %>%
        ceiling_date("month") - days(1)
      
      prev_pitchers <- pitcher_data_mlb %>%
        filter(between(game_date, year_start, prev_period_end)) %>%
        group_by(pitcher, player_name) %>%
        summarise(pitch_count = n(), .groups = "drop") %>%
        filter(pitch_count >= 50)
      
      curr_pitchers <- pitcher_data_mlb %>%
        filter(between(game_date, year_start, curr_period_end)) %>%
        group_by(pitcher, player_name) %>%
        summarise(pitch_count = n(), .groups = "drop") %>%
        filter(pitch_count >= 50)
      
      overlap_pitchers <- intersect(prev_pitchers$pitcher, curr_pitchers$pitcher)
      
      if (length(overlap_pitchers) == 0) next
      
      for (pid in overlap_pitchers) {
        pname <- prev_pitchers %>% filter(pitcher == pid) %>% pull(player_name) %>% first()
        
        prev_data <- pitcher_data_mlb %>%
          filter(pitcher == pid, between(game_date, year_start, prev_period_end))
        
        curr_data <- pitcher_data_mlb %>%
          filter(pitcher == pid, between(game_date, year_start, curr_period_end))
        
        # Calculate arsenal metrics (these are just means, not percentiles)
        for (metric in names(pitcher_arsenal_metrics)) {
          prev_val <- mean(prev_data[[metric]], na.rm = TRUE)
          curr_val <- mean(curr_data[[metric]], na.rm = TRUE)
          
          if (is.na(prev_val) || is.na(curr_val)) next
          
          delta_abs <- curr_val - prev_val
          
          pitcher_arsenal_deltas <- rbind(pitcher_arsenal_deltas, tibble(
            pitcher = pid,
            player_name = pname,
            comparison = sprintf("YTD through %s vs %s", month.abb[prev_month], month.abb[curr_month]),
            metric = metric,
            metric_name = pitcher_arsenal_metrics[[metric]],
            prev_value = prev_val,
            curr_value = curr_val,
            delta = delta_abs
          ))
        }
      }
    }
  }
  
  # Analyze distributions
  if (nrow(pitcher_arsenal_deltas) > 0) {
    cat("Total pitcher-metric month-pairs analyzed:", nrow(pitcher_arsenal_deltas), "\n\n")
    
    for (metric in names(pitcher_arsenal_metrics)) {
      metric_data <- pitcher_arsenal_deltas %>% filter(metric == !!metric)
      
      if (nrow(metric_data) == 0) next
      
      cat(sprintf("%-20s (n=%4d)\n", pitcher_arsenal_metrics[[metric]], nrow(metric_data)))
      cat("  Absolute Delta Distribution:\n")
      
      # Create bins for absolute deltas (metric-specific)
      bins <- case_when(
        metric == "velo" ~ c(-Inf, -2, -1, 0, 1, 2, Inf),
        metric == "spin" ~ c(-Inf, -100, -50, 0, 50, 100, Inf),
        TRUE ~ c(-Inf, -0.5, -0.25, 0, 0.25, 0.5, Inf)
      )
      bin_labels <- case_when(
        metric == "velo" ~ c("<-2 mph", "-2 to -1", "-1 to 0", "0 to 1", "1 to 2", ">2 mph"),
        metric == "spin" ~ c("<-100 rpm", "-100 to -50", "-50 to 0", "0 to 50", "50 to 100", ">100 rpm"),
        TRUE ~ c("<-0.5", "-0.5 to -0.25", "-0.25 to 0", "0 to 0.25", "0.25 to 0.5", ">0.5")
      )
      
      for (j in 1:(length(bins)-1)) {
        lower <- bins[j]
        upper <- bins[j+1]
        count <- nrow(metric_data %>% filter(delta >= lower & delta < upper))
        pct <- 100 * count / nrow(metric_data)
        
        cat(sprintf("    %15s: %3d cases (%5.1f%%)\n", bin_labels[j], count, pct))
      }
      
      cat(sprintf("    Mean: %+.2f, Median: %+.2f, SD: %.2f\n",
                  mean(metric_data$delta, na.rm=TRUE),
                  median(metric_data$delta, na.rm=TRUE),
                  sd(metric_data$delta, na.rm=TRUE)))
      cat("\n")
    }
  }
}

# =============================================================================
# HITTER ANALYSIS
# =============================================================================

cat("\n========== HITTER TREND THRESHOLD ANALYSIS ==========\n\n")

hitter_metrics <- list(
  swing_pct = "Swing%",
  chase_pct = "Chase%",
  foul_pct = "Foul%",
  whiff_pct = "Whiff%",
  iz_whiff = "IZ Whiff",
  oz_whiff = "OZ Whiff",
  gb_pct = "GB%",
  hh_pct = "HH%",
  slg = "Slugging",
  swspt_pct = "Sweet Spot%"
)

if (length(years_available) < 1) {
  cat("No data available for analysis.\n")
} else {
  
  # Build hitter YTD cumulative comparisons (same logic as process_statcast)
  hitter_deltas_all <- tibble()
  
  # For each year in data, create month-to-month YTD comparisons
  for (year in years_available) {
    # Get all months in this year
    months_in_year <- hitter_data_mlb %>%
      filter(year(game_date) == year) %>%
      mutate(month = month(game_date)) %>%
      pull(month) %>%
      unique() %>%
      sort()
    
    # Need at least 3 months to do comparisons
    if (length(months_in_year) < 3) next
    
    # Compare each consecutive pair: (YTD through month i-2) vs (YTD through month i-1)
    # Only analyze June-September window (months 5-9, comparing May-June through Aug-Sept)
    for (i in 3:length(months_in_year)) {
      prev_month <- months_in_year[i-2]
      curr_month <- months_in_year[i-1]
      
      # Skip if not in the June-September analysis window
      if (!(prev_month >= 5 && curr_month <= 9)) next
      
      year_start <- as.Date(paste0(year, "-01-01"))
      prev_period_end <- as.Date(paste0(year, "-", sprintf("%02d", prev_month), "-28")) %>%
        ceiling_date("month") - days(1)
      curr_period_end <- as.Date(paste0(year, "-", sprintf("%02d", curr_month), "-28")) %>%
        ceiling_date("month") - days(1)
      
      # Get hitters with 50+ PAs in BOTH YTD periods
      prev_hitters <- hitter_data_mlb %>%
        filter(between(game_date, year_start, prev_period_end)) %>%
        group_by(batter) %>%
        summarise(pa_count = n(), .groups = "drop") %>%
        filter(pa_count >= 50)
      
      curr_hitters <- hitter_data_mlb %>%
        filter(between(game_date, year_start, curr_period_end)) %>%
        group_by(batter) %>%
        summarise(pa_count = n(), .groups = "drop") %>%
        filter(pa_count >= 50)
      
      # Find overlap
      overlap_hitters <- intersect(prev_hitters$batter, curr_hitters$batter)
      
      if (length(overlap_hitters) == 0) next
      
      for (bid in overlap_hitters) {
        # YTD through previous period end date
        prev_data <- hitter_data_mlb %>%
          filter(batter == bid, between(game_date, year_start, prev_period_end))
        
        # YTD through current period end date
        curr_data <- hitter_data_mlb %>%
          filter(batter == bid, between(game_date, year_start, curr_period_end))
        
        prev_metrics <- calculate_batter_overall_perf(prev_data)
        curr_metrics <- calculate_batter_overall_perf(curr_data)
        
        # Calculate percentiles and deltas
        for (metric in names(hitter_metrics)) {
          prev_val <- prev_metrics[[metric]]
          curr_val <- curr_metrics[[metric]]
          
          if (is.na(prev_val) || is.na(curr_val)) next
          
          prev_pct <- get_percentile(prev_val, metric, "batter", batter_overall_percentiles)
          curr_pct <- get_percentile(curr_val, metric, "batter", batter_overall_percentiles)
          
          if (is.na(prev_pct) || is.na(curr_pct)) next
          
          delta_pct <- curr_pct - prev_pct
          
          hitter_deltas_all <- rbind(hitter_deltas_all, tibble(
            batter = bid,
            comparison = sprintf("YTD through %s vs %s", month.abb[prev_month], month.abb[curr_month]),
            metric = metric,
            metric_name = hitter_metrics[[metric]],
            prev_value = prev_val,
            curr_value = curr_val,
            prev_percentile = prev_pct,
            curr_percentile = curr_pct,
            delta_percentile = delta_pct,
            delta_absolute = curr_val - prev_val
          ))
        }
      }
    }
  }
  
  # Analyze distributions
  if (nrow(hitter_deltas_all) > 0) {
    cat("Total hitter-metric month-pairs analyzed:", nrow(hitter_deltas_all), "\n\n")
    
    for (metric in names(hitter_metrics)) {
      metric_data <- hitter_deltas_all %>% filter(metric == !!metric)
      
      if (nrow(metric_data) == 0) next
      
      cat(sprintf("%-15s (n=%4d)\n", hitter_metrics[[metric]], nrow(metric_data)))
      cat("  Percentile Delta Distribution:\n")
      
      # Create bins for percentile deltas
      bins <- c(0, 2, 5, 10, 15, 20, Inf)
      bin_labels <- c("0-2pp", "2-5pp", "5-10pp", "10-15pp", "15-20pp", "20pp+")
      
      for (j in 1:(length(bins)-1)) {
        lower <- bins[j]
        upper <- bins[j+1]
        count <- nrow(metric_data %>% filter(abs(delta_percentile) >= lower & abs(delta_percentile) < upper))
        pct <- 100 * count / nrow(metric_data)
        
        cat(sprintf("    %8s: %3d cases (%5.1f%%)\n", bin_labels[j], count, pct))
      }
      
      cat(sprintf("    Mean: %+.2f pp, Median: %+.2f pp, SD: %.2f pp\n",
                  mean(metric_data$delta_percentile, na.rm=TRUE),
                  median(metric_data$delta_percentile, na.rm=TRUE),
                  sd(metric_data$delta_percentile, na.rm=TRUE)))
      cat("\n")
    }
  }
}

# =============================================================================
# HITTER PROFILE ANALYSIS
# =============================================================================

cat("\n========== HITTER PROFILE THRESHOLD ANALYSIS ==========\n\n")

hitter_profile_metrics <- list(
  avg_la = "Avg Launch Angle (°)",
  la_std_dev = "LA Std Dev (°)",
  swspt_pct = "Sweet Spot%",
  hh_la = "HH Launch Angle (°)",
  oppo_fb_pct = "Oppo FB%",
  oppo_fb_ev = "Oppo FB Exit Velo (mph)",
  high_aa_pct = "High Attack Angle%"
)

if (nrow(hitter_deltas_all) > 0) {
  
  hitter_profile_deltas <- tibble()
  
  for (year in years_available) {
    months_in_year <- hitter_data_mlb %>%
      filter(year(game_date) == year) %>%
      mutate(month = month(game_date)) %>%
      pull(month) %>%
      unique() %>%
      sort()
    
    if (length(months_in_year) < 3) next
    
    for (i in 3:length(months_in_year)) {
      prev_month <- months_in_year[i-2]
      curr_month <- months_in_year[i-1]
      
      if (!(prev_month >= 5 && curr_month <= 9)) next
      
      year_start <- as.Date(paste0(year, "-01-01"))
      prev_period_end <- as.Date(paste0(year, "-", sprintf("%02d", prev_month), "-28")) %>%
        ceiling_date("month") - days(1)
      curr_period_end <- as.Date(paste0(year, "-", sprintf("%02d", curr_month), "-28")) %>%
        ceiling_date("month") - days(1)
      
      prev_hitters <- hitter_data_mlb %>%
        filter(between(game_date, year_start, prev_period_end)) %>%
        group_by(batter) %>%
        summarise(pa_count = n(), .groups = "drop") %>%
        filter(pa_count >= 50)
      
      curr_hitters <- hitter_data_mlb %>%
        filter(between(game_date, year_start, curr_period_end)) %>%
        group_by(batter) %>%
        summarise(pa_count = n(), .groups = "drop") %>%
        filter(pa_count >= 50)
      
      overlap_hitters <- intersect(prev_hitters$batter, curr_hitters$batter)
      
      if (length(overlap_hitters) == 0) next
      
      for (bid in overlap_hitters) {
        prev_data <- hitter_data_mlb %>%
          filter(batter == bid, between(game_date, year_start, prev_period_end))
        
        curr_data <- hitter_data_mlb %>%
          filter(batter == bid, between(game_date, year_start, curr_period_end))
        
        # Calculate profile metrics (these are just means, not percentiles)
        for (metric in names(hitter_profile_metrics)) {
          prev_val <- mean(prev_data[[metric]], na.rm = TRUE)
          curr_val <- mean(curr_data[[metric]], na.rm = TRUE)
          
          if (is.na(prev_val) || is.na(curr_val)) next
          
          delta_abs <- curr_val - prev_val
          
          hitter_profile_deltas <- rbind(hitter_profile_deltas, tibble(
            batter = bid,
            comparison = sprintf("YTD through %s vs %s", month.abb[prev_month], month.abb[curr_month]),
            metric = metric,
            metric_name = hitter_profile_metrics[[metric]],
            prev_value = prev_val,
            curr_value = curr_val,
            delta = delta_abs
          ))
        }
      }
    }
  }
  
  # Analyze distributions
  if (nrow(hitter_profile_deltas) > 0) {
    cat("Total hitter-metric month-pairs analyzed:", nrow(hitter_profile_deltas), "\n\n")
    
    for (metric in names(hitter_profile_metrics)) {
      metric_data <- hitter_profile_deltas %>% filter(metric == !!metric)
      
      if (nrow(metric_data) == 0) next
      
      cat(sprintf("%-25s (n=%4d)\n", hitter_profile_metrics[[metric]], nrow(metric_data)))
      cat("  Absolute Delta Distribution:\n")
      
      # Create bins for absolute deltas (metric-specific)
      bins <- case_when(
        metric == "oppo_fb_ev" ~ c(-Inf, -2, -1, 0, 1, 2, Inf),
        metric == "avg_la" || metric == "hh_la" ~ c(-Inf, -5, -2, 0, 2, 5, Inf),
        metric == "la_std_dev" ~ c(-Inf, -2, -1, 0, 1, 2, Inf),
        TRUE ~ c(-Inf, -5, -2, 0, 2, 5, Inf)
      )
      bin_labels <- case_when(
        metric == "oppo_fb_ev" ~ c("<-2 mph", "-2 to -1", "-1 to 0", "0 to 1", "1 to 2", ">2 mph"),
        metric == "avg_la" || metric == "hh_la" ~ c("<-5°", "-5° to -2°", "-2° to 0°", "0° to 2°", "2° to 5°", ">5°"),
        metric == "la_std_dev" ~ c("<-2", "-2 to -1", "-1 to 0", "0 to 1", "1 to 2", ">2"),
        TRUE ~ c("<-5", "-5 to -2", "-2 to 0", "0 to 2", "2 to 5", ">5")
      )
      
      for (j in 1:(length(bins)-1)) {
        lower <- bins[j]
        upper <- bins[j+1]
        count <- nrow(metric_data %>% filter(delta >= lower & delta < upper))
        pct <- 100 * count / nrow(metric_data)
        
        cat(sprintf("    %15s: %3d cases (%5.1f%%)\n", bin_labels[j], count, pct))
      }
      
      cat(sprintf("    Mean: %+.2f, Median: %+.2f, SD: %.2f\n",
                  mean(metric_data$delta, na.rm=TRUE),
                  median(metric_data$delta, na.rm=TRUE),
                  sd(metric_data$delta, na.rm=TRUE)))
      cat("\n")
    }
  }
}

# =============================================================================
# Summary recommendations (based on distribution patterns)
# =============================================================================
cat("\n========== THRESHOLD RECOMMENDATIONS ==========\n\n")
cat("Review the distributions above. Look for natural breakpoints where:\n")
cat("- Changes become rarer (transitions from frequent to rare)\n")
cat("- The 'outlier' zone begins\n\n")
cat("Suggested starting points (adjust based on report volume preferences):\n")
cat("  Conservative (more reports):  5pp percentile delta\n")
cat("  Moderate (balanced):           7-8pp percentile delta\n")
cat("  Selective (fewer reports):    10pp percentile delta\n\n")
