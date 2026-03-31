# Main Statcast Data Processing Pipeline
# Reads raw data, calculates metrics, generates reports
source("scripts/calculate_metrics.R")

library(readr)
library(stringr)
library(purrr)
library(dplyr)
library(baseballr)
library(lubridate)

# id <- playername_lookup(434378)
# =============================================================================
# Configuration
# =============================================================================

DATA_DIR <- "data/raw"
OUTPUT_DIR <- "reports"
PROCESSED_DIR <- "data/processed"

# =============================================================================
# Main Processing Function
# =============================================================================

process_weekly_data <- function() {
  # Main orchestration function for weekly report generation
  
  # 1. Load all data files for accumulation
  raw_files <- list.files(DATA_DIR, pattern = "*.csv", full.names = TRUE)
  
  if (length(raw_files) == 0) {
    stop("No CSV files found in data/raw/. Please add Statcast data.")
  }
  
  # Load all data files for complete player history
  all_data <- map_df(raw_files, ~read_csv(., show_col_types = FALSE))
  
  # Get max game_date from data (not real-world current date)
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  
  # Also load just the latest file for new player identification
  latest_file <- raw_files[which.max(file.info(raw_files)$mtime)]
  cat("Loading data from:", latest_file, "\n")
  
  statcast_data <- read_csv(latest_file, show_col_types = FALSE)
  
  # 2. Validate and clean data
  # statcast_data <- validate_statcast(statcast_data)

  # Load tracking logs for trend identification
  pitcher_tracking_path <- ".system/pitcher_tracking_log.csv"
  if (file.exists(pitcher_tracking_path)) {
    pitcher_log <- read_csv(pitcher_tracking_path, show_col_types = FALSE)
  } else {
    pitcher_log <- tibble(pitcher_name = character(), report_date = character(), 
                         bip_count = numeric(), pitch_count = numeric(), 
                         status = character(), notes = character())
  }
  
  hitter_tracking_path <- ".system/hitter_tracking_log.csv"
  if (file.exists(hitter_tracking_path)) {
    hitter_log <- read_csv(hitter_tracking_path, show_col_types = FALSE)
  } else {
    hitter_log <- tibble(batter = character(), report_date = character(), 
                        bip_count = numeric(), pa_count = numeric(), 
                        status = character(), notes = character())
  }

  # 3. Segment by player type and identify reportable players
  new_players <- identify_new_players(statcast_data)
  trend_candidates <- identify_trend_players(all_data, pitcher_log, hitter_log)
  
  # 4. Generate reports
  if (nrow(new_players) > 0) {
    generate_new_player_reports(new_players, statcast_data, all_data, max_game_date)
  }
  
  if (nrow(trend_candidates) > 0) {
    generate_trend_reports(trend_candidates, all_data)
  }
  
  cat("Report generation complete.\n")
}

# =============================================================================
# Data Validation
# =============================================================================

validate_statcast <- function(data) {
  # Basic validation and cleaning of Statcast data
  
  required_cols <- c("pitcher", "batter", "pitch_type", "release_speed", 
                     "plate_x", "plate_z", "launch_angle", "launch_speed")
  
  missing_cols <- setdiff(required_cols, colnames(data))
  if (length(missing_cols) > 0) {
    warning("Missing columns:", paste(missing_cols, collapse = ", "))
  }
  
  # Remove rows with critical missing data
  data <- data %>%
    filter(!is.na(pitcher), !is.na(batter)) %>%
    filter(!is.na(pitch_type))
  
  return(data)
}

# =============================================================================
# Player Identification
# =============================================================================
# data <- statcast_data
identify_new_players <- function(data) {
  # Identifies new players that meet sample size threshold
  # THRESHOLD: Placeholder - will be calibrated after first reports
  
  MIN_SAMPLE <- 50  # Starting threshold
  
  new_pitchers <- data %>%
    group_by(pitcher) %>%
    summarise(pitch_count = n(), .groups = "drop") %>%
    filter(pitch_count >= MIN_SAMPLE)
  
  new_batters <- data %>%
    group_by(batter) %>%
    summarise(pa_count = n(), .groups = "drop") %>%
    filter(pa_count >= MIN_SAMPLE)
  
  return(bind_rows(
    new_pitchers %>% mutate(player_type = "pitcher"),
    new_batters %>% mutate(player_type = "batter")
  ))
}

# =============================================================================
# Trend Identification & Reporting
# =============================================================================

identify_trend_players <- function(all_data, pitcher_log, hitter_log) {
  # Identifies existing players with significant KPI changes month-over-month
  # Only eligible players (status="reported" or "performance_reported") are evaluated
  # Exclusion: players whose first performance report was in the same data month
  # Returns list of players with significant improvements/declines
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  
  # Only generate trend reports at the beginning of each month (1st-3rd in the data)
  # This gives us a full month of data to analyze
  days_into_data_month <- mday(max_game_date)
  if (days_into_data_month > 3) {
    # Data month is past the beginning, skip trend analysis
    return(tibble(
      player_id = character(),
      player_type = character(),
      player_name = character()
    ))
  }
  
  # Previous period: all data from start of data year to end of month before previous month
  # (two months before the current data month)
  prev_month <- if (data_month <= 2) data_month + 10 else data_month - 2  # Go back 2 months
  prev_year <- if (data_month <= 2) data_year - 1 else data_year
  
  prev_period_end <- as.Date(paste0(prev_year, "-", 
                                     sprintf("%02d", prev_month), "-", "28")) %>%
    ceiling_date("month") - days(1)
  
  # Current period: all data from start of data year to end of previous month
  # (one month before the current data month)
  curr_month <- if (data_month == 1) 12 else data_month - 1
  curr_year <- if (data_month == 1) data_year - 1 else data_year
  
  curr_period_end <- as.Date(paste0(curr_year, "-", 
                                     sprintf("%02d", curr_month), "-", "28")) %>%
    ceiling_date("month") - days(1)
  
  trend_players <- tibble(
    player_id = character(),
    player_name = character(),
    player_type = character(),
    metric_changes = list()
  )
  
  # Evaluate eligible pitchers
  eligible_pitchers <- pitcher_log %>%
    filter(status == "performance_reported") %>%
    pull(pitcher_name)
  
  for (pitcher_name in eligible_pitchers) {
    # Skip if performance report was just generated in the data month
    pitcher_report_date <- pitcher_log %>%
      filter(pitcher_name == !!pitcher_name) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(pitcher_report_date)) == data_month &&
        year(as.Date(pitcher_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }
    
    pitcher_id <- all_data %>%
      filter(player_name == pitcher_name) %>%
      pull(pitcher) %>%
      unique() %>%
      first()
    
    if (is.na(pitcher_id)) next
    
    # Aggregate pitcher data for comparison
    result <- compare_pitcher_trend(pitcher_id, pitcher_name, prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  # Evaluate eligible hitters
  eligible_hitters <- hitter_log %>%
    filter(status == "reported") %>%
    pull(batter)
  
  for (batter_id in eligible_hitters) {
    # Skip if performance report was just generated in the data month
    hitter_report_date <- hitter_log %>%
      filter(batter == batter_id) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(hitter_report_date)) == data_month &&
        year(as.Date(hitter_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }
    
    # Note: batter_name field doesn't exist in our data, only pitcher has player_name
    batter_name <- NA  # Set to NA/NULL since we don't have batter names
    
    # Aggregate hitter data for comparison
    result <- compare_batter_trend(as.numeric(batter_id), prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  return(trend_players)
}

compare_pitcher_trend <- function(pitcher_id, pitcher_name, prev_period_end, curr_period_end, all_data, data_month, data_year) {
  # Compares pitcher performance: previous month vs current month (full months only)
  # Exclusion: don't include if first perf report was in the data month
  # Returns tibble if significant changes detected, NULL otherwise
  
  year_start <- paste0(data_year, "-01-01")
  
  # Previous period: start of year through end of two months before current data month
  prev_data <- all_data %>%
    filter(pitcher == pitcher_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end)
  
  # Current period: start of year through end of one month before current data month
  curr_data <- all_data %>%
    filter(pitcher == pitcher_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  
  if (nrow(prev_data) < 50 || nrow(curr_data) < 50) {
    # Not enough data for reliable comparison
    return(NULL)
  }
  
  # Calculate metrics for both periods
  prev_metrics <- calculate_pitcher_overall_perf(prev_data)
  curr_metrics <- calculate_pitcher_overall_perf(curr_data)
  
  # Calculate deltas (current - previous)
  metric_deltas <- list(
    swing_pct = curr_metrics$swing_pct - prev_metrics$swing_pct,
    strike_pct = curr_metrics$strike_pct - prev_metrics$strike_pct,
    zone_pct = curr_metrics$zone_pct - prev_metrics$zone_pct,
    chase_pct = curr_metrics$chase_pct - prev_metrics$chase_pct,
    whiff_pct = curr_metrics$whiff_pct - prev_metrics$whiff_pct,
    iz_whiff = curr_metrics$iz_whiff - prev_metrics$iz_whiff,
    oz_whiff = curr_metrics$oz_whiff - prev_metrics$oz_whiff,
    gb_pct = curr_metrics$gb_pct - prev_metrics$gb_pct,
    hh_pct = curr_metrics$hh_pct - prev_metrics$hh_pct
  )
  
  # Placeholder thresholds - to be calibrated
  thresholds <- list(
    swing_pct = 5.0,      # ±5% significant
    strike_pct = 5.0,
    zone_pct = 5.0,
    chase_pct = 5.0,
    whiff_pct = 5.0,      # ±5% significant
    iz_whiff = 5.0,
    oz_whiff = 5.0,
    gb_pct = 5.0,
    hh_pct = 5.0
  )
  
  # Check if any metric has significant change
  significant_changes <- map_lgl(names(metric_deltas), ~{
    abs(metric_deltas[[.x]]) >= thresholds[[.x]]
  })
  
  if (any(significant_changes)) {
    return(tibble(
      player_id = pitcher_id,
      player_name = pitcher_name,
      player_type = "pitcher",
      metric_changes = list(metric_deltas)
    ))
  }
  
  return(NULL)
}

compare_batter_trend <- function(batter_id, prev_period_end, curr_period_end, all_data, data_month, data_year) {
  # Compares batter performance: previous month vs current month (full months only)
  # Exclusion: don't include if first perf report was in the data month
  # Returns tibble if significant changes detected, NULL otherwise
  
  year_start <- paste0(data_year, "-01-01")
  
  # Previous period: start of year through end of two months before current data month
  prev_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end)
  
  # Current period: start of year through end of one month before current data month
  curr_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  
  if (nrow(prev_data) < 50 || nrow(curr_data) < 50) {
    # Not enough data for reliable comparison
    return(NULL)
  }
  
  # Calculate metrics for both periods
  prev_metrics <- calculate_batter_overall_perf(prev_data)
  curr_metrics <- calculate_batter_overall_perf(curr_data)
  
  # Calculate deltas (current - previous)
  metric_deltas <- list(
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
  
  # Placeholder thresholds - to be calibrated
  thresholds <- list(
    swing_pct = 5.0,      # ±5% significant
    chase_pct = 5.0,
    foul_pct = 5.0,
    whiff_pct = 5.0,      # ±5% significant
    iz_whiff = 5.0,
    oz_whiff = 5.0,
    gb_pct = 2.5,
    barrel_pct = 2.0,     # ±2.0% significant
    hh_pct = 2.5,
    slg = 0.050,          # ±.050 slugging points significant
    swspt_pct = 2.5
  )
  
  # Check if any metric has significant change
  significant_changes <- map_lgl(names(metric_deltas), ~{
    abs(metric_deltas[[.x]]) >= thresholds[[.x]]
  })
  
  if (any(significant_changes)) {
    return(tibble(
      player_id = batter_id,
      player_name = NA,  # No batter name available in our data
      player_type = "batter",
      metric_changes = list(metric_deltas)
    ))
  }
  
  return(NULL)
}

# =============================================================================
# Report Generation
# =============================================================================
generate_new_player_reports <- function(players, data, all_data, max_game_date) {
  # Generates new player profile reports
  # data = current batch data (for identification)
  # all_data = full historical data (for performance report calculations)
  
  # Load or initialize pitcher tracking log
  pitcher_tracking_path <- ".system/pitcher_tracking_log.csv"
  if (file.exists(pitcher_tracking_path)) {
    pitcher_log <- read_csv(pitcher_tracking_path, show_col_types = FALSE)
  } else {
    pitcher_log <- tibble(pitcher_name = character(), report_date = character(), 
                         bip_count = numeric(), pitch_count = numeric(), 
                         status = character(), notes = character())
  }
  
  # Load or initialize hitter tracking log
  hitter_tracking_path <- ".system/hitter_tracking_log.csv"
  if (file.exists(hitter_tracking_path)) {
    hitter_log <- read_csv(hitter_tracking_path, show_col_types = FALSE)
  } else {
    hitter_log <- tibble(batter = character(), report_date = character(), 
                        bip_count = numeric(), pa_count = numeric(), 
                        status = character(), notes = character())
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- if (!is.na(players$pitcher[i])) players$pitcher[i] else players$batter[i]
    player_type <- players$player_type[i]
    
    if (player_type == "pitcher") {
      pitcher_data <- data %>% filter(pitcher == player_id)
      pitcher_name <- pitcher_data$player_name[1]  # Extract actual player name
      filename_name <- pitcher_name
      report <- NULL  # Initialize report as NULL
      
      # Calculate BIP and pitch count
      bip_count <- calculate_pitcher_bip(pitcher_data)
      pitch_count <- nrow(pitcher_data)
      
      # Determine pitcher status and generate appropriate report
      pitcher_idx <- which(pitcher_log$pitcher_name == pitcher_name)
      
      if (length(pitcher_idx) == 0) {
        # New pitcher - add to log and generate arsenal report
        pitcher_log <- rbind(pitcher_log, tibble(
          pitcher_name = pitcher_name,
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pitch_count = pitch_count,
          status = "arsenal_reported",
          notes = ""
        ))
        # Generate arsenal report
        report <- generate_pitcher_report(pitcher_data, pitcher_name)
        
      } else {
        # Pitcher exists - add to BIP/pitch counts and check for performance report trigger
        existing_bip <- pitcher_log$bip_count[pitcher_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- pitcher_log$status[pitcher_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "arsenal_reported" && new_total_bip >= 100) {
          new_status <- "performance_reported"
          # Generate performance report with complete pitcher history
          full_pitcher_data <- all_data %>% filter(pitcher == player_id)
          report <- generate_pitcher_performance_report(full_pitcher_data, pitcher_name, player_id)
        }
        
        pitcher_log <- pitcher_log %>%
          mutate(
            bip_count = if_else(pitcher_name == !!pitcher_name, 
                              new_total_bip, bip_count),
            pitch_count = if_else(pitcher_name == !!pitcher_name, 
                                pitch_count + !!pitch_count, pitch_count),
            status = if_else(pitcher_name == !!pitcher_name,
                           new_status, status),
            report_date = if_else(pitcher_name == !!pitcher_name & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
        
    } else {
      batter_data <- data %>% filter(batter == player_id)
      filename_name <- player_id
      
      # Calculate BIP and PA count
      bip_count <- calculate_hitter_bip(batter_data)
      pa_count <- nrow(batter_data)
      
      # Determine hitter status and generate appropriate report
      hitter_idx <- which(hitter_log$batter == as.character(player_id))
      
      if (length(hitter_idx) == 0) {
        # New hitter - add to log, no report yet
        hitter_log <- rbind(hitter_log, tibble(
          batter = as.character(player_id),
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pa_count = pa_count,
          status = "new",
          notes = ""
        ))
        report <- NULL  # No report yet for new hitters
        
      } else {
        # Hitter exists - add to BIP/PA counts and check for report trigger
        existing_bip <- hitter_log$bip_count[hitter_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- hitter_log$status[hitter_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "new" && new_total_bip >= 100) {
          new_status <- "reported"
          # Generate hitter report with complete hitter history
          full_batter_data <- all_data %>% filter(batter == player_id)
          report <- generate_hitter_report(full_batter_data, player_id)
        }
        
        hitter_log <- hitter_log %>%
          mutate(
            bip_count = if_else(batter == as.character(!!player_id), 
                              new_total_bip, bip_count),
            pa_count = if_else(batter == as.character(!!player_id), 
                             pa_count + !!pa_count, pa_count),
            status = if_else(batter == as.character(!!player_id),
                           new_status, status),
            report_date = if_else(batter == as.character(!!player_id) & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
    }
    
    # Save report (if generated)
    if (!is.null(report)) {
      # Determine report type for filename based on report content
      report_type <- if (grepl("Arsenal", report)) "newprofile" else "performance"
      filename <- sprintf("%s_%s_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         report_type,
                         str_replace_all(as.character(filename_name), " ", "-"))
      filepath <- file.path(OUTPUT_DIR, filename)
      
      writeLines(report, filepath)
      cat("Generated:", filename, "\n")
    }
  }
  
  # Save updated tracking logs
  write_csv(pitcher_log, pitcher_tracking_path)
  write_csv(hitter_log, hitter_tracking_path)
}


generate_trend_reports <- function(players, all_data) {
  # Generates trend analysis reports for players with significant metric changes
  # Only called at beginning of each month
  
  if (nrow(players) == 0) {
    return()
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- players$player_id[i]
    player_name <- players$player_name[i]
    player_type <- players$player_type[i]
    metric_changes <- players$metric_changes[[i]]
    report <- NULL
    
    if (player_type == "pitcher") {
      report <- generate_pitcher_trend_report(player_id, player_name, metric_changes, all_data)
    } else if (player_type == "batter") {
      report <- generate_batter_trend_report(player_id, metric_changes, all_data)
    }
    
    # Save report
    if (!is.null(report)) {
      filename <- sprintf("%s_trend_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         str_replace_all(as.character(player_name), " ", "-"))
      filepath <- file.path(OUTPUT_DIR, filename)
      
      writeLines(report, filepath)
      cat("Generated trend report:", filename, "\n")
    }
  }
}

generate_pitcher_trend_report <- function(pitcher_id, pitcher_name, metric_changes, all_data) {
  # Generates pitcher trend report showing month-over-month changes
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 1
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods
  prev_data <- all_data %>%
    filter(pitcher == pitcher_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(pitcher == pitcher_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= max_game_date)
  
  prev_metrics <- calculate_pitcher_overall_perf(prev_data)
  curr_metrics <- calculate_pitcher_overall_perf(curr_data)
  
  # Thresholds for significance
  thresholds <- list(
    swing_pct = 5.0,
    strike_pct = 5.0,
    zone_pct = 5.0,
    chase_pct = 5.0,
    whiff_pct = 5.0,
    iz_whiff = 5.0,
    oz_whiff = 5.0,
    gb_pct = 5.0,
    hh_pct = 5.0
  )
  
  # Identify significant changes
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "pitches" || metric == "bip") next
    if (abs(metric_changes[[metric]]) >= thresholds[[metric]]) {
      direction <- if (metric_changes[[metric]] > 0) "↑" else "↓"
      significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                              sprintf("%+.1f", metric_changes[[metric]]), "%")
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table
  metrics_table <- "| Metric | Previous | Current | Change |\n|---|---|---|---|\n"
  
  metric_names <- names(metric_changes)
  for (metric in metric_names) {
    if (metric == "pitches" || metric == "bip") next
    
    prev_val <- prev_metrics[[metric]]
    curr_val <- curr_metrics[[metric]]
    delta <- metric_changes[[metric]]
    
    if (is.na(prev_val) || is.na(curr_val)) next
    
    if (grepl("pct", metric)) {
      metrics_table <- paste0(metrics_table,
                             "| ", metric, " | ", prev_val, "% | ", curr_val, "% | ",
                             sprintf("%+.1f", delta), "% |\n")
    } else {
      metrics_table <- paste0(metrics_table,
                             "| ", metric, " | ", prev_val, " | ", curr_val, " | ",
                             sprintf("%+.1f", delta), " |\n")
    }
  }
  
  # Create report content
  report_content <- paste0(
    "# Pitcher Trend Report: ", pitcher_name, "\n\n",
    "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
    "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
    "## Significant Changes\n",
    changes_list, "\n\n",
    "## Detailed Metrics Breakdown\n",
    metrics_table, "\n",
    "## Analysis\n",
    "[Trend analysis pending]\n"
  )
  
  return(report_content)
}

generate_batter_trend_report <- function(batter_id, metric_changes, all_data) {
  # Generates batter trend report showing month-over-month changes
  # Note: batter_name is not available in our data, using batter_id for identification
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 1
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods
  prev_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(batter == batter_id,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= max_game_date)
  
  prev_metrics <- calculate_batter_overall_perf(prev_data)
  curr_metrics <- calculate_batter_overall_perf(curr_data)
  
  # Thresholds for significance
  thresholds <- list(
    swing_pct = 5.0,
    chase_pct = 5.0,
    foul_pct = 5.0,
    whiff_pct = 5.0,
    iz_whiff = 5.0,
    oz_whiff = 5.0,
    gb_pct = 2.5,
    barrel_pct = 2.0,
    hh_pct = 2.5,
    slg = 0.050,
    swspt_pct = 2.5
  )
  
  # Identify significant changes
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "bip") next
    if (abs(metric_changes[[metric]]) >= thresholds[[metric]]) {
      direction <- if (metric_changes[[metric]] > 0) "↑" else "↓"
      if (metric == "slg") {
        significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                                sprintf("%+.3f", metric_changes[[metric]]))
      } else {
        significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                                sprintf("%+.1f", metric_changes[[metric]]), "%")
      }
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table
  metrics_table <- "| Metric | Previous | Current | Change |\n|---|---|---|---|\n"
  
  metric_names <- names(metric_changes)
  for (metric in metric_names) {
    if (metric == "bip") next
    
    prev_val <- prev_metrics[[metric]]
    curr_val <- curr_metrics[[metric]]
    delta <- metric_changes[[metric]]
    
    if (is.na(prev_val) || is.na(curr_val)) next
    
    if (grepl("pct", metric)) {
      metrics_table <- paste0(metrics_table,
                             "| ", metric, " | ", prev_val, "% | ", curr_val, "% | ",
                             sprintf("%+.1f", delta), "% |\n")
    } else if (metric == "slg") {
      metrics_table <- paste0(metrics_table,
                             "| ", metric, " | ", prev_val, " | ", curr_val, " | ",
                             sprintf("%+.3f", delta), " |\n")
    } else {
      metrics_table <- paste0(metrics_table,
                             "| ", metric, " | ", prev_val, " | ", curr_val, " | ",
                             sprintf("%+.1f", delta), " |\n")
    }
  }
  
  # Create report content
  report_content <- paste0(
    "# Batter Trend Report: ", batter_id, "\n\n",
    "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
    "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
    "## Significant Changes\n",
    changes_list, "\n\n",
    "## Detailed Metrics Breakdown\n",
    metrics_table, "\n",
    "## Analysis\n",
    "[Trend analysis pending]\n"
  )
  
  return(report_content)
}

# =============================================================================
# Report Template Population (Pitcher)
# =============================================================================
generate_pitcher_report <- function(pitcher_data, pitcher_name) {
  # Generates pitcher arsenal report (at first appearance)
  
  report <- readLines("templates/new_player_profile_pitcher.md")
  
  # Calculate metrics
  pitch_types <- unique(pitcher_data$pitch_type)
  pitch_metrics_list <- map(pitch_types, ~calculate_pitch_metrics(pitcher_data, .x))
  
  # Create a dataframe with pitch type and overall usage, sort by usage descending
  pitch_summary <- tibble(
    pitch_type = pitch_types,
    usage_pct = map_dbl(pitch_metrics_list, ~.$usage_pct)
  ) %>% arrange(desc(usage_pct))
  
  # Build pitch table with arsenal metrics (sorted by usage)
  pitch_table <- "| Pitch Type | Usage% (RHH) | Usage% (LHH) | Avg Velo | Velo Range | H-Break | V-Break | Spin Rate | Release Side | Release Height |\n|---|---|---|---|---|---|---|---|---|---|\n"
  for (i in seq_len(nrow(pitch_summary))) {
    pt <- pitch_summary$pitch_type[i]
    metrics_overall <- calculate_pitch_metrics(pitcher_data, pt)
    metrics_rhh <- calculate_pitch_metrics(pitcher_data, pt, batter_hand = "R")
    metrics_lhh <- calculate_pitch_metrics(pitcher_data, pt, batter_hand = "L")
    pitch_table <- paste0(pitch_table, 
                         "| ", pt, 
                         " | ", round(metrics_rhh$usage_pct, 1), 
                         " | ", round(metrics_lhh$usage_pct, 1),
                         " | ", metrics_overall$avg_velocity, 
                         " | ", metrics_overall$velo_min, "-", metrics_overall$velo_max,
                         " | ", metrics_overall$hb,
                         " | ", metrics_overall$vb,
                         " | ", metrics_overall$spin,
                         " | ", metrics_overall$rel_side,
                         " | ", metrics_overall$rel_height,
                         " |\n")
  }
  
  # Replace placeholders
  report <- str_replace_all(report, "\\{\\{PLAYER_NAME\\}\\}", as.character(pitcher_name))
  report <- str_replace_all(report, "\\{\\{DATE\\}\\}", format(Sys.Date(), "%B %d, %Y"))
  report <- str_replace_all(report, "\\{\\{PITCH_COUNT\\}\\}", as.character(nrow(pitcher_data)))
  report <- str_replace_all(report, "\\{\\{PITCH_TABLE\\}\\}", pitch_table)
  report <- str_replace_all(report, "\\{\\{SUMMARY_NOTES\\}\\}", "Awaiting analysis...")
  report <- str_replace_all(report, "\\{\\{.*?\\}\\}", "[DATA PENDING]")
  
  return(paste(report, collapse = "\n"))
}

generate_pitcher_performance_report <- function(pitcher_data, pitcher_name, pitcher_id = NULL) {
  # Generates pitcher performance report (at 100+ BIP)
  # Includes overall performance, pitch-level performance, and updated arsenal metrics
  
  # Calculate metrics
  overall_perf <- calculate_pitcher_overall_perf(pitcher_data)
  pitch_perf <- calculate_pitcher_pitch_perf(pitcher_data)
  
  # Calculate percentile ranks if pitcher_id provided
  percentiles_overall <- NULL
  percentiles_pitch <- NULL
  if (!is.null(pitcher_id)) {
    tryCatch({
      percentiles_overall <- calculate_pitcher_overall_percentiles(overall_perf, pitcher_id)
    }, error = function(e) {
      warning("Could not calculate overall percentiles: ", e$message)
    })
    
    tryCatch({
      percentiles_pitch <- calculate_pitcher_pitch_percentiles(pitch_perf, pitcher_id)
    }, error = function(e) {
      warning("Could not calculate pitch percentiles: ", e$message)
    })
  }
  
  # Build performance metrics table with percentile ranks
  perf_table <- "| Metric | Value | Percentile |\n|---|---|---|\n"
  perf_table <- paste0(perf_table,
                       "| Pitches | ", overall_perf$pitches, " | — |\n",
                       "| BIP | ", overall_perf$bip, " | — |\n",
                       "| Swing% | ", overall_perf$swing_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$swing_rank, "th") else "—", " |\n",
                       "| Strike% | ", overall_perf$strike_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$strike_rank, "th") else "—", " |\n",
                       "| Zone% | ", overall_perf$zone_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$zone_rank, "th") else "—", " |\n",
                       "| Chase% | ", overall_perf$chase_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$chase_rank, "th") else "—", " |\n",
                       "| Called Strike% | ", overall_perf$cs_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$cs_rank, "th") else "—", " |\n",
                       "| Foul% | ", overall_perf$foul_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$foul_rank, "th") else "—", " |\n",
                       "| Whiff% | ", overall_perf$whiff_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$whiff_rank, "th") else "—", " |\n",
                       "| IZ Whiff% | ", overall_perf$iz_whiff, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$iz_whiff_rank, "th") else "—", " |\n",
                       "| OZ Whiff% | ", overall_perf$oz_whiff, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$oz_whiff_rank, "th") else "—", " |\n",
                       "| GB% | ", overall_perf$gb_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$gb_rank, "th") else "—", " |\n",
                       "| Hard Hit% | ", overall_perf$hh_pct, "% | ", 
                       if (!is.null(percentiles_overall)) paste0(percentiles_overall$hh_rank, "th") else "—", " |\n")
  
  # Build pitch-level performance table with percentile ranks
  pitch_table <- "| Pitch | Pitches | BIP | Swing% | Strike% | Zone% | Chase% | Whiff% | IZ Whiff% | OZ Whiff% | GB% | HH% |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
  for (i in seq_len(nrow(pitch_perf))) {
    pitch_table <- paste0(pitch_table,
                         "| ", pitch_perf$pitch_type[i], 
                         " | ", pitch_perf$pitches[i],
                         " | ", pitch_perf$bip[i],
                         " | ", pitch_perf$swing_pct[i], "%",
                         " | ", pitch_perf$strike_pct[i], "%",
                         " | ", pitch_perf$zone_pct[i], "%",
                         " | ", pitch_perf$chase_pct[i], "%",
                         " | ", pitch_perf$whiff_pct[i], "%",
                         " | ", pitch_perf$iz_whiff[i], "%",
                         " | ", pitch_perf$oz_whiff[i], "%",
                         " | ", pitch_perf$gb_pct[i], "%",
                         " | ", pitch_perf$hh_pct[i], "% |\n")
  }
  
  # Build updated arsenal metrics
  pitch_types <- unique(pitcher_data$pitch_type)
  arsenal_table <- "| Pitch | Avg Velo | H-Break | V-Break | Spin Rate | Release Side | Release Height |\n|---|---|---|---|---|---|---|\n"
  for (pt in pitch_types) {
    metrics <- calculate_pitch_metrics(pitcher_data, pt)
    arsenal_table <- paste0(arsenal_table,
                           "| ", pt,
                           " | ", metrics$avg_velocity,
                           " | ", metrics$hb,
                           " | ", metrics$vb,
                           " | ", metrics$spin,
                           " | ", metrics$rel_side,
                           " | ", metrics$rel_height, " |\n")
  }
  
  # Create performance report content
  report_content <- paste0(
    "# Pitcher Performance Report: ", pitcher_name, "\n\n",
    "**Report Date:** ", format(Sys.Date(), "%B %d, %Y"), "\n",
    "**Sample Size:** ", overall_perf$pitches, " pitches\n\n",
    "## Overall Performance\n",
    perf_table, "\n",
    "## Pitch-Level Performance\n",
    pitch_table, "\n",
    "## Arsenal Metrics (Updated)\n",
    arsenal_table, "\n",
    "## Analysis\n",
    "[Performance analysis pending]\n"
  )
  
  return(report_content)
}

# =============================================================================
# Report Template Population (Hitter)
# =============================================================================

generate_hitter_report <- function(batter_data, batter_id) {
  # Generates hitter performance report (at 100+ BIP)
  # Includes overall performance, zone performance, and batter profile
  
  # Calculate metrics
  overall_perf <- calculate_batter_overall_perf(batter_data)
  zone_perf <- calculate_batter_zone_perf(batter_data)
  profile <- calculate_batter_profile(batter_data)
  
  # Calculate percentile ranks
  percentiles_overall <- NULL
  percentiles_zone <- NULL
  percentiles_profile <- NULL
  tryCatch({
    percentiles_overall <- calculate_batter_overall_percentiles(overall_perf, batter_id)
  }, error = function(e) {
    warning("Could not calculate overall percentiles: ", e$message)
  })
  
  tryCatch({
    percentiles_zone <- calculate_batter_zone_percentiles(zone_perf, batter_id)
  }, error = function(e) {
    warning("Could not calculate zone percentiles: ", e$message)
  })
  
  tryCatch({
    percentiles_profile <- calculate_batter_profile_percentiles(profile, batter_id)
  }, error = function(e) {
    warning("Could not calculate profile percentiles: ", e$message)
  })
  
  # Get batter name
  batter_name <- batter_data$player_name[1]
  if (is.na(batter_name)) {
    batter_name <- as.character(batter_id)
  }
  
  # Build overall performance table with percentile ranks
  overall_table <- "| Stat | Value | Percentile |\n|---|---|---|\n"
  overall_table <- paste0(overall_table,
                         "| Swing% | ", overall_perf$swing_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$swing_rank, "th") else "—", " |\n",
                         "| Chase% | ", overall_perf$chase_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$chase_rank, "th") else "—", " |\n",
                         "| Foul% | ", overall_perf$foul_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$foul_rank, "th") else "—", " |\n",
                         "| Whiff% | ", overall_perf$whiff_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$whiff_rank, "th") else "—", " |\n",
                         "| IZ Whiff% | ", overall_perf$iz_whiff, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$iz_whiff_rank, "th") else "—", " |\n",
                         "| OZ Whiff% | ", overall_perf$oz_whiff, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$oz_whiff_rank, "th") else "—", " |\n",
                         "| BIP | ", overall_perf$bip, " | — |\n",
                         "| GB% | ", overall_perf$gb_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$gb_rank, "th") else "—", " |\n",
                         "| Barrel% | ", overall_perf$barrel_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$barrel_rank, "th") else "—", " |\n",
                         "| Hard Hit% | ", overall_perf$hh_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$hh_rank, "th") else "—", " |\n",
                         "| SLG (contact) | ", overall_perf$slg, " | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$slg_rank, "th") else "—", " |\n",
                         "| Sweet Spot% | ", overall_perf$swspt_pct, "% | ", 
                         if (!is.null(percentiles_overall)) paste0(percentiles_overall$swspt_rank, "th") else "—", " |\n")
  
  # Build zone performance table (simplified without percentiles for zone breakdowns)
  zone_table <- "| Location | BIP | Swing% | Chase% | Foul% | Whiff% | IZ Whiff% | OZ Whiff% | GB% | HH% | SLGcon | Sweet Spot% |\n|---|---|---|---|---|---|---|---|---|---|---|---|\n"
  for (i in seq_len(nrow(zone_perf))) {
    zone_table <- paste0(zone_table,
                        "| ", zone_perf$Location[i],
                        " | ", zone_perf$BIP[i],
                        " | ", zone_perf$`Swing%`[i], "%",
                        " | ", zone_perf$`Chase%`[i], "%",
                        " | ", zone_perf$`Foul%`[i], "%",
                        " | ", zone_perf$`Whiff%`[i], "%",
                        " | ", zone_perf$`IZ Whiff`[i], "%",
                        " | ", zone_perf$`OZ Whiff`[i], "%",
                        " | ", zone_perf$`GB%`[i], "%",
                        " | ", zone_perf$`HH%`[i], "%",
                        " | ", zone_perf$`SLGcon`[i],
                        " | ", zone_perf$`Sweet Spot%`[i], "% |\n")
  }
  
  # Build profile metrics summary with percentile ranks
  profile_summary <- if (!is.null(profile)) {
    paste0("**Batted Ball Events:** ", profile$bbe, "\n",
           "**Avg Launch Angle:** ", profile$avg_la, "° ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$avg_la_rank, "th percentile)") else "", "\n",
           "**LA Std Dev:** ", profile$la_std_dev, 
           if (!is.null(percentiles_profile)) paste0(" (", percentiles_profile$la_std_rank, "th percentile)") else "", "\n",
           "**Sweet Spot%:** ", profile$sweet_spot_pct, "% ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$swspt_rank, "th percentile)") else "", "\n",
           "**Hard Hit LA:** ", profile$hh_la, "° ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$hh_la_rank, "th percentile)") else "", "\n",
           "**Oppo FB%:** ", profile$oppo_fb_pct, "% ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$oppo_fb_pct_rank, "th percentile)") else "", "\n",
           "**Oppo FB EV:** ", profile$oppo_fb_ev, " mph ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$oppo_fb_ev_rank, "th percentile)") else "", "\n",
           "**High Attack Angle%:** ", profile$high_aa_pct, "% ", 
           if (!is.null(percentiles_profile)) paste0("(", percentiles_profile$high_aa_rank, "th percentile)") else "", "\n")
  } else {
    "Profile data pending\n"
  }
  
  # Create hitter report content
  report_content <- paste0(
    "# Hitter Performance Report: ", batter_name, "\n\n",
    "**Report Date:** ", format(Sys.Date(), "%B %d, %Y"), "\n",
    "**Sample Size:** ", overall_perf$bip, " balls in play\n\n",
    "## Overall Performance\n",
    overall_table, "\n",
    "## Zone Performance\n",
    zone_table, "\n",
    "## Batter Profile (Swing Quality & Mechanics)\n",
    profile_summary, "\n",
    "## Analysis\n",
    "[Performance analysis pending]\n"
  )
  
  return(report_content)
}

# =============================================================================
# Run Pipeline
# =============================================================================

if (sys.nframe() == 0) {
  # Script is being run directly (not sourced)
  process_weekly_data()
}
