#!/usr/bin/env Rscript
# Troubleshooting script for batter trend report generation
# Helps identify why players are or aren't included in trend reports

library(tidyverse)
library(readr)
library(lubridate)

# SOURCE HELPER FUNCTIONS
source("scripts/calculate_metrics.R")

# LOAD DATA
cat("Loading data...\n")
all_data <- read_csv(".system/all_statcast_data.csv")
hitter_log <- read_csv(".system/hitter_tracking_log.csv")

# DATE PARAMETERS
current_date <- Sys.Date()
max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
data_month <- month(max_game_date)
data_year <- year(max_game_date)
year_start <- paste0(data_year, "-01-01")

prev_month_end <- as.Date(paste0(data_year, "-", 
                                sprintf("%02d", data_month - 1), "-28")) %>%
  ceiling_date("month") - days(1)

cat("Current date:\", format(current_date, "%B %d, %Y"), "\n")
cat("Latest game_date in data:\", format(max_game_date, "%B %d, %Y"), "\n")
cat("Trend report date range:\", format(as.Date(year_start), "%B %d"), "to\", 
    format(prev_month_end, "%B %d"), "\n")
cat("Data month for exclusion check:\", data_month, "/\", data_year, "\n\n")

# IDENTIFY ELIGIBLE PLAYERS
cat("=== ELIGIBLE PLAYERS CHECK ===\n\n")

eligible_batters <- hitter_log %>%
  filter(status == "reported") %>%
  mutate(report_month = month(as.Date(report_date)),
         report_year = year(as.Date(report_date)),
         first_report_this_data_month = (report_month == data_month & report_year == data_year))

cat("Total hitters in tracking log with 'reported' status:", nrow(eligible_batters), "\n")
cat("Hitters excluded (first report in data month):", 
    sum(eligible_batters$first_report_this_data_month), "\n")
cat("Hitters truly eligible for trend report:", 
    nrow(eligible_batters) - sum(eligible_batters$first_report_this_data_month), "\n\n")

# SHOW EXCLUDED PLAYERS
excluded_this_month <- eligible_batters %>%
  filter(first_report_this_data_month)

if (nrow(excluded_this_month) > 0) {
  cat("Players excluded (first report this month):\n")
  print(excluded_this_month %>% select(batter, report_date), n = Inf)
  cat("\n")
}

# ANALYZE ELIGIBLE PLAYERS
trend_eligible_batters <- eligible_batters %>%
  filter(!first_report_this_month) %>%
  pull(batter)

cat("=== TREND ELIGIBLE PLAYERS ANALYSIS ===\n\n")
cat("Checking metric changes for", length(trend_eligible_batters), "eligible hitters:\n\n")

# Thresholds for significance
thresholds <- list(
  swing_pct = 5.0,
  chase_pct = 5.0,
  foul_pct = 5.0,
  whiff_pct = 5.0,
  iz_whiff = 5.0,
  oz_whiff = 5.0,
  gb_pct = 5.0,
  barrel_pct = 2.0,
  hh_pct = 2.5,
  slg = 0.050,
  swspt_pct = 5.0
)

# Analyze each eligible player
analysis_results <- tibble()

cat("Using YTD data from", format(as.Date(year_start), "%B %d"), "to", 
    format(prev_month_end, "%B %d"), "(previous month)  ")  
cat("and", format(as.Date(year_start), "%B %d"), "to", 
    format(max_game_date, "%B %d"), "(through current data)\n\n")

for (batter_id in trend_eligible_batters) {
  batter_name <- hitter_log %>% 
    filter(batter == batter_id) %>% 
    pull(batter_name) %>% 
    first()
  
  # Get previous period data
  prev_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  # Get current period data
  curr_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= current_date)
  
  prev_bips <- nrow(prev_data %>% filter(!is.na(events)))
  curr_bips <- nrow(curr_data %>% filter(!is.na(events)))
  
  # Calculate metrics
  prev_metrics <- calculate_batter_overall_perf(prev_data)
  curr_metrics <- calculate_batter_overall_perf(curr_data)
  
  # Calculate deltas
  metric_deltas <- tibble(
    swing_pct = curr_metrics$swing_pct - prev_metrics$swing_pct,
    chase_pct = curr_metrics$chase_pct - prev_metrics$chase_pct,
    foul_pct = curr_metrics$foul_pct - prev_metrics$foul_pct,
    whiff_pct = curr_metrics$whiff_pct - prev_metrics$whiff_pct,
    iz_whiff = curr_metrics$iz_whiff - prev_metrics$iz_whiff,
    oz_whiff = curr_metrics$oz_whiff - prev_metrics$oz_whiff,
    gb_pct = curr_metrics$gb_pct - prev_metrics$gb_pct,
    barrel_pct = curr_metrics$barrel_pct - prev_metrics$barrel_pct,
    hh_pct = curr_metrics$hh_pct - prev_metrics$hh_pct,
    slg = curr_metrics$slg - prev_metrics$slg,
    swspt_pct = curr_metrics$swspt_pct - prev_metrics$swspt_pct
  )
  
  # Check for significant changes
  significant_metrics <- list()
  for (metric in names(metric_deltas)) {
    delta <- metric_deltas[[metric]]
    threshold <- thresholds[[metric]]
    
    if (!is.na(delta) && abs(delta) >= threshold) {
      significant_metrics[[metric]] <- delta
    }
  }
  
  # Store results
  is_significant <- length(significant_metrics) > 0
  
  analysis_results <- analysis_results %>%
    bind_rows(tibble(
      batter_id = batter_id,
    #   batter_name = batter_name,
      prev_bips = prev_bips,
      curr_bips = curr_bips,
      is_significant = is_significant,
      num_significant_changes = length(significant_metrics),
      metric_deltas = list(metric_deltas)
    ))
}

# Display results
cat("SIGNIFICANT CHANGES (≥ threshold):\n")
cat(paste(rep("-", 80), collapse = ""), "\n")

significant_players <- analysis_results %>% filter(is_significant)

if (nrow(significant_players) > 0) {
  for (i in seq_len(nrow(significant_players))) {
    player <- significant_players[i, ]
    cat("\n", player$batter_name, "(ID:", player$batter_id, ")\n")
    cat("  Previous Period:", player$prev_bips, "BIPs | Current Period:", 
        player$curr_bips, "BIPs\n")
    cat("  Significant Changes:", player$num_significant_changes, "\n")
    
    deltas <- player$metric_deltas[[1]]
    for (metric in names(deltas)) {
      delta <- deltas[[metric]]
      threshold <- thresholds[[metric]]
      
      if (!is.na(delta) && abs(delta) >= threshold) {
        direction <- if (delta > 0) "↑" else "↓"
        if (metric == "slg") {
          cat("    ", direction, metric, ":", sprintf("%+.3f", delta), 
              "(threshold: ±", threshold, ")\n")
        } else {
          cat("    ", direction, metric, ":", sprintf("%+.1f", delta), "%", 
              "(threshold: ±", threshold, "%)\n")
        }
      }
    }
  }
  cat("\n")
} else {
  cat("No hitters with significant metric changes.\n\n")
}

# NEAR THRESHOLD ANALYSIS
cat("NEAR THRESHOLD (within 2% of threshold):\n")
cat(paste(rep("-", 80), collapse = ""), "\n")

near_threshold <- tibble()

for (i in seq_len(nrow(analysis_results))) {
  player <- analysis_results[i, ]
  deltas <- player$metric_deltas[[1]]
  
  near_metrics <- list()
  for (metric in names(deltas)) {
    delta <- deltas[[metric]]
    threshold <- thresholds[[metric]]
    
    if (!is.na(delta)) {
      # For percentage metrics, check if within 2%
      if (metric != "slg") {
        pct_to_threshold <- (abs(delta) / threshold) * 100
        if (pct_to_threshold >= 80 && pct_to_threshold < 100) {
          near_metrics[[metric]] <- list(delta = delta, pct_to_threshold = pct_to_threshold)
        }
      } else {
        # For SLG, check if within 80% of threshold
        pct_to_threshold <- (abs(delta) / threshold) * 100
        if (pct_to_threshold >= 80 && pct_to_threshold < 100) {
          near_metrics[[metric]] <- list(delta = delta, pct_to_threshold = pct_to_threshold)
        }
      }
    }
  }
  
  if (length(near_metrics) > 0) {
    near_threshold <- near_threshold %>%
      bind_rows(tibble(
        batter_name = player$batter_name,
        batter_id = player$batter_id,
        near_metrics = list(near_metrics)
      ))
  }
}

if (nrow(near_threshold) > 0) {
  for (i in seq_len(nrow(near_threshold))) {
    player <- near_threshold[i, ]
    cat("\n", player$batter_name, "(ID:", player$batter_id, ")\n")
    
    near_metrics <- player$near_metrics[[1]]
    for (metric in names(near_metrics)) {
      delta <- near_metrics[[metric]]$delta
      pct_to_threshold <- near_metrics[[metric]]$pct_to_threshold
      threshold <- thresholds[[metric]]
      
      direction <- if (delta > 0) "↑" else "↓"
      if (metric == "slg") {
        cat("    ", direction, metric, ":", sprintf("%+.3f", delta), 
            "(", sprintf("%.0f", pct_to_threshold), "% to threshold of ±", threshold, ")\n")
      } else {
        cat("    ", direction, metric, ":", sprintf("%+.1f", delta), "%", 
            "(", sprintf("%.0f", pct_to_threshold), "% to threshold of ±", threshold, "%)\n")
      }
    }
  }
  cat("\n")
} else {
  cat("No hitters near thresholds.\n\n")
}

# DATA AVAILABILITY CHECK
cat("=== DATA AVAILABILITY CHECK ===\n")
cat("Total records in all_statcast_data.csv:", nrow(all_data), "\n")
cat("Records with batter field:", sum(!is.na(all_data$batter)), "\n")
cat("Unique batters in dataset:", n_distinct(all_data$batter), "\n")
cat("Batters in tracking log:", nrow(hitter_log), "\n\n")

# FINAL SUMMARY
cat("=== SUMMARY ===\n")
cat("Hitters included in trend report:", nrow(significant_players), "\n")
cat("Hitters excluded (first report this month):", sum(eligible_batters$first_report_this_month), "\n")
cat("Hitters not yet reported:", nrow(hitter_log %>% filter(status == "new")), "\n")
cat("Total eligible for trend check:", length(trend_eligible_batters), "\n\n")

cat("Script completed. Check which players you expected to see above.\n")
