# Main Statcast Data Processing Pipeline
# Reads raw data, calculates metrics, generates reports
source("scripts/calculate_metrics.R")

library(readr)
library(stringr)
library(purrr)
library(dplyr)
library(baseballr)

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
  
  # 1. Load latest data file
  raw_files <- list.files(DATA_DIR, pattern = "*.csv", full.names = TRUE)
  
  if (length(raw_files) == 0) {
    stop("No CSV files found in data/raw/. Please add Statcast data.")
  }
  
  latest_file <- raw_files[which.max(file.info(raw_files)$mtime)]
  cat("Loading data from:", latest_file, "\n")
  
  statcast_data <- read_csv(latest_file, show_col_types = FALSE)
  
  # 2. Validate and clean data
  # statcast_data <- validate_statcast(statcast_data)

  # 3. Segment by player type and identify reportable players
  new_players <- identify_new_players(statcast_data)
  trend_candidates <- identify_trend_players(statcast_data)
  
  # 4. Generate reports
  if (nrow(new_players) > 0) {
    generate_new_player_reports(new_players, statcast_data)
  }
  
  if (nrow(trend_candidates) > 0) {
    generate_trend_reports(trend_candidates, statcast_data)
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

identify_trend_players <- function(data) {
  # Identifies existing players with noteworthy trends
  # THRESHOLD: Placeholder - will be calibrated
  
  # This is a template for trend identification logic
  # Would need historical data to compare
  
  trend_players <- tibble(
    player_id = character(),
    player_type = character(),
    metric = character(),
    change_magnitude = numeric()
  )
  
  return(trend_players)
}

# =============================================================================
# Report Generation
# =============================================================================
generate_new_player_reports <- function(players, data) {
  # Generates new player profile reports
  
  for (i in seq_len(nrow(players))) {
    # player_id <- players$pitcher[i] %||% players$batter[i]
    player_id <- if (!is.null(players$pitcher[i])) players$pitcher[i] else players$batter[i]
    player_type <- players$player_type[i]
    
    if (player_type == "pitcher") {
      pitcher_data <- data %>% filter(pitcher == player_id)
      report <- generate_pitcher_report(pitcher_data, player_id)
    } else {
      batter_data <- data %>% filter(batter == player_id)
      report <- generate_hitter_report(batter_data, player_id)
    }
    
    # Save report
    filename <- sprintf("%s_newprofile_%s.md", 
                       format(Sys.Date(), "%Y-%m-%d"),
                       str_replace_all(as.character(player_id), " ", "-"))
    filepath <- file.path(OUTPUT_DIR, filename)
    
    writeLines(report, filepath)
    cat("Generated:", filename, "\n")
  }
}

generate_trend_reports <- function(players, data) {
  # Generates trend analysis reports
  # Template placeholder - needs historical comparison data
  
  cat("Trend report generation not yet implemented.\n")
}

# =============================================================================
# Report Template Population (Pitcher)
# =============================================================================
generate_pitcher_report <- function(pitcher_data, pitcher_name) {
  # Populates pitcher template with calculated metrics
  
  report <- readLines("templates/new_player_profile_pitcher.md")
  
  # Calculate metrics
  pitch_types <- unique(pitcher_data$pitch_type)
  pitch_metrics_list <- map(pitch_types, ~calculate_pitch_metrics(pitcher_data, .x))
  
  # Create a dataframe with pitch type and usage, sort by usage descending
  pitch_summary <- tibble(
    pitch_type = pitch_types,
    usage_pct = map_dbl(pitch_metrics_list, ~.$usage_pct)
  ) %>% arrange(desc(usage_pct))
  
  # Build pitch table with arsenal metrics (sorted by usage)
  pitch_table <- "| Pitch Type | Usage % | Avg Velo | Velo Range | H-Break | V-Break | Spin Rate | Release Side | Release Height |\n|---|---|---|---|---|---|---|---|---|\n"
  for (i in seq_len(nrow(pitch_summary))) {
    pt <- pitch_summary$pitch_type[i]
    metrics <- calculate_pitch_metrics(pitcher_data, pt)
    pitch_table <- paste0(pitch_table, 
                         "| ", pt, 
                         " | ", round(metrics$usage_pct, 1), 
                         " | ", metrics$avg_velocity, 
                         " | ", metrics$velo_min, "-", metrics$velo_max,
                         " | ", metrics$hb,
                         " | ", metrics$vb,
                         " | ", metrics$spin,
                         " | ", metrics$rel_side,
                         " | ", metrics$rel_height,
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

# =============================================================================
# Report Template Population (Hitter)
# =============================================================================

generate_hitter_report <- function(batter_data, batter_name) {
  # Populates hitter template with calculated metrics
  
  report <- readLines("templates/new_player_profile_hitter.md")
  
  # Calculate key metrics
  avg <- sum(batter_data$type %in% c("X", "D", "T", "HR"), na.rm = TRUE) / nrow(batter_data)
  
  # Replace placeholders
  report <- str_replace_all(report, "\\{\\{PLAYER_NAME\\}\\}", as.character(batter_name))
  report <- str_replace_all(report, "\\{\\{DATE\\}\\}", format(Sys.Date(), "%B %d, %Y"))
  report <- str_replace_all(report, "\\{\\{PLATE_APPEARANCES\\}\\}", as.character(nrow(batter_data)))
  report <- str_replace_all(report, "\\{\\{AVG\\}\\}", as.character(round(avg, 3)))
  report <- str_replace_all(report, "\\{\\{SUMMARY_NOTES\\}\\}", "Awaiting analysis...")
  report <- str_replace_all(report, "\\{\\{.*?\\}\\}", "[DATA PENDING]")
  
  return(paste(report, collapse = "\n"))
}

# =============================================================================
# Run Pipeline
# =============================================================================

if (sys.nframe() == 0) {
  # Script is being run directly (not sourced)
  process_weekly_data()
}
