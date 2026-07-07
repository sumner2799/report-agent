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
  
  # Separate MLB and MiLB files
  mlb_files <- raw_files[grepl("^.*statcast_.*\\.csv$", basename(raw_files), ignore.case = TRUE)]
  milb_files <- raw_files[grepl("^.*(minorleague|mnl)_.*\\.csv$", basename(raw_files), ignore.case = TRUE)]
  
  # Load and process MLB data (separate)
  mlb_all_data <- tibble()
  mlb_statcast_data <- tibble()
  
  if (length(mlb_files) > 0) {
    cat("Loading MLB data from", length(mlb_files), "file(s)...\n")
    mlb_all_data <- map_df(mlb_files, ~read_csv(., show_col_types = FALSE) %>% 
                         mutate(level = "MLB", .before = 1))
    
    # Get MLB player names (batter names) using mlb_sports_players
    cat("Fetching MLB player names...\n")
    tryCatch({
      players <- mlb_sports_players(sport_id = 1, season = 2026)
      mlb_all_data <- left_join(mlb_all_data, 
                           players %>% select(player_id, last_first_name),
                           by = c("batter" = "player_id"))
    }, error = function(e) {
      warning("Could not fetch MLB player names: ", e$message)
    })
    
    latest_mlb <- mlb_files[which.max(file.info(mlb_files)$mtime)]
    mlb_statcast_data <- read_csv(latest_mlb, show_col_types = FALSE) %>%
      mutate(level = "MLB", .before = 1)
    
    # Add player names to mlb_statcast_data as well
    tryCatch({
      players <- mlb_sports_players(sport_id = 1, season = 2026)
      mlb_statcast_data <- left_join(mlb_statcast_data, 
                                players %>% select(player_id, last_first_name),
                                by = c("batter" = "player_id"))
    }, error = function(e) {
      warning("Could not fetch MLB player names for latest data: ", e$message)
    })
  }
  
  # Load and process MiLB data (separate)
  milb_all_data <- tibble()
  milb_statcast_data <- tibble()
  
  if (length(milb_files) > 0) {
    cat("Loading MiLB data from", length(milb_files), "file(s)...\n")
    milb_all_data <- map_df(milb_files, ~normalize_milb_data(read_csv(., show_col_types = FALSE)))
    
    latest_milb <- milb_files[which.max(file.info(milb_files)$mtime)]
    milb_statcast_data <- normalize_milb_data(read_csv(latest_milb, show_col_types = FALSE))
  }
  
  if (nrow(mlb_all_data) == 0 && nrow(milb_all_data) == 0) {
    stop("No valid data loaded from MLB or MiLB files.")
  }
  
  # Get max game_date from each dataset (separate)
  mlb_max_game_date <- if (nrow(mlb_all_data) > 0) max(as.Date(mlb_all_data$game_date), na.rm = TRUE) else as.Date("1970-01-01")
  milb_max_game_date <- if (nrow(milb_all_data) > 0) max(as.Date(milb_all_data$game_date), na.rm = TRUE) else as.Date("1970-01-01")
  
  # Use the most recent game date overall for analysis cutoffs
  max_game_date <- max(mlb_max_game_date, milb_max_game_date)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  
  cat("MLB data loaded. Latest game date:", mlb_max_game_date, "\n")
  cat("MiLB data loaded. Latest game date:", milb_max_game_date, "\n")
  
  # 2. Validate and clean data
  # statcast_data <- validate_statcast(statcast_data)

  # Load tracking logs for trend identification (now include 'level' column)
  pitcher_tracking_path <- ".system/pitcher_tracking_log.csv"
  if (file.exists(pitcher_tracking_path)) {
    pitcher_log <- read_csv(pitcher_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(pitcher_log)) {
      pitcher_log <- pitcher_log %>% mutate(level = "MLB", .after = pitcher_name)
    }
  } else {
    pitcher_log <- tibble(pitcher_name = character(), level = character(), 
                         report_date = character(), bip_count = numeric(), 
                         pitch_count = numeric(), status = character(), notes = character())
  }
  
  hitter_tracking_path <- ".system/hitter_tracking_log.csv"
  if (file.exists(hitter_tracking_path)) {
    hitter_log <- read_csv(hitter_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(hitter_log)) {
      hitter_log <- hitter_log %>% mutate(level = "MLB", .after = batter)
    }
  } else {
    hitter_log <- tibble(batter = character(), level = character(), 
                        report_date = character(), bip_count = numeric(), 
                        pa_count = numeric(), status = character(), notes = character())
  }

  # 3. Segment by player type and identify reportable players (process each league separately)
  
  # Process MLB data
  if (nrow(mlb_statcast_data) > 0) {
    cat("Processing MLB data...\n")
    mlb_new_players <- identify_new_players(mlb_statcast_data)
    mlb_trend_candidates <- identify_trend_players(mlb_all_data, pitcher_log, hitter_log)
    
    if (nrow(mlb_new_players) > 0) {
      generate_new_player_reports(mlb_new_players, mlb_statcast_data, mlb_all_data, max_game_date)
    }
    
    if (nrow(mlb_trend_candidates) > 0) {
      generate_trend_reports(mlb_trend_candidates, mlb_all_data)
    }
  }
  
  # Process MiLB data
  if (nrow(milb_statcast_data) > 0) {
    cat("Processing MiLB data...\n")
    milb_new_players <- identify_new_players_milb(milb_statcast_data)
    milb_trend_candidates <- identify_trend_players_mnl(milb_all_data, pitcher_log, hitter_log)
    
    if (nrow(milb_new_players) > 0) {
      generate_new_player_reports_milb(milb_new_players, milb_statcast_data, milb_all_data, max_game_date)
    }
    
    if (nrow(milb_trend_candidates) > 0) {
      generate_trend_reports_mnl(milb_trend_candidates, milb_all_data)
    }
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
# MiLB Data Normalization
# =============================================================================

normalize_milb_data <- function(milb_raw) {
  # Normalizes MiLB data to match MLB field structure
  # Extracts league level from data and creates standardized field names
  
  # Extract league level (AAA, AA, A+, etc.) from home_level_name or level column
  if ("home_level_name" %in% colnames(milb_raw)) {
    level <- unique(milb_raw$home_level_name)[1]
  } else if ("level" %in% colnames(milb_raw)) {
    level <- unique(milb_raw$level)[1]
  } else {
    level <- "AAA"  # Default fallback
  }
  
  # Normalize field names to match MLB Statcast format
  milb_normalized <- milb_raw %>%
    mutate(
      # Player IDs and names
      pitcher = matchup.pitcher.id,
      pitcher_name = matchup.pitcher.fullName,
      batter = matchup.batter.id,
      player_name = matchup.batter.fullName,
      
      # Game info
      game_date = as.Date(game_date),
      
      # Pitch mechanics
      pitch_type = details.type.description,
      pitch_x = pitchData.coordinates.pX,
      pitch_z = pitchData.coordinates.pZ,
      plate_x = hitData.coordinates.coordX,
      plate_z = hitData.coordinates.coordY,
      release_speed = pitchData.startSpeed,
      release_x = 0,  # Not consistently available in MiLB
      release_z = 0,  # Not consistently available in MiLB
      
      # Ball in play mechanics
      launch_speed = hitData.launchSpeed,
      launch_angle = hitData.launchAngle,
      bb_type = hitData.trajectory,
      
      # Call results
      description = details.call.description,
      is_bip = details.isInPlay,
      result_type = result.eventType,
      
      # Pitch characteristics
      hb = pitchData.breaks.breakHorizontal,
      vb = pitchData.breaks.breakVerticalInduced,
      spin = pitchData.breaks.spinRate,
      
      # Strike zone
      sz_bot = pitchData.strikeZoneBottom,
      sz_top = pitchData.strikeZoneTop,
      
      # Add level designation
      level = level
    ) %>%
    select(level, pitcher, pitcher_name, batter, player_name, game_date, pitch_type,
           pitch_x, pitch_z, plate_x, plate_z, release_speed, release_x, release_z,
           launch_speed, launch_angle, bb_type, description, is_bip, result_type,
           hb, vb, spin, sz_bot, sz_top, everything())
  
  return(milb_normalized)
}

# =============================================================================
# Team Extraction Helpers
# =============================================================================

get_pitcher_team_mlb <- function(pitcher_data) {
  # Extracts pitcher's team based on inning_topbot
  # If pitcher throws in "Top" inning, pitcher's team is home_team
  # If pitcher throws in "Bot" inning, pitcher's team is away_team
  
  if (nrow(pitcher_data) == 0) return(NA_character_)
  
  first_row <- pitcher_data %>% dplyr::slice(1)
  inning_topbot <- first_row$inning_topbot[1]
  
  if (inning_topbot == "Top") {
    return(first_row$home_team[1])
  } else {
    return(first_row$away_team[1])
  }
}

get_batter_team_mlb <- function(batter_data) {
  # Extracts batter's team based on inning_topbot
  # If batter hits in "Top" inning, batter's team is away_team
  # If batter hits in "Bot" inning, batter's team is home_team
  
  if (nrow(batter_data) == 0) return(NA_character_)
  
  first_row <- batter_data %>% dplyr::slice(1)
  inning_topbot <- first_row$inning_topbot[1]
  
  if (inning_topbot == "Top") {
    return(first_row$away_team[1])
  } else {
    return(first_row$home_team[1])
  }
}

get_pitcher_team_milb <- function(pitcher_data) {
  # Extracts pitcher's team based on about.halfInning
  # If pitcher throws in "top" inning, pitcher's team is home_parentOrg_name
  # If pitcher throws in "bottom" inning, pitcher's team is away_parentOrg_name
  
  if (nrow(pitcher_data) == 0) return(NA_character_)
  
  first_row <- pitcher_data %>% dplyr::slice(1)
  half_inning <- tolower(first_row$about.halfInning[1])
  
  if (half_inning == "top") {
    return(first_row$home_parentOrg_name[1])
  } else {
    return(first_row$away_parentOrg_name[1])
  }
}

get_batter_team_milb <- function(batter_data) {
  # Extracts batter's team based on about.halfInning
  # If batter hits in "top" inning, batter's team is away_parentOrg_name
  # If batter hits in "bottom" inning, batter's team is home_parentOrg_name
  
  if (nrow(batter_data) == 0) return(NA_character_)
  
  first_row <- batter_data %>% dplyr::slice(1)
  half_inning <- tolower(first_row$about.halfInning[1])
  
  if (half_inning == "top") {
    return(first_row$away_parentOrg_name[1])
  } else {
    return(first_row$home_parentOrg_name[1])
  }
}

# =============================================================================
# Player Identification
# =============================================================================
# data <- statcast_data
identify_new_players <- function(data) {
  # Identifies new players that meet sample size threshold
  # Tracks players separately by level (MLB, AAA, AA, etc.)
  # THRESHOLD: Placeholder - will be calibrated after first reports
  
  MIN_SAMPLE <- 50  # Starting threshold
  
  new_pitchers <- data %>%
    group_by(pitcher, player_name) %>%
    summarise(pitch_count = n(), .groups = "drop") %>%
    filter(pitch_count >= MIN_SAMPLE) %>%
    select(pitcher, player_name, pitch_count)
  
  new_batters <- data %>%
    group_by(batter, last_first_name) %>%
    summarise(pa_count = n(), .groups = "drop") %>%
    filter(pa_count >= MIN_SAMPLE) %>%
    select(batter, last_first_name, pa_count)
  
  return(bind_rows(
    new_pitchers %>% mutate(player_type = "pitcher"),
    new_batters %>% mutate(player_type = "batter")
  ))
}

identify_new_players_milb <- function(data) {
  # Identifies new players that meet sample size threshold
  # Tracks players separately by level (MLB, AAA, AA, etc.)
  # THRESHOLD: Placeholder - will be calibrated after first reports
  
  MIN_SAMPLE <- 50  # Starting threshold
  
  new_pitchers <- data %>%
    group_by(matchup.pitcher.id, matchup.pitcher.fullName, home_level_name) %>%
    summarise(pitch_count = n(), .groups = "drop") %>%
    filter(pitch_count >= MIN_SAMPLE) %>%
    select(matchup.pitcher.id, matchup.pitcher.fullName, home_level_name, pitch_count)
  
  new_batters <- data %>%
    group_by(matchup.batter.id, matchup.batter.fullName, home_level_name) %>%
    summarise(pa_count = n(), .groups = "drop") %>%
    filter(pa_count >= MIN_SAMPLE) %>%
    select(matchup.batter.id, matchup.batter.fullName, home_level_name, pa_count)
  
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
  # Tracks players separately by level (MLB, AAA, AA, etc.)
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
      player_name = character(),
      level = character()
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
    level = character(),
    metric_changes = list()
  )
  
  # Evaluate eligible pitchers (filter by level to maintain level separation)
  eligible_pitchers <- pitcher_log %>%
    filter(status == "performance_reported", level == "MLB") %>%
    select(pitcher_name, level)
  
  for (i in seq_len(nrow(eligible_pitchers))) {
    pitcher_name <- eligible_pitchers$pitcher_name[i]
    pitcher_level <- eligible_pitchers$level[i]
    
    # Skip if performance report was just generated in the data month
    pitcher_report_date <- pitcher_log %>%
      filter(pitcher_name == !!pitcher_name & level == !!pitcher_level) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(pitcher_report_date)) == data_month &&
        year(as.Date(pitcher_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }

    pitcher_id <- all_data %>%
        filter(player_name == !!pitcher_name) %>%
        pull(pitcher) %>%
        unique() %>%
        first()
    
    if (is.na(pitcher_id)) next
    
    # Aggregate pitcher data for comparison at this specific level
    result <- compare_pitcher_trend(pitcher_id, pitcher_name, pitcher_level, prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  # Evaluate eligible hitters (filter by level to maintain level separation)
  eligible_hitters <- hitter_log %>%
    filter(status == "reported", level == "MLB") %>%
    select(batter, level)
  
  for (i in seq_len(nrow(eligible_hitters))) {
    batter_id <- eligible_hitters$batter[i]
    batter_level <- eligible_hitters$level[i]
    
    # Skip if performance report was just generated in the data month
    hitter_report_date <- hitter_log %>%
      filter(batter == !!batter_id & level == !!batter_level) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(hitter_report_date)) == data_month &&
        year(as.Date(hitter_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }
    
    # Aggregate hitter data for comparison at this specific level
    result <- compare_batter_trend(as.numeric(batter_id), batter_level, prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  return(trend_players)
}

identify_trend_players_mnl <- function(all_data, pitcher_log, hitter_log) {
  # Identifies existing players with significant KPI changes month-over-month
  # Tracks players separately by level (MLB, AAA, AA, etc.)
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
      player_name = character(),
      level = character()
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
    level = character(),
    metric_changes = list()
  )
  
  # Evaluate eligible pitchers (filter by level to maintain level separation)
  eligible_pitchers <- pitcher_log %>%
    filter(status == "performance_reported", level != "MLB") %>%
    select(pitcher_name, level)
  
  for (i in seq_len(nrow(eligible_pitchers))) {
    pitcher_name <- eligible_pitchers$pitcher_name[i]
    pitcher_level <- eligible_pitchers$level[i]
    
    # Skip if performance report was just generated in the data month
    pitcher_report_date <- pitcher_log %>%
      filter(pitcher_name == !!pitcher_name & level == !!pitcher_level) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(pitcher_report_date)) == data_month &&
        year(as.Date(pitcher_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }

    pitcher_id <- all_data %>%
        filter(matchup.pitcher.fullName == !!pitcher_name, home_level_name == !!pitcher_level) %>%
        pull(matchup.pitcher.id) %>%
        unique() %>%
        first()
    
    if (is.na(pitcher_id)) next
    
    # Aggregate pitcher data for comparison at this specific level
    result <- compare_pitcher_trend(pitcher_id, pitcher_name, pitcher_level, prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  # Evaluate eligible hitters (filter by level to maintain level separation)
  eligible_hitters <- hitter_log %>%
    filter(status == "reported", level != "MLB") %>%
    select(batter, level)
  
  for (i in seq_len(nrow(eligible_hitters))) {
    batter_id <- eligible_hitters$batter[i]
    batter_level <- eligible_hitters$level[i]
    
    # Skip if performance report was just generated in the data month
    hitter_report_date <- hitter_log %>%
      filter(batter == !!batter_id & level == !!batter_level) %>%
      pull(report_date) %>%
      first()
    
    if (month(as.Date(hitter_report_date)) == data_month &&
        year(as.Date(hitter_report_date)) == data_year) {
      # Performance report generated in data month, skip trend analysis
      next
    }
    
    # Aggregate hitter data for comparison at this specific level
    result <- compare_batter_trend(as.numeric(batter_id), batter_level, prev_period_end, curr_period_end, all_data, data_month, data_year)
    if (!is.null(result)) {
      trend_players <- rbind(trend_players, result)
    }
  }
  
  return(trend_players)
}

compare_pitcher_trend <- function(pitcher_id, pitcher_name, pitcher_level, prev_period_end, curr_period_end, all_data, data_month, data_year) {
  # Compares pitcher performance: previous month vs current month (full months only)
  # Filters by level to maintain separate tracking
  # Exclusion: don't include if first perf report was in the data month
  # Returns tibble if significant changes detected, NULL otherwise
  
  year_start <- paste0(data_year, "-01-01")
  
  # Previous period: start of year through end of two months before current data month (at this level)

  if (pitcher_level == "MLB") {
    prev_data <- all_data %>%
    filter(pitcher == pitcher_id, level == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end)
  } else {
    prev_data <- all_data %>%
    filter(matchup.pitcher.id == pitcher_id, home_level_name == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end)
  }
  
  # Current period: start of year through end of one month before current data month (at this level)

  if (pitcher_level == "MLB") {
    curr_data <- all_data %>%
    filter(pitcher == pitcher_id, level == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  } else {
    curr_data <- all_data %>%
    filter(matchup.pitcher.id == pitcher_id, home_level_name == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  }
  
  if (nrow(prev_data) < 50 || nrow(curr_data) < 50) {
    # Not enough data for reliable comparison
    return(NULL)
  }
  
  # Calculate metrics for both periods using appropriate function based on level
  if (pitcher_level == "MLB") {
    prev_metrics <- calculate_pitcher_overall_perf(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_pitcher_overall_perf_milb(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf_milb(curr_data)
  }
  
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
  
  # Calculate pitcher arsenal metrics for both periods
  # Get unique pitch types and calculate metrics per pitch
  tryCatch({
    pitch_types <- unique(curr_data$pitch_type)
    pitch_types <- pitch_types[!is.na(pitch_types)]
    
    arsenal_deltas <- list()
    
    for (pitch in pitch_types) {
      prev_pitch_metrics <- calculate_pitch_metrics(prev_data, pitch)
      curr_pitch_metrics <- calculate_pitch_metrics(curr_data, pitch)
      
      # Store deltas with pitch identifier
      arsenal_deltas[[paste0(pitch, "_velo")]] <- list(
        pitch = pitch,
        metric = "velo",
        delta = curr_pitch_metrics$avg_velocity - prev_pitch_metrics$avg_velocity,
        prev_val = prev_pitch_metrics$avg_velocity,
        curr_val = curr_pitch_metrics$avg_velocity
      )
      arsenal_deltas[[paste0(pitch, "_hb")]] <- list(
        pitch = pitch,
        metric = "hb",
        delta = curr_pitch_metrics$hb - prev_pitch_metrics$hb,
        prev_val = prev_pitch_metrics$hb,
        curr_val = curr_pitch_metrics$hb
      )
      arsenal_deltas[[paste0(pitch, "_vb")]] <- list(
        pitch = pitch,
        metric = "vb",
        delta = curr_pitch_metrics$vb - prev_pitch_metrics$vb,
        prev_val = prev_pitch_metrics$vb,
        curr_val = curr_pitch_metrics$vb
      )
      arsenal_deltas[[paste0(pitch, "_rel_side")]] <- list(
        pitch = pitch,
        metric = "rel_side",
        delta = curr_pitch_metrics$rel_side - prev_pitch_metrics$rel_side,
        prev_val = prev_pitch_metrics$rel_side,
        curr_val = curr_pitch_metrics$rel_side
      )
      arsenal_deltas[[paste0(pitch, "_rel_height")]] <- list(
        pitch = pitch,
        metric = "rel_height",
        delta = curr_pitch_metrics$rel_height - prev_pitch_metrics$rel_height,
        prev_val = prev_pitch_metrics$rel_height,
        curr_val = curr_pitch_metrics$rel_height
      )
    }
    
    # Add arsenal deltas to the main list
    metric_deltas$arsenal <- arsenal_deltas
  }, error = function(e) {
    # If arsenal calculation fails, just continue without it
    NULL
  })
  
  # Calibrated thresholds for pitcher trend detection
  thresholds <- list(
    swing_pct = 0.92,
    strike_pct = 0.80,
    zone_pct = 0.94,
    chase_pct = 1.17,
    whiff_pct = 1.39,
    iz_whiff = 1.43,
    oz_whiff = 2.22,
    gb_pct = 2.23,
    hh_pct = 1.62,
    # Arsenal thresholds
    velo = 2.0,
    hb = 3.0,
    vb = 3.0,
    rel_side = 0.2,
    rel_height = 0.2
  )
  
  # Check if any metric has significant change
  significant_changes <- map_lgl(names(metric_deltas), ~{
    if (.x == "arsenal") {
      # Check if any pitch meets arsenal thresholds
      return(any(map_lgl(metric_deltas$arsenal, ~{
        if (!(.x$metric %in% names(thresholds))) return(FALSE)
        delta_val <- .x$delta
        if (length(delta_val) != 1) return(FALSE)
        if (is.na(delta_val)) return(FALSE)
        abs(delta_val) >= thresholds[[.x$metric]]
      }), na.rm = TRUE))
    } else {
      if (!(.x %in% names(thresholds))) return(FALSE)
      delta_val <- metric_deltas[[.x]]
      if (length(delta_val) != 1) return(FALSE)
      if (is.na(delta_val)) return(FALSE)
      return(abs(delta_val) >= thresholds[[.x]])
    }
  })
  
  if (any(significant_changes, na.rm = TRUE)) {
    return(tibble(
      player_id = pitcher_id,
      player_name = pitcher_name,
      player_type = "pitcher",
      level = pitcher_level,
      metric_changes = list(metric_deltas)
    ))
  }
  
  return(NULL)
}

compare_batter_trend <- function(batter_id, batter_level, prev_period_end, curr_period_end, all_data, data_month, data_year) {
  # Compares batter performance: previous month vs current month (full months only)
  # Filters by level to maintain separate tracking
  # Exclusion: don't include if first perf report was in the data month
  # Returns tibble if significant changes detected, NULL otherwise
  
  year_start <- paste0(data_year, "-01-01")
  if (batter_level == "MLB") {
    batter_name <- all_data %>% filter(batter == batter_id) %>% pull(last_first_name) %>% first()
  } else {
    batter_name <- all_data %>% filter(matchup.batter.id == batter_id) %>% pull(matchup.batter.fullName) %>% first()
  }
  
  # Previous period: start of year through end of two months before current data month (at this level)

  if (batter_level == "MLB") {
    prev_data <- all_data %>%
    filter(batter == batter_id, level == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end)
  } else {
    prev_data <- all_data %>%
    filter(matchup.batter.id == batter_id, home_level_name == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_period_end
           )
  }
  
  # Current period: start of year through end of one month before current data month (at this level)
  
  
  if (batter_level == "MLB") {
    curr_data <- all_data %>%
    filter(batter == batter_id, level == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  } else {
    curr_data <- all_data %>%
    filter(matchup.batter.id == batter_id, home_level_name == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= curr_period_end)
  }
  
  if (nrow(prev_data) < 50 || nrow(curr_data) < 50) {
    # Not enough data for reliable comparison
    return(NULL)
  }
  
  # Calculate metrics for both periods using appropriate function based on level
  if (batter_level == "MLB") {
    prev_metrics <- calculate_batter_overall_perf(prev_data)
    curr_metrics <- calculate_batter_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_batter_overall_perf_milb(prev_data)
    curr_metrics <- calculate_batter_overall_perf_milb(curr_data)
  }
  
  # Calculate deltas (current - previous)
  metric_deltas <- list(
    swing_pct = curr_metrics$swing_pct - prev_metrics$swing_pct,
    chase_pct = curr_metrics$chase_pct - prev_metrics$chase_pct,
    foul_pct = curr_metrics$foul_pct - prev_metrics$foul_pct,
    whiff_pct = curr_metrics$whiff_pct - prev_metrics$whiff_pct,
    iz_whiff = curr_metrics$iz_whiff - prev_metrics$iz_whiff,
    oz_whiff = curr_metrics$oz_whiff - prev_metrics$oz_whiff,
    gb_pct = curr_metrics$gb_pct - prev_metrics$gb_pct,
    # barrel_pct = curr_metrics$barrel_pct - prev_metrics$barrel_pct,
    hh_pct = curr_metrics$hh_pct - prev_metrics$hh_pct,
    slg = curr_metrics$slg - prev_metrics$slg,
    swspt_pct = curr_metrics$swspt_pct - prev_metrics$swspt_pct
  )
  
  # Calculate batter profile metrics for both periods
  # Filter to balls in play only for profile calculations
  tryCatch({
    prev_bip_data <- prev_data
    curr_bip_data <- curr_data
    
    if (nrow(prev_bip_data) >= 10 && nrow(curr_bip_data) >= 10) {
      if (batter_level == "MLB") {
        prev_profile <- calculate_batter_profile(prev_bip_data)
        curr_profile <- calculate_batter_profile(curr_bip_data)
      } else {
        prev_profile <- calculate_batter_profile_milb(prev_bip_data)
        curr_profile <- calculate_batter_profile_milb(curr_bip_data)
      }
      
      # Add profile deltas to metric_deltas
      metric_deltas$avg_la = curr_profile$avg_la - prev_profile$avg_la
      metric_deltas$la_std_dev = curr_profile$la_std_dev - prev_profile$la_std_dev
      metric_deltas$hh_la = curr_profile$hh_la - prev_profile$hh_la
      metric_deltas$oppo_fb_pct = curr_profile$oppo_fb_pct - prev_profile$oppo_fb_pct
      metric_deltas$oppo_fb_ev = curr_profile$oppo_fb_ev - prev_profile$oppo_fb_ev
      metric_deltas$high_aa_pct = curr_profile$high_aa_pct - prev_profile$high_aa_pct
    }
  }, error = function(e) {
    # If profile calculation fails, just continue without it
    NULL
  })
  
  # Calibrated thresholds for batter trend detection
  thresholds <- list(
    swing_pct = 1.93,
    chase_pct = 2.31,
    foul_pct = 2.17,
    whiff_pct = 2.16,
    iz_whiff = 2.24,
    oz_whiff = 3.66,
    gb_pct = 3.95,
    barrel_pct = 2.0,
    hh_pct = 3.48,
    slg = 0.075,
    swspt_pct = 3.64,
    # Profile thresholds
    avg_la = 2.20,
    la_std_dev = 1.53,
    hh_la = 2.18,
    oppo_fb_pct = 6.80,
    oppo_fb_ev = 2.45,
    high_aa_pct = 8.50
  )
  
  # Check if any metric has significant change
  significant_changes <- map_lgl(names(metric_deltas), ~{
    if (.x %in% names(thresholds)) {
      delta_val <- metric_deltas[[.x]]
      if (length(delta_val) != 1) return(FALSE)
      if (is.na(delta_val)) return(FALSE)
      return(abs(delta_val) >= thresholds[[.x]])
    }
    return(FALSE)
  })
  
  if (any(significant_changes, na.rm = TRUE)) {
    return(tibble(
      player_id = batter_id,
      player_name = batter_name,  
      player_type = "batter",
      level = batter_level,
      metric_changes = list(metric_deltas)
    ))
  }
  
  return(NULL)
}
# (mlb_new_players, mlb_statcast_data, mlb_all_data, max_game_date)
# players <- mlb_new_players
# data <- mlb_statcast_data
# all_data <- mlb_all_data
# =============================================================================
# Report Generation
# =============================================================================
generate_new_player_reports <- function(players, data, all_data, max_game_date) {
  # Generates new player profile reports
  # Tracks players separately by level (MLB, AAA, AA, etc.)
  # data = current batch data (for identification)
  # all_data = full historical data (for performance report calculations)
  
  # Load or initialize pitcher tracking log
  pitcher_tracking_path <- ".system/pitcher_tracking_log.csv"
  if (file.exists(pitcher_tracking_path)) {
    pitcher_log <- read_csv(pitcher_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(pitcher_log)) {
      pitcher_log <- pitcher_log %>% mutate(level = "MLB", .after = pitcher_name)
    }
  } else {
    pitcher_log <- tibble(pitcher_name = character(), level = character(), 
                         report_date = character(), bip_count = numeric(), 
                         pitch_count = numeric(), status = character(), notes = character())
  }
  
  # Load or initialize hitter tracking log
  hitter_tracking_path <- ".system/hitter_tracking_log.csv"
  if (file.exists(hitter_tracking_path)) {
    hitter_log <- read_csv(hitter_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(hitter_log)) {
      hitter_log <- hitter_log %>% mutate(level = "MLB", .after = batter)
    }
  } else {
    hitter_log <- tibble(batter = character(), level = character(), 
                        report_date = character(), bip_count = numeric(), 
                        pa_count = numeric(), status = character(), notes = character())
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- if (!is.na(players$pitcher[i])) players$pitcher[i] else players$batter[i]
    player_type <- players$player_type[i]
    
    if (player_type == "pitcher") {
      # Filter data by both pitcher ID AND level
      pitcher_data <- data %>% filter(pitcher == player_id)
      pitcher_name <- pitcher_data$player_name[1]
      player_level <- "MLB"
      filename_name <- pitcher_name
      report <- NULL  # Initialize report as NULL
      
      # Calculate BIP and pitch count
      bip_count <- calculate_pitcher_bip(pitcher_data)
      pitch_count <- nrow(pitcher_data)
      
      # Determine pitcher status and generate appropriate report
      # Check for existing pitcher at this SPECIFIC LEVEL
      pitcher_idx <- which(pitcher_log$pitcher_name == pitcher_name & pitcher_log$level == "MLB")
      
      if (length(pitcher_idx) == 0) {
        # New pitcher at this level - add to log and generate arsenal report
        pitcher_log <- rbind(pitcher_log, tibble(
          pitcher_name = pitcher_name,
          level = "MLB",
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pitch_count = pitch_count,
          status = "arsenal_reported",
          notes = ""
        ))
        # Generate arsenal report with appropriate level
        report <- generate_pitcher_report(pitcher_data, pitcher_name, "MLB")
        
      } else {
        # Pitcher exists at this level - add to BIP/pitch counts and check for performance report trigger
        existing_bip <- pitcher_log$bip_count[pitcher_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- pitcher_log$status[pitcher_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "arsenal_reported" && new_total_bip >= 100) {
          new_status <- "performance_reported"
          # Generate performance report with complete pitcher history at this level
          full_pitcher_data <- all_data %>% filter(pitcher == player_id)
          report <- generate_pitcher_performance_report(full_pitcher_data, pitcher_name, player_id, "MLB")
        }
        
        pitcher_log <- pitcher_log %>%
          mutate(
            bip_count = if_else(pitcher_name == !!pitcher_name & level == !!player_level, 
                              new_total_bip, bip_count),
            pitch_count = if_else(pitcher_name == !!pitcher_name & level == !!player_level, 
                                pitch_count + !!pitch_count, pitch_count),
            status = if_else(pitcher_name == !!pitcher_name & level == !!player_level,
                           new_status, status),
            report_date = if_else(pitcher_name == !!pitcher_name & level == !!player_level & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
        
    } else {
      # Filter data by both batter ID AND level
      batter_data <- data %>% filter(batter == player_id)
      player_name <- batter_data$last_first_name[1]
      player_level <- "MLB"
      filename_name <- player_name
      
      # Calculate BIP and PA count
      bip_count <- calculate_hitter_bip(batter_data)
      pa_count <- nrow(batter_data)
      
      # Determine hitter status and generate appropriate report
      # Check for existing batter at this SPECIFIC LEVEL
      hitter_idx <- which(hitter_log$batter == as.character(player_id) & hitter_log$level == "MLB")
      
      if (length(hitter_idx) == 0) {
        # New hitter at this level - add to log, no report yet
        hitter_log <- rbind(hitter_log, tibble(
          batter = as.character(player_id),
          level = "MLB",
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pa_count = pa_count,
          status = "new",
          notes = ""
        ))
        report <- NULL  # No report yet for new hitters
        
      } else {
        # Hitter exists at this level - add to BIP/PA counts and check for report trigger
        existing_bip <- hitter_log$bip_count[hitter_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- hitter_log$status[hitter_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "new" && new_total_bip >= 100) {
          new_status <- "reported"
          # Generate hitter report with complete hitter history at this level
          full_batter_data <- all_data %>% filter(batter == player_id)
          report <- generate_hitter_report(full_batter_data, player_id, "MLB")
        }
        
        hitter_log <- hitter_log %>%
          mutate(
            bip_count = if_else(batter == as.character(!!player_id) & level == !!player_level, 
                              new_total_bip, bip_count),
            pa_count = if_else(batter == as.character(!!player_id) & level == !!player_level, 
                             pa_count + !!pa_count, pa_count),
            status = if_else(batter == as.character(!!player_id) & level == !!player_level,
                           new_status, status),
            report_date = if_else(batter == as.character(!!player_id) & level == !!player_level & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
    }
    
    # Save report (if generated)
    if (!is.null(report)) {
      # Extract team information
      team <- NA_character_
      if (player_type == "pitcher") {
        team <- get_pitcher_team_mlb(pitcher_data)
      } else {
        team <- get_batter_team_mlb(batter_data)
      }
      team_str <- if (is.na(team)) "" else paste0(team, "_")
      
      # Include level in filename for MiLB reports
      level_prefix <- if (player_level != "MLB") paste0(player_level, "_") else ""
      # Determine report type for filename based on report content
      report_type <- if (any(grepl("Arsenal", report))) "newprofile" else "performance"
      filename <- sprintf("%s_%s%s%s_%s_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         level_prefix,
                         team_str,
                         player_type,
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
# (milb_new_players, milb_statcast_data, milb_all_data, max_game_date)
# players <- milb_new_players
# data <- milb_statcast_data
# all_data <- milb_all_data
generate_new_player_reports_milb <- function(players, data, all_data, max_game_date) {
  # Generates new player profile reports
  # Tracks players separately by level (MLB, AAA, AA, etc.)
  # data = current batch data (for identification)
  # all_data = full historical data (for performance report calculations)
  
  # Load or initialize pitcher tracking log
  pitcher_tracking_path <- ".system/pitcher_tracking_log.csv"
  if (file.exists(pitcher_tracking_path)) {
    pitcher_log <- read_csv(pitcher_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(pitcher_log)) {
      pitcher_log <- pitcher_log %>% mutate(level = "MiLB", .after = pitcher_name)
    }
  } else {
    pitcher_log <- tibble(pitcher_name = character(), level = character(), 
                         report_date = character(), bip_count = numeric(), 
                         pitch_count = numeric(), status = character(), notes = character())
  }
  
  # Load or initialize hitter tracking log
  hitter_tracking_path <- ".system/hitter_tracking_log.csv"
  if (file.exists(hitter_tracking_path)) {
    hitter_log <- read_csv(hitter_tracking_path, show_col_types = FALSE)
    # Ensure level column exists
    if (!"level" %in% colnames(hitter_log)) {
      hitter_log <- hitter_log %>% mutate(level = "MiLB", .after = batter)
    }
  } else {
    hitter_log <- tibble(batter = character(), level = character(), 
                        report_date = character(), bip_count = numeric(), 
                        pa_count = numeric(), status = character(), notes = character())
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- if (!is.na(players$matchup.pitcher.id[i])) players$matchup.pitcher.id[i] else players$matchup.batter.id[i]
    player_type <- players$player_type[i]
    
    if (player_type == "pitcher") {
      # Filter data by both pitcher ID AND level
      pitcher_data <- data %>% filter(matchup.pitcher.id == player_id)
      pitcher_name <- pitcher_data$matchup.pitcher.fullName[1]
      player_level <- pitcher_data$home_level_name[1]
      filename_name <- pitcher_name
      report <- NULL  # Initialize report as NULL
      
      # Calculate BIP and pitch count
      bip_count <- calculate_pitcher_bip_mnl(pitcher_data)
      pitch_count <- nrow(pitcher_data)
      
      # Determine pitcher status and generate appropriate report
      # Check for existing pitcher at this SPECIFIC LEVEL
      pitcher_idx <- which(pitcher_log$pitcher_name == pitcher_name & pitcher_log$level == player_level)
      
      if (length(pitcher_idx) == 0) {
        # New pitcher at this level - add to log and generate arsenal report
        pitcher_log <- rbind(pitcher_log, tibble(
          pitcher_name = pitcher_name,
          level = player_level,
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pitch_count = pitch_count,
          status = "arsenal_reported",
          notes = ""
        ))
        # Generate arsenal report with appropriate level
        report <- generate_pitcher_report(pitcher_data, pitcher_name, player_level)
        
      } else {
        # Pitcher exists at this level - add to BIP/pitch counts and check for performance report trigger
        existing_bip <- pitcher_log$bip_count[pitcher_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- pitcher_log$status[pitcher_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "arsenal_reported" && new_total_bip >= 100) {
          new_status <- "performance_reported"
          # Generate performance report with complete pitcher history at this level
          full_pitcher_data <- all_data %>% filter(matchup.pitcher.id == player_id)
          report <- generate_pitcher_performance_report(full_pitcher_data, pitcher_name, player_id, player_level)
        }
        
        pitcher_log <- pitcher_log %>%
          mutate(
            bip_count = if_else(pitcher_name == !!pitcher_name & level == !!player_level, 
                              new_total_bip, bip_count),
            pitch_count = if_else(pitcher_name == !!pitcher_name & level == !!player_level, 
                                pitch_count + !!pitch_count, pitch_count),
            status = if_else(pitcher_name == !!pitcher_name & level == !!player_level,
                           new_status, status),
            report_date = if_else(pitcher_name == !!pitcher_name & level == !!player_level & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
        
    } else {
      # Filter data by both batter ID AND level
      batter_data <- data %>% filter(matchup.batter.id == player_id)
      player_name <- batter_data$matchup.batter.fullName[1]
      player_level <- batter_data$home_level_name[1]
      filename_name <- player_name
      
      # Calculate BIP and PA count
      bip_count <- calculate_hitter_bip_mnl(batter_data)
      pa_count <- nrow(batter_data)
      
      # Determine hitter status and generate appropriate report
      # Check for existing batter at this SPECIFIC LEVEL
      hitter_idx <- which(hitter_log$batter == as.character(player_id) & hitter_log$level == player_level)
      
      if (length(hitter_idx) == 0) {
        # New hitter at this level - add to log, no report yet
        hitter_log <- rbind(hitter_log, tibble(
          batter = as.character(player_id),
          level = player_level,
          report_date = format(max_game_date, "%Y-%m-%d"),
          bip_count = bip_count,
          pa_count = pa_count,
          status = "new",
          notes = ""
        ))
        report <- NULL  # No report yet for new hitters
        
      } else {
        # Hitter exists at this level - add to BIP/PA counts and check for report trigger
        existing_bip <- hitter_log$bip_count[hitter_idx]
        new_total_bip <- existing_bip + bip_count
        current_status <- hitter_log$status[hitter_idx]
        
        # Update counts and potentially status
        new_status <- current_status
        report <- NULL  # Initialize report as NULL
        if (current_status == "new" && new_total_bip >= 100) {
          new_status <- "reported"
          # Generate hitter report with complete hitter history at this level
          full_batter_data <- all_data %>% filter(matchup.batter.id == player_id)
          report <- generate_hitter_report(full_batter_data, player_id, player_level)
        }
        
        hitter_log <- hitter_log %>%
          mutate(
            bip_count = if_else(batter == as.character(!!player_id) & level == !!player_level, 
                              new_total_bip, bip_count),
            pa_count = if_else(batter == as.character(!!player_id) & level == !!player_level, 
                             pa_count + !!pa_count, pa_count),
            status = if_else(batter == as.character(!!player_id) & level == !!player_level,
                           new_status, status),
            report_date = if_else(batter == as.character(!!player_id) & level == !!player_level & new_status != current_status,
                                format(max_game_date, "%Y-%m-%d"), as.character(report_date))
          )
      }
    }
    
    # Save report (if generated)
    if (!is.null(report)) {
      # Extract team information
      team <- NA_character_
      if (player_type == "pitcher") {
        pitcher_data <- data %>% filter(matchup.pitcher.id == player_id)
        team <- get_pitcher_team_milb(pitcher_data)
      } else {
        batter_data <- data %>% filter(matchup.batter.id == player_id)
        team <- get_batter_team_milb(batter_data)
      }
      team_str <- if (is.na(team)) "" else paste0(team, "_")
      
      # Include level in filename for MiLB reports
      level_prefix <- if (player_level != "MLB") paste0(player_level, "_") else ""
      # Determine report type for filename based on report content
      report_type <- if (any(grepl("Arsenal", report))) "newprofile" else "performance"
      filename <- sprintf("%s_%s%s%s_%s_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         level_prefix,
                         team_str,
                         player_type,
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

# players <- mlb_trend_candidates
# all_data <- mlb_all_data
generate_trend_reports <- function(players, all_data) {
  # Generates trend analysis reports for players with significant metric changes
  # Only called at beginning of each month
  
  if (nrow(players) == 0) {
    return()
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- players$player_id[i]
    player_type <- players$player_type[i]
    if (player_type == "pitcher") {
      player_name <- players$player_name[i]
    } else if (player_type == "batter") {
      player_name <- all_data %>%
        filter(batter == player_id) %>%
        pull(last_first_name) %>%
        first()
    }
    player_level <- players$level[i]
    metric_changes <- players$metric_changes[[i]]
    report <- NULL
    
    if (player_type == "pitcher") {
      report <- generate_pitcher_trend_report(player_id, player_name, player_level, metric_changes, all_data)
    } else if (player_type == "batter") {
      report <- generate_batter_trend_report(player_id, player_level, metric_changes, all_data)
    }
    
    # Save report
    if (!is.null(report)) {
      # Extract team information for trend report
      team <- NA_character_
      if (player_type == "pitcher") {
        pitcher_data <- all_data %>% filter(pitcher == player_id, level == player_level) %>% dplyr::slice(1)
        team <- get_pitcher_team_mlb(pitcher_data)
      } else {
        batter_data <- all_data %>% filter(batter == player_id, level == player_level) %>% dplyr::slice(1)
        team <- get_batter_team_mlb(batter_data)
      }
      team_str <- if (is.na(team)) "" else paste0(team, "_")
      
      level_prefix <- if (player_level != "MLB") paste0(player_level, "_") else ""
      filename <- sprintf("%s_%s%strend_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         level_prefix,
                         team_str,
                         str_replace_all(as.character(player_name), " ", "-"))
      filepath <- file.path(OUTPUT_DIR, filename)
      
      writeLines(report, filepath)
      cat("Generated trend report:", filename, "\n")
    }
  }
}

generate_trend_reports_mnl <- function(players, all_data) {
  # Generates trend analysis reports for players with significant metric changes
  # Only called at beginning of each month
  
  if (nrow(players) == 0) {
    return()
  }
  
  for (i in seq_len(nrow(players))) {
    player_id <- players$player_id[i]
    player_type <- players$player_type[i]
    if (player_type == "pitcher") {
      player_name <- players$player_name[i]
    } else if (player_type == "batter") {
      player_name <- all_data %>%
        filter(matchup.batter.id == player_id) %>%
        pull(matchup.batter.fullName) %>%
        first()
    }
    player_level <- players$level[i]
    metric_changes <- players$metric_changes[[i]]
    report <- NULL
    
    if (player_type == "pitcher") {
      report <- generate_pitcher_trend_report_mnl(player_id, player_name, player_level, metric_changes, all_data)
    } else if (player_type == "batter") {
      report <- generate_batter_trend_report_mnl(player_id, player_level, metric_changes, all_data)
    }
    
    # Save report
    if (!is.null(report)) {
      # Extract team information for trend report
      team <- NA_character_
      if (player_type == "pitcher") {
        pitcher_data <- all_data %>% filter(matchup.pitcher.id == player_id, home_level_name == player_level) %>% dplyr::slice(1)
        team <- get_pitcher_team_milb(pitcher_data)
      } else {
        batter_data <- all_data %>% filter(matchup.batter.id == player_id, home_level_name == player_level) %>% dplyr::slice(1)
        team <- get_batter_team_milb(batter_data)
      }
      team_str <- if (is.na(team)) "" else paste0(team, "_")
      
      level_prefix <- if (player_level != "MLB") paste0(player_level, "_") else ""
      filename <- sprintf("%s_%s%strend_%s.md", 
                         format(Sys.Date(), "%Y-%m-%d"),
                         level_prefix,
                         team_str,
                         str_replace_all(as.character(player_name), " ", "-"))
      filepath <- file.path(OUTPUT_DIR, filename)
      
      writeLines(report, filepath)
      cat("Generated trend report:", filename, "\n")
    }
  }
}

generate_pitcher_trend_report <- function(pitcher_id, pitcher_name, pitcher_level, metric_changes, all_data) {
  # Generates pitcher trend report showing month-over-month changes with percentile ranks and arsenal metrics
  # pitcher_level: league level ("MLB", "AAA", "AA", etc.)
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  first_of_month <- as.Date(paste0(data_year, "-", sprintf("%02d", data_month), "-01"))
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 2
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods (filtered by level to maintain separation)
  prev_data <- all_data %>%
    filter(pitcher == pitcher_id, level == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(pitcher == pitcher_id, level == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) < first_of_month)
  
  # Use appropriate metric function based on level
  if (pitcher_level == "MLB") {
    prev_metrics <- calculate_pitcher_overall_perf(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_pitcher_overall_perf_milb(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf_milb(curr_data)
  }
  
  # Calculate percentile ranks for both periods
  tryCatch({
    prev_percentiles <- calculate_pitcher_overall_percentiles(prev_metrics, pitcher_id, pitcher_level)
    curr_percentiles <- calculate_pitcher_overall_percentiles(curr_metrics, pitcher_id, pitcher_level)
  }, error = function(e) {
    # Skip report if percentile calculation fails
    return(NULL)
  })
  
  # If percentile calculation failed, return NULL to skip report
  if (is.null(prev_percentiles) || is.null(curr_percentiles)) {
    return(NULL)
  }
  
  # Calibrated thresholds for percentile differences
  thresholds <- list(
    swing_pct = 0.92,
    strike_pct = 0.80,
    zone_pct = 0.94,
    chase_pct = 1.17,
    whiff_pct = 1.39,
    iz_whiff = 1.43,
    oz_whiff = 2.22,
    gb_pct = 2.23,
    hh_pct = 1.62
  )
  
  # Map metric names to percentile rank field names
  metric_to_percentile <- list(
    swing_pct = "swing_rank",
    strike_pct = "strike_rank",
    zone_pct = "zone_rank",
    chase_pct = "chase_rank",
    whiff_pct = "whiff_rank",
    iz_whiff = "iz_whiff_rank",
    oz_whiff = "oz_whiff_rank",
    gb_pct = "gb_rank",
    hh_pct = "hh_rank"
  )
  
  # Identify significant percentile changes (performance KPIs)
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "arsenal") next  # Handle arsenal separately below
    if (!(metric %in% names(metric_to_percentile))) next
    
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    if (abs(pctl_delta) >= thresholds[[metric]]) {
      direction <- if (pctl_delta > 0) "↑" else "↓"
      significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                              sprintf("%+.1f", pctl_delta), " percentile points")
    }
  }
  
  # Add significant arsenal changes with pitch identification
  if (!is.null(metric_changes$arsenal)) {
    arsenal_thresholds <- list(velo = 2.0, hb = 3.0, vb = 3.0, rel_side = 0.2, rel_height = 0.2)
    
    for (arsenal_key in names(metric_changes$arsenal)) {
      arsenal_metric <- metric_changes$arsenal[[arsenal_key]]
      if (!is.na(arsenal_metric$delta) && abs(arsenal_metric$delta) >= arsenal_thresholds[[arsenal_metric$metric]]) {
        direction <- if (arsenal_metric$delta > 0) "↑" else "↓"
        
        # Format the display based on metric type
        if (arsenal_metric$metric == "velo") {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - Velo: ", 
                           sprintf("%+.1f", arsenal_metric$delta), " mph")
        } else if (arsenal_metric$metric %in% c("hb", "vb")) {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - ", 
                           toupper(gsub("_", "-", arsenal_metric$metric)), ": ", 
                           sprintf("%+.1f", arsenal_metric$delta), " in")
        } else {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - ", 
                           arsenal_metric$metric, ": ", 
                           sprintf("%+.2f", arsenal_metric$delta))
        }
        
        significant_changes[[arsenal_key]] <- display
      }
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table with percentile ranks
  metrics_table <- "| Metric | Previous Percentile | Current Percentile | Change |\n|---|---|---|---|\n"
  
  for (metric in names(metric_to_percentile)) {
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }
  
  # Add arsenal metrics table if present
  if (!is.null(metric_changes$arsenal)) {
    arsenal_thresholds <- list(velo = 2.0, hb = 3.0, vb = 3.0, rel_side = 0.2, rel_height = 0.2)
    arsenal_metrics_shown <- FALSE
    arsenal_table <- "| Pitch | Metric | Previous | Current | Change |\n|---|---|---|---|---|\n"
    
    for (arsenal_key in names(metric_changes$arsenal)) {
      arsenal_metric <- metric_changes$arsenal[[arsenal_key]]
      if (!is.na(arsenal_metric$prev_val) && !is.na(arsenal_metric$curr_val)) {
        arsenal_metrics_shown <- TRUE
        
        if (arsenal_metric$metric == "velo") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Velo (mph) | ",
                                sprintf("%.1f", arsenal_metric$prev_val), " | ",
                                sprintf("%.1f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.1f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric %in% c("hb", "vb")) {
          metric_name <- if (arsenal_metric$metric == "hb") "H-Break (in)" else "V-Break (in)"
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | ", metric_name, " | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric == "rel_side") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Release Side | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric == "rel_height") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Release Height | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        }
      }
    }
    
    if (arsenal_metrics_shown) {
      metrics_table <- paste0(metrics_table, "\n## Arsenal Metrics\n", arsenal_table)
    }
  }
  
  # Create report content
  if (length(significant_changes) > 0) {
    report_content <- paste0(
      "# Pitcher Trend Report: ", pitcher_name, "\n\n",
      "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
      "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
      "## Significant Changes\n",
      changes_list, "\n\n",
      "## Detailed Metrics Breakdown (Percentile Ranks)\n",
      metrics_table, "\n",
      "## Analysis\n",
      "[Trend analysis pending]\n"
    )
  } else {
    report_content <- NULL
  }
  
  return(report_content)
}

generate_pitcher_trend_report_mnl <- function(pitcher_id, pitcher_name, pitcher_level, metric_changes, all_data) {
  # Generates pitcher trend report showing month-over-month changes with percentile ranks
  # pitcher_level: league level ("MLB", "AAA", "AA", etc.)
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  first_of_month <- as.Date(paste0(data_year, "-", sprintf("%02d", data_month), "-01"))
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 2
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods (filtered by level to maintain separation)
  prev_data <- all_data %>%
    filter(matchup.pitcher.id == pitcher_id, home_level_name == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(matchup.pitcher.id == pitcher_id, home_level_name == pitcher_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) < first_of_month)
  
  # Use appropriate metric function based on level
  if (pitcher_level == "MLB") {
    prev_metrics <- calculate_pitcher_overall_perf(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_pitcher_overall_perf_milb(prev_data)
    curr_metrics <- calculate_pitcher_overall_perf_milb(curr_data)
  }
  
  # Calculate percentile ranks for both periods
  tryCatch({
    prev_percentiles <- calculate_pitcher_overall_percentiles(prev_metrics, pitcher_id, pitcher_level)
    curr_percentiles <- calculate_pitcher_overall_percentiles(curr_metrics, pitcher_id, pitcher_level)
  }, error = function(e) {
    # Skip report if percentile calculation fails
    return(NULL)
  })
  
  # If percentile calculation failed, return NULL to skip report
  if (is.null(prev_percentiles) || is.null(curr_percentiles)) {
    return(NULL)
  }
  
  # Calibrated thresholds for percentile differences
  thresholds <- list(
    swing_pct = 0.92,
    strike_pct = 0.80,
    zone_pct = 0.94,
    chase_pct = 1.17,
    whiff_pct = 1.39,
    iz_whiff = 1.43,
    oz_whiff = 2.22,
    gb_pct = 2.23,
    hh_pct = 1.62
  )
  
  # Map metric names to percentile rank field names
  metric_to_percentile <- list(
    swing_pct = "swing_rank",
    strike_pct = "strike_rank",
    zone_pct = "zone_rank",
    chase_pct = "chase_rank",
    whiff_pct = "whiff_rank",
    iz_whiff = "iz_whiff_rank",
    oz_whiff = "oz_whiff_rank",
    gb_pct = "gb_rank",
    hh_pct = "hh_rank"
  )
  
  # Identify significant percentile changes (performance KPIs)
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "arsenal") next  # Handle arsenal separately below
    if (!(metric %in% names(metric_to_percentile))) next
    
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    if (abs(pctl_delta) >= thresholds[[metric]]) {
      direction <- if (pctl_delta > 0) "↑" else "↓"
      significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                              sprintf("%+.1f", pctl_delta), " percentile points")
    }
  }
  
  # Add significant arsenal changes with pitch identification
  if (!is.null(metric_changes$arsenal)) {
    arsenal_thresholds <- list(velo = 2.0, hb = 3.0, vb = 3.0, rel_side = 0.2, rel_height = 0.2)
    
    for (arsenal_key in names(metric_changes$arsenal)) {
      arsenal_metric <- metric_changes$arsenal[[arsenal_key]]
      if (!is.na(arsenal_metric$delta) && abs(arsenal_metric$delta) >= arsenal_thresholds[[arsenal_metric$metric]]) {
        direction <- if (arsenal_metric$delta > 0) "↑" else "↓"
        
        # Format the display based on metric type
        if (arsenal_metric$metric == "velo") {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - Velo: ", 
                           sprintf("%+.1f", arsenal_metric$delta), " mph")
        } else if (arsenal_metric$metric %in% c("hb", "vb")) {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - ", 
                           toupper(gsub("_", "-", arsenal_metric$metric)), ": ", 
                           sprintf("%+.1f", arsenal_metric$delta), " in")
        } else {
          display <- paste0(direction, " ", arsenal_metric$pitch, " - ", 
                           arsenal_metric$metric, ": ", 
                           sprintf("%+.2f", arsenal_metric$delta))
        }
        
        significant_changes[[arsenal_key]] <- display
      }
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table with percentile ranks
  metrics_table <- "| Metric | Previous Percentile | Current Percentile | Change |\n|---|---|---|---|\n"
  
  for (metric in names(metric_to_percentile)) {
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }
  
  # Add arsenal metrics table if present
  if (!is.null(metric_changes$arsenal)) {
    arsenal_thresholds <- list(velo = 2.0, hb = 3.0, vb = 3.0, rel_side = 0.2, rel_height = 0.2)
    arsenal_metrics_shown <- FALSE
    arsenal_table <- "| Pitch | Metric | Previous | Current | Change |\n|---|---|---|---|---|\n"
    
    for (arsenal_key in names(metric_changes$arsenal)) {
      arsenal_metric <- metric_changes$arsenal[[arsenal_key]]
      if (!is.na(arsenal_metric$prev_val) && !is.na(arsenal_metric$curr_val)) {
        arsenal_metrics_shown <- TRUE
        
        if (arsenal_metric$metric == "velo") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Velo (mph) | ",
                                sprintf("%.1f", arsenal_metric$prev_val), " | ",
                                sprintf("%.1f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.1f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric %in% c("hb", "vb")) {
          metric_name <- if (arsenal_metric$metric == "hb") "H-Break (in)" else "V-Break (in)"
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | ", metric_name, " | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric == "rel_side") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Release Side | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        } else if (arsenal_metric$metric == "rel_height") {
          arsenal_table <- paste0(arsenal_table, "| ", arsenal_metric$pitch, " | Release Height | ",
                                sprintf("%.2f", arsenal_metric$prev_val), " | ",
                                sprintf("%.2f", arsenal_metric$curr_val), " | ",
                                sprintf("%+.2f", arsenal_metric$delta), " |\n")
        }
      }
    }
    
    if (arsenal_metrics_shown) {
      metrics_table <- paste0(metrics_table, "\n## Arsenal Metrics\n", arsenal_table)
    }
  }
  
  # Create report content
  if (length(significant_changes) > 0) {
    report_content <- paste0(
    "# Pitcher Trend Report: ", pitcher_name, "\n\n",
    "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
    "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
    "## Significant Changes\n",
    changes_list, "\n\n",
    "## Detailed Metrics Breakdown (Percentile Ranks)\n",
    metrics_table, "\n",
    "## Analysis\n",
    "[Trend analysis pending]\n"
    )
  } else {
    NULL
  }
  
  return(report_content)
}

generate_batter_trend_report <- function(batter_id, batter_level, metric_changes, all_data) {
  # Generates batter trend report showing month-over-month changes with percentile ranks
  # Note: batter_name is not available in our data, using batter_id for identification
  # batter_level: league level ("MLB", "AAA", "AA", etc.)

  batter_name <- all_data %>% filter(batter == batter_id) %>% pull(last_first_name) %>% first()
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  first_of_month <- as.Date(paste0(data_year, "-", sprintf("%02d", data_month), "-01"))
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 2
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods (filtered by level to maintain separation)
  prev_data <- all_data %>%
    filter(batter == batter_id, level == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(batter == batter_id, level == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= max_game_date)
  
  # Use appropriate metric function based on level
  if (batter_level == "MLB") {
    prev_metrics <- calculate_batter_overall_perf(prev_data)
    curr_metrics <- calculate_batter_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_batter_overall_perf_milb(prev_data)
    curr_metrics <- calculate_batter_overall_perf_milb(curr_data)
  }
  
  # Calculate percentile ranks for both periods
  tryCatch({
    prev_percentiles <- calculate_batter_overall_percentiles(prev_metrics, batter_id, batter_level)
    curr_percentiles <- calculate_batter_overall_percentiles(curr_metrics, batter_id, batter_level)
    # Also get profile percentiles
    prev_profile <- calculate_batter_profile(prev_data)
    curr_profile <- calculate_batter_profile(curr_data)
    prev_profile_pctl <- calculate_batter_profile_percentiles(prev_profile, batter_id, batter_level)
    curr_profile_pctl <- calculate_batter_profile_percentiles(curr_profile, batter_id, batter_level)
  }, error = function(e) {
    # Skip report if percentile calculation fails
    return(NULL)
  })
  
  # If percentile calculation failed, return NULL to skip report
  if (is.null(prev_percentiles) || is.null(curr_percentiles) || 
      is.null(prev_profile_pctl) || is.null(curr_profile_pctl)) {
    return(NULL)
  }
  
  # Calibrated thresholds for percentile differences (performance KPIs)
  thresholds <- list(
    swing_pct = 1.93,
    chase_pct = 2.31,
    foul_pct = 2.17,
    whiff_pct = 2.16,
    iz_whiff = 2.24,
    oz_whiff = 3.66,
    gb_pct = 3.95,
    barrel_pct = 2.0,
    hh_pct = 3.48,
    slg = 0.075,
    swspt_pct = 3.64
  )
  
  # Add profile KPI thresholds
  profile_thresholds <- list(
    avg_la = 2.20,
    la_std_dev = 1.53,
    hh_la = 2.18,
    oppo_fb_pct = 6.80,
    oppo_fb_ev = 2.45,
    high_aa_pct = 8.50
  )
  
  # Map metric names to percentile rank field names
  metric_to_percentile <- list(
    swing_pct = "swing_rank",
    chase_pct = "chase_rank",
    foul_pct = "foul_rank",
    whiff_pct = "whiff_rank",
    iz_whiff = "iz_whiff_rank",
    oz_whiff = "oz_whiff_rank",
    gb_pct = "gb_rank",
    barrel_pct = "barrel_rank",
    hh_pct = "hh_rank",
    slg = "slg_rank",
    swspt_pct = "swspt_rank"
  )
  
  # Map profile metrics to percentile rank field names
  profile_to_percentile <- list(
    avg_la = "avg_la_rank",
    la_std_dev = "la_std_dev_rank",
    hh_la = "hh_la_rank",
    oppo_fb_pct = "oppo_fb_pct_rank",
    oppo_fb_ev = "oppo_fb_ev_rank",
    high_aa_pct = "high_aa_pct_rank"
  )
  
  # Identify significant percentile changes for performance KPIs
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "profile") next  # Handle profile separately below
    if (!(metric %in% names(metric_to_percentile))) next
    
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    if (abs(pctl_delta) >= thresholds[[metric]]) {
      direction <- if (pctl_delta > 0) "↑" else "↓"
      significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                              sprintf("%+.1f", pctl_delta), " percentile points")
    }
  }
  
  # Add significant profile changes
  if (!is.null(metric_changes$profile)) {
    for (profile_metric in names(metric_changes$profile)) {
      if (!(profile_metric %in% names(profile_to_percentile))) next
      
      percentile_field <- profile_to_percentile[[profile_metric]]
      prev_pctl <- prev_profile_pctl[[percentile_field]]
      curr_pctl <- curr_profile_pctl[[percentile_field]]
      pctl_delta <- curr_pctl - prev_pctl
      
      if (abs(pctl_delta) >= profile_thresholds[[profile_metric]]) {
        direction <- if (pctl_delta > 0) "↑" else "↓"
        significant_changes[[profile_metric]] <- paste0(direction, " ", profile_metric, ": ", 
                                                        sprintf("%+.1f", pctl_delta), " percentile points")
      }
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table with percentile ranks - include both performance and profile
  metrics_table <- "| Metric | Previous Percentile | Current Percentile | Change |\n|---|---|---|---|\n"
  
  # Add performance KPI percentiles
  for (metric in names(metric_to_percentile)) {
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }
  
  # Add profile KPI percentiles
  for (profile_metric in names(profile_to_percentile)) {
    percentile_field <- profile_to_percentile[[profile_metric]]
    prev_pctl <- prev_profile_pctl[[percentile_field]]
    curr_pctl <- curr_profile_pctl[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", profile_metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }

  if (length(significant_changes) > 0) {
    report_content <- paste0(
    "# Batter Trend Report: ", batter_name, "\n\n",
    "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
    "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
    "## Significant Changes\n",
    changes_list, "\n\n",
    "## Detailed Metrics Breakdown (Percentile Ranks)\n",
    metrics_table, "\n",
    "## Analysis\n",
    "[Trend analysis pending]\n"
  )
  } else {
    report_content <- NULL
  }
  
  return(report_content)
}

generate_batter_trend_report_mnl <- function(batter_id, batter_level, metric_changes, all_data) {
  # Generates batter trend report showing month-over-month changes with percentile ranks
  # Note: batter_name is not available in our data, using batter_id for identification
  # batter_level: league level ("MLB", "AAA", "AA", etc.)

  batter_name <- all_data %>% filter(matchup.batter.id == batter_id) %>% pull(matchup.batter.fullName) %>% first()
  
  # Get the latest game_date in the data to determine analysis month/year
  max_game_date <- max(as.Date(all_data$game_date), na.rm = TRUE)
  data_month <- month(max_game_date)
  data_year <- year(max_game_date)
  first_of_month <- as.Date(paste0(data_year, "-", sprintf("%02d", data_month), "-01"))
  
  year_start <- paste0(data_year, "-01-01")
  prev_month <- if (data_month == 1) 12 else data_month - 2
  prev_year <- if (data_month == 1) data_year - 1 else data_year
  prev_month_end <- as.Date(paste0(prev_year, "-", 
                                   sprintf("%02d", prev_month), "-28")) %>%
    ceiling_date("month") - days(1)
  
  # Get data for both periods (filtered by level to maintain separation)
  prev_data <- all_data %>%
    filter(matchup.batter.id == batter_id, home_level_name == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= prev_month_end)
  
  curr_data <- all_data %>%
    filter(matchup.batter.id == batter_id, home_level_name == batter_level,
           as.Date(game_date) >= as.Date(year_start),
           as.Date(game_date) <= max_game_date)
  
  # Use appropriate metric function based on level
  if (batter_level == "MLB") {
    prev_metrics <- calculate_batter_overall_perf(prev_data)
    curr_metrics <- calculate_batter_overall_perf(curr_data)
  } else {
    prev_metrics <- calculate_batter_overall_perf_milb(prev_data)
    curr_metrics <- calculate_batter_overall_perf_milb(curr_data)
  }
  
  # Calculate percentile ranks for both periods
  tryCatch({
    prev_percentiles <- calculate_batter_overall_percentiles(prev_metrics, batter_id, batter_level)
    curr_percentiles <- calculate_batter_overall_percentiles(curr_metrics, batter_id, batter_level)
    # Also get profile percentiles
    prev_profile <- calculate_batter_profile_milb(prev_data)
    curr_profile <- calculate_batter_profile_milb(curr_data)
    prev_profile_pctl <- calculate_batter_profile_percentiles(prev_profile, batter_id, batter_level)
    curr_profile_pctl <- calculate_batter_profile_percentiles(curr_profile, batter_id, batter_level)
  }, error = function(e) {
    # Skip report if percentile calculation fails
    return(NULL)
  })
  
  # If percentile calculation failed, return NULL to skip report
  if (is.null(prev_percentiles) || is.null(curr_percentiles) || 
      is.null(prev_profile_pctl) || is.null(curr_profile_pctl)) {
    return(NULL)
  }
  
  # Calibrated thresholds for percentile differences (performance KPIs)
  thresholds <- list(
    swing_pct = 1.93,
    chase_pct = 2.31,
    foul_pct = 2.17,
    whiff_pct = 2.16,
    iz_whiff = 2.24,
    oz_whiff = 3.66,
    gb_pct = 3.95,
    barrel_pct = 2.0,
    hh_pct = 3.48,
    slg = 0.075,
    swspt_pct = 3.64
  )
  
  # Add profile KPI thresholds
  profile_thresholds <- list(
    avg_la = 2.20,
    la_std_dev = 1.53,
    hh_la = 2.18,
    oppo_fb_pct = 6.80,
    oppo_fb_ev = 2.45,
    high_aa_pct = 8.50
  )
  
  # Map metric names to percentile rank field names
  metric_to_percentile <- list(
    swing_pct = "swing_rank",
    chase_pct = "chase_rank",
    foul_pct = "foul_rank",
    whiff_pct = "whiff_rank",
    iz_whiff = "iz_whiff_rank",
    oz_whiff = "oz_whiff_rank",
    gb_pct = "gb_rank",
    barrel_pct = "barrel_rank",
    hh_pct = "hh_rank",
    slg = "slg_rank",
    swspt_pct = "swspt_rank"
  )
  
  # Map profile metrics to percentile rank field names
  profile_to_percentile <- list(
    avg_la = "avg_la_rank",
    la_std_dev = "la_std_dev_rank",
    hh_la = "hh_la_rank",
    oppo_fb_pct = "oppo_fb_pct_rank",
    oppo_fb_ev = "oppo_fb_ev_rank",
    high_aa_pct = "high_aa_pct_rank"
  )
  
  # Identify significant percentile changes for performance KPIs
  significant_changes <- list()
  for (metric in names(metric_changes)) {
    if (metric == "profile") next  # Handle profile separately below
    if (!(metric %in% names(metric_to_percentile))) next
    
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    if (abs(pctl_delta) >= thresholds[[metric]]) {
      direction <- if (pctl_delta > 0) "↑" else "↓"
      significant_changes[[metric]] <- paste0(direction, " ", metric, ": ", 
                                              sprintf("%+.1f", pctl_delta), " percentile points")
    }
  }
  
  # Add significant profile changes
  if (!is.null(metric_changes$profile)) {
    for (profile_metric in names(metric_changes$profile)) {
      if (!(profile_metric %in% names(profile_to_percentile))) next
      
      percentile_field <- profile_to_percentile[[profile_metric]]
      prev_pctl <- prev_profile_pctl[[percentile_field]]
      curr_pctl <- curr_profile_pctl[[percentile_field]]
      pctl_delta <- curr_pctl - prev_pctl
      
      if (abs(pctl_delta) >= profile_thresholds[[profile_metric]]) {
        direction <- if (pctl_delta > 0) "↑" else "↓"
        significant_changes[[profile_metric]] <- paste0(direction, " ", profile_metric, ": ", 
                                                        sprintf("%+.1f", pctl_delta), " percentile points")
      }
    }
  }
  
  # Add significant profile changes
  if (!is.null(metric_changes$profile)) {
    for (profile_metric in names(metric_changes$profile)) {
      if (!(profile_metric %in% names(profile_to_percentile))) next
      
      percentile_field <- profile_to_percentile[[profile_metric]]
      prev_pctl <- prev_profile_pctl[[percentile_field]]
      curr_pctl <- curr_profile_pctl[[percentile_field]]
      pctl_delta <- curr_pctl - prev_pctl
      
      if (abs(pctl_delta) >= profile_thresholds[[profile_metric]]) {
        direction <- if (pctl_delta > 0) "↑" else "↓"
        significant_changes[[profile_metric]] <- paste0(direction, " ", profile_metric, ": ", 
                                                        sprintf("%+.1f", pctl_delta), " percentile points")
      }
    }
  }
  
  # Build significant changes bullet list
  changes_list <- if (length(significant_changes) > 0) {
    paste0("- ", paste(unlist(significant_changes), collapse = "\n- "))
  } else {
    "No significant metric changes detected"
  }
  
  # Build full metrics comparison table with percentile ranks - include both performance and profile
  metrics_table <- "| Metric | Previous Percentile | Current Percentile | Change |\n|---|---|---|---|\n"
  
  # Add performance KPI percentiles
  for (metric in names(metric_to_percentile)) {
    percentile_field <- metric_to_percentile[[metric]]
    prev_pctl <- prev_percentiles[[percentile_field]]
    curr_pctl <- curr_percentiles[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }
  
  # Add profile KPI percentiles
  for (profile_metric in names(profile_to_percentile)) {
    percentile_field <- profile_to_percentile[[profile_metric]]
    prev_pctl <- prev_profile_pctl[[percentile_field]]
    curr_pctl <- curr_profile_pctl[[percentile_field]]
    pctl_delta <- curr_pctl - prev_pctl
    
    # if (is.na(prev_pctl) || is.na(curr_pctl)) next
    if (
      length(prev_pctl) != 1 ||
      length(curr_pctl) != 1 ||
      is.na(prev_pctl) ||
      is.na(curr_pctl) ||
      !is.finite(prev_pctl) ||
      !is.finite(curr_pctl)
    ) {
      next
    }
    
    metrics_table <- paste0(metrics_table,
                           "| ", profile_metric, " | ", sprintf("%.1f", prev_pctl), "th | ", 
                           sprintf("%.1f", curr_pctl), "th | ",
                           sprintf("%+.1f", pctl_delta), " |\n")
  }

  if (length(significant_changes) > 0) {
    report_content <- paste0(
    "# Batter Trend Report: ", batter_name, "\n\n",
    "**Report Date:** ", format(max_game_date, "%B %d, %Y"), "\n",
    "**Analysis Period:** Year-to-date through previous month vs year-to-date through current month\n\n",
    "## Significant Changes\n",
    changes_list, "\n\n",
    "## Detailed Metrics Breakdown (Percentile Ranks)\n",
    metrics_table, "\n",
    "## Analysis\n",
    "[Trend analysis pending]\n"
  )
  } else {
    report_content <- NULL
  }
  
  return(report_content)
}

# =============================================================================
# Report Template Population (Pitcher)
# =============================================================================
generate_pitcher_report <- function(pitcher_data, pitcher_name, level = "MLB") {
  # Generates pitcher arsenal report (at first appearance)
  # level: league level ("MLB", "AAA", "AA", etc.)
  
  report <- readLines("templates/new_player_profile_pitcher.md")
  
  # Calculate arsenal metrics based on league level
  if (level == "MLB") {
    # MLB: Use pitch-level metrics with RHH/LHH splits
    pitch_types <- unique(pitcher_data$pitch_type)
    pitch_metrics_list <- map(pitch_types, ~calculate_pitch_metrics(pitcher_data, .x))
    
    pitch_summary <- tibble(
      pitch_type = pitch_types,
      usage_pct = map_dbl(pitch_metrics_list, ~.$usage_pct)
    ) %>% arrange(desc(usage_pct))
    
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
  } else {
    # MiLB: Use simplified arsenal metrics
    arsenal_df <- calculate_pitcher_arsenal_milb(pitcher_data)
    
    pitch_table <- "| Pitch | Usage | Avg Velo | Velo Range | H-Break | V-Break | Spin Rate |\n|---|---|---|---|---|---|---|\n"
    for (i in seq_len(nrow(arsenal_df))) {
      pitch_table <- paste0(pitch_table,
                           "| ", arsenal_df$Pitch[i],
                           " | ", arsenal_df$Usage[i],
                           " | ", arsenal_df$`Avg Velo`[i],
                           " | ", arsenal_df$`Velo Min`[i], "-", arsenal_df$`Velo Max`[i],
                           " | ", arsenal_df$`H-Break`[i],
                           " | ", arsenal_df$`V-Break`[i],
                           " | ", arsenal_df$`Spin Rate`[i],
                           " |\n")
    }
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

generate_pitcher_performance_report <- function(pitcher_data, pitcher_name, pitcher_id, level) {
  # Generates pitcher performance report (at 100+ BIP)
  # Includes overall performance, pitch-level performance, and updated arsenal metrics
  # level: league level ("MLB", "AAA", "AA", etc.)
  
  # Calculate metrics based on league level
  if (level == "MLB") {
    overall_perf <- calculate_pitcher_overall_perf(pitcher_data)
    pitch_perf <- calculate_pitcher_pitch_perf(pitcher_data)
  } else {
    overall_perf <- calculate_pitcher_overall_perf_milb(pitcher_data)
    pitch_perf <- calculate_pitcher_pitch_perf_milb(pitcher_data)
  }
  
  # Calculate percentile ranks if pitcher_id provided
  percentiles_overall <- NULL
  percentiles_pitch <- NULL
  if (!is.null(pitcher_id)) {
    tryCatch({
      percentiles_overall <- calculate_pitcher_overall_percentiles(overall_perf, pitcher_id, level)
    }, error = function(e) {
      warning("Could not calculate overall percentiles: ", e$message)
    })
    
    tryCatch({
      percentiles_pitch <- calculate_pitcher_pitch_percentiles(pitch_perf, pitcher_id, level)
    }, error = function(e) {
      warning("Could not calculate pitch percentiles: ", e$message)
    })
  }
  
  # Build performance metrics table with percentile ranks
  perf_table <- paste0("| Metric | Value | Percentile |\n|---|---|---|\n",
                       "| **League** | ", level, " | — |\n")
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
  for (i in seq_len(nrow(percentiles_pitch))) {
    pitch_table <- paste0(pitch_table,
                         "| ", percentiles_pitch$pitch_name[i], 
                         " | ", percentiles_pitch$Pitches[i],
                         " | ", percentiles_pitch$BIP[i],
                         " | ", percentiles_pitch$swing_rank[i], "%",
                         " | ", percentiles_pitch$strike_rank[i], "%",
                         " | ", percentiles_pitch$zone_rank[i], "%",
                         " | ", percentiles_pitch$chase_rank[i], "%",
                         " | ", percentiles_pitch$whiff_rank[i], "%",
                         " | ", percentiles_pitch$iz_whiff_rank[i], "%",
                         " | ", percentiles_pitch$oz_whiff_rank[i], "%",
                         " | ", percentiles_pitch$gb_rank[i], "%",
                         " | ", percentiles_pitch$hh_rank[i], "% |\n")
  }
  
  # Build updated arsenal metrics based on league level
  if (level == "MLB") {
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
  } else {
    arsenal_df <- calculate_pitcher_arsenal_milb(pitcher_data)
    arsenal_table <- "| Pitch | Avg Velo | Velo Range | H-Break | V-Break | Spin Rate |\n|---|---|---|---|---|---|\n"
    for (i in seq_len(nrow(arsenal_df))) {
      arsenal_table <- paste0(arsenal_table,
                             "| ", arsenal_df$Pitch[i],
                             " | ", arsenal_df$`Avg Velo`[i],
                             " | ", arsenal_df$`Velo Min`[i], "-", arsenal_df$`Velo Max`[i],
                             " | ", arsenal_df$`H-Break`[i],
                             " | ", arsenal_df$`V-Break`[i],
                             " | ", arsenal_df$`Spin Rate`[i],
                             " |\n")
    }
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
# generate_hitter_report(full_batter_data, player_id, player_level)
# batter_data <- full_batter_data
# batter_id <- player_id
# level <- player_level
generate_hitter_report <- function(batter_data, batter_id, level) {
  # Generates hitter performance report (at 100+ BIP)
  # Includes overall performance, zone performance, and batter profile
  # level: league level ("MLB", "AAA", "AA", etc.)
  
  # Calculate metrics based on league level
  if (level == "MLB") {
    overall_perf <- calculate_batter_overall_perf(batter_data)
    zone_perf <- calculate_batter_zone_perf(batter_data)
    profile <- calculate_batter_profile(batter_data)
  } else {
    overall_perf <- calculate_batter_overall_perf_milb(batter_data)
    zone_perf <- calculate_batter_zone_perf_milb(batter_data)
    profile <- calculate_batter_profile_milb(batter_data)
  }
  
  # Calculate percentile ranks
  percentiles_overall <- NULL
  percentiles_zone <- NULL
  percentiles_profile <- NULL
  tryCatch({
    percentiles_overall <- calculate_batter_overall_percentiles(overall_perf, batter_id, level)
  }, error = function(e) {
    warning("Could not calculate overall percentiles: ", e$message)
  })
  
  tryCatch({
    percentiles_zone <- calculate_batter_zone_percentiles(zone_perf, batter_id, level)
  }, error = function(e) {
    warning("Could not calculate zone percentiles: ", e$message)
  })
  
  tryCatch({
    percentiles_profile <- calculate_batter_profile_percentiles(profile, batter_id, level)
  }, error = function(e) {
    warning("Could not calculate profile percentiles: ", e$message)
  })
  
  # Get batter name
  if (level == "MLB") {
     batter_name <- batter_data$last_first_name[1]
  } else {
    batter_name <- batter_data$matchup.batter.fullName[1]
  }
  
  if (is.na(batter_name)) {
    batter_name <- as.character(batter_id)
  }
  
  # Build overall performance table with percentile ranks
  overall_table <- paste0("| Stat | Value | Percentile |\n|---|---|---|\n",
                          "| **League** | ", level, " | — |\n")
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
  for (i in seq_len(nrow(percentiles_zone))) {
    zone_table <- paste0(zone_table,
                        "| ", percentiles_zone$Location[i],
                        " | ", percentiles_zone$BIP[i],
                        " | ", percentiles_zone$swing_rank[i], "th",
                        # if (!is.null(percentiles_zone)) paste0("(", percentiles_zone$swing_rank[i], "th)") else "", "\n",
                        " | ", percentiles_zone$chase_rank[i], "%",
                        " | ", percentiles_zone$foul_rank[i], "%",
                        " | ", percentiles_zone$whiff_rank[i], "%",
                        " | ", percentiles_zone$iz_whiff_rank[i], "%",
                        " | ", percentiles_zone$oz_whiff_rank[i], "%",
                        " | ", percentiles_zone$gb_rank[i], "%",
                        " | ", percentiles_zone$hh_rank[i], "%",
                        " | ", percentiles_zone$slg_rank[i],
                        " | ", percentiles_zone$swspt_rank[i], "% |\n")
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
