# Step 1: Build Historical Multi-Year Player Dataset (2023–2025+)
# Constructs comprehensive player-season profiles with angle and approach metrics
# Output: data/processed/angles_history_player_season.csv

library(dplyr)
library(tidyr)
library(readr)
library(purrr)
library(lubridate)
library(baseballr)

# =============================================================================
# Configuration
# =============================================================================

DATA_DIR <- "data/raw"
OUTPUT_DIR <- "data/processed"
MIN_BBE_THRESHOLD <- 50  # Lowered for early-season YTD data (typically 6-8 weeks)

# =============================================================================
# Helper Functions
# =============================================================================

# Function to identify middle zone (mid-zone pitches)
# Based on plate location: mid-zone typically defined by pixel ranges
is_middle_zone <- function(plate_x, plate_z) {
  # Approximate middle zone: x between -1.3 and 1.3, z between 1.5 and 3.5
  (plate_x >= -1.3 & plate_x <= 1.3 & plate_z >= 1.5 & plate_z <= 3.5)
}

# Function to check if pitch is a batted ball event (BBE)
is_bbe <- function(events) {
  !is.na(events) & 
    events %in% c(
      "single", "double", "triple", "home_run",
      "field_out", "force_out", "field_error", "grounded_into_double_play",
      "double_play", "sac_bunt", "sac_fly", "fielders_choice_out",
      "fielders_choice", "triple_play", "sacrifice_bunt_double_play"
    )
}

# Function to identify sweet spot (LA 8-32°)
is_sweet_spot <- function(launch_angle) {
  !is.na(launch_angle) & launch_angle >= 8 & launch_angle <= 32
}

# Function to identify hard hit (EV ≥ 95 mph)
is_hard_hit <- function(exit_velocity) {
  !is.na(exit_velocity) & exit_velocity >= 95
}

# Function to identify barrel (EV ≥ 92 AND LA 26-30°)
# is_barrel <- function(launch_angle, exit_velocity) {
#   !is.na(launch_angle) & !is.na(exit_velocity) &
#     exit_velocity >= 92 & launch_angle >= 26 & launch_angle <= 30
# }

# Function to identify fly ball
is_fly_ball <- function(bb_type) {
  !is.na(bb_type) & bb_type == "fly_ball"
}

# Function to identify opposite-field fly ball
# Opposite field = third base side for RHH, first base side for LHH
# is_oppo_fb <- function(hc_x, hc_y, stand) {
#   # Batted ball coordinates: hc_x goes from -300 (3B side) to +300 (1B side)
#   # For RHH (stand = "R"): oppo is 3B side (hc_x < ~-30)
#   # For LHH (stand = "L"): oppo is 1B side (hc_x > ~30)
#   # Approximate center line at hc_x = 0
  
#   !is.na(hc_x) & !is.na(stand) & (
#     (stand == "R" & hc_x < -30) |
#     (stand == "L" & hc_x > 30)
#   )
# }

# Function to check for high attack angle (≥ 14°)
is_high_aa <- function(attack_angle) {
  !is.na(attack_angle) & attack_angle >= 14
}

# Function to classify by LA band
la_band <- function(launch_angle) {
  ifelse(is.na(launch_angle), NA,
    ifelse(launch_angle >= 8 & launch_angle <= 16, "8_16",
      ifelse(launch_angle >= 17 & launch_angle <= 32, "17_32", "other")))
}

# =============================================================================
# Main Processing Function
# =============================================================================

# build_angles_history <- function() {
  # cat("Building angles history dataset...\n")
  
  # # 1. Load all Statcast files from data/raw/
  # raw_files <- list.files(DATA_DIR, pattern = "^statcast_.*\\.csv$", full.names = TRUE)
  
  # if (length(raw_files) == 0) {
  #   stop("No Statcast CSV files found in data/raw/")
  # }
  
  # cat("Loading", length(raw_files), "Statcast file(s)...\n")
  
  # # Load and combine all files
  # all_data <- tibble()
  # for (file in raw_files) {
  #   cat("  Processing:", basename(file), "\n")
  #   df <- read_csv(file, show_col_types = FALSE)

#   df <- dbGetQuery(conn,glue::glue(
#   "select
# *   
# from
# sc_mlb
# where 
# game_type = 'R'
# and 
#   ",
#   .con = conn
#   )
# )

player_ex <- batter_profile %>%
  filter(last_first_name == "Hamilton, David",season == 2025, handedness == "Overall",level == "MLB")

df <- batter_profile %>%
  filter(handedness == "Overall",level == "MLB", BBE >= 100)

    df <- df %>%
      rename(exit_velocity = launch_speed) %>%
      select(season, game_date, batter, stand, launch_angle, exit_velocity, 
             attack_angle, events, bb_type, hc_x, hc_y)
    all_data <- bind_rows(all_data, df)
  }
  
  # cat("Loaded", nrow(all_data), "total records across", length(unique(all_data$season)), "season(s).\n")
  
  # # Get batter names using baseballr
  # cat("Fetching batter names...\n")
  # tryCatch({
  #   players <- mlb_sports_players(sport_id = 1, season = 2026)
  #   batter_names <- players %>%
  #     select(player_id, last_first_name) %>%
  #     rename(batter = player_id, batter_name = last_first_name)
    
  #   all_data <- all_data %>%
  #     left_join(batter_names, by = "batter")
  # }, error = function(e) {
  #   cat("Warning: Could not fetch batter names via baseballr:", e$message, "\n")
  # })
  
  # # If batter_name is still missing, use batter ID as fallback
  # all_data <- all_data %>%
  #   mutate(batter_name = coalesce(batter_name, as.character(batter)))
  
  # # 2. Filter to BBE only
  # bbe_data <- all_data %>%
  #   filter(is_bbe(events)) %>%
  #   mutate(
  #     is_bbe = TRUE,
  #     is_fb = is_fly_ball(bb_type),
  #     is_oppo_fb = is_fb & is_oppo_fb(hc_x, hc_y, stand),
  #     is_ss = is_sweet_spot(launch_angle),
  #     is_hh = is_hard_hit(exit_velocity),
  #     is_barrel = is_barrel(launch_angle, exit_velocity),
  #     is_high_aa = is_high_aa(attack_angle),
  #     la_band = la_band(launch_angle)
  #   )
  
  # cat("Filtered to", nrow(bbe_data), "batted ball events (BBE).\n")
  
  # # 3. Aggregate by player-season
  # angles_by_season <- bbe_data %>%
  #   filter(!is.na(batter_name)) %>%  # Ensure batter_name exists
  #   group_by(season, batter_name, batter) %>%
  #   summarise(
  #     # Minimum BBE threshold
  #     total_bbe = n(),
      
  #     # Opposite-field metrics
  #     oppo_fb_count = sum(is_oppo_fb, na.rm = TRUE),
  #     oppo_fb_pct = ifelse(sum(is_fb, na.rm = TRUE) > 0, 
  #                           100 * sum(is_oppo_fb, na.rm = TRUE) / sum(is_fb, na.rm = TRUE),
  #                           NA),
  #     oppo_fb_ev = mean(exit_velocity[is_oppo_fb], na.rm = TRUE),
  #     oppo_fb_ev_count = sum(is_oppo_fb & !is.na(exit_velocity)),
      
  #     # Attack angle (proxy for swing loft)
  #     attack_angle_avg = mean(attack_angle, na.rm = TRUE),
  #     attack_angle_std = sd(attack_angle, na.rm = TRUE),
  #     high_aa_count = sum(is_high_aa, na.rm = TRUE),
  #     high_aa_pct = 100 * sum(is_high_aa, na.rm = TRUE) / n(),
      
  #     # Sweet spot & launch angle quality
  #     sweet_spot_count = sum(is_ss, na.rm = TRUE),
  #     sweet_spot_pct = 100 * sum(is_ss, na.rm = TRUE) / n(),
  #     launch_angle_avg = mean(launch_angle, na.rm = TRUE),
  #     launch_angle_std = sd(launch_angle, na.rm = TRUE),
  #     la_8_16_count = sum(la_band == "8_16", na.rm = TRUE),
  #     la_8_16_pct = 100 * sum(la_band == "8_16", na.rm = TRUE) / n(),
  #     la_17_32_count = sum(la_band == "17_32", na.rm = TRUE),
  #     la_17_32_pct = 100 * sum(la_band == "17_32", na.rm = TRUE) / n(),
      
  #     # Contact quality
  #     hard_hit_count = sum(is_hh, na.rm = TRUE),
  #     hard_hit_pct = 100 * sum(is_hh, na.rm = TRUE) / n(),
  #     barrel_count = sum(is_barrel, na.rm = TRUE),
  #     barrel_pct = 100 * sum(is_barrel, na.rm = TRUE) / n(),
  #     avg_exit_velocity = mean(exit_velocity, na.rm = TRUE),
      
  #     .groups = "drop"
  #   ) %>%
  #   # Filter to minimum BBE threshold
  #   filter(total_bbe >= MIN_BBE_THRESHOLD)
  
  # cat("Aggregated to player-season level. Found", nrow(angles_by_season), 
  #     "player-seasons with ≥", MIN_BBE_THRESHOLD, "BBE.\n")
  
  # 4. Calculate percentile ranks within each season (skip if no data)
  if (nrow(angles_by_season) == 0) {
    cat("\nWarning: No player-seasons with sufficient BBE. Skipping percentile calculations.\n")
    final_output <- angles_by_season %>%
      mutate(
        oppo_fb_pct_rank = NA,
        oppo_fb_ev_pct_rank = NA,
        high_aa_pct_rank = NA,
        attack_angle_avg_rank = NA,
        sweet_spot_pct_rank = NA,
        launch_angle_avg_rank = NA,
        hard_hit_pct_rank = NA,
        barrel_pct_rank = NA,
        avg_ev_rank = NA
      )
  } else {
    # (This will be used in loft profile classification later)
    angles_with_percentiles <- df %>%
      group_by(season) %>%
      mutate(
        oppo_fb_pct_rank = round(percent_rank(`Oppo FB%`) * 100, 1),
        oppo_fb_ev_pct_rank = round(percent_rank(`Oppo FB EV`) * 100, 1),
        high_aa_pct_rank = round(percent_rank(`High AA%`) * 100, 1),
        attack_angle_avg_rank = round(percent_rank(`High AA%`) * 100, 1),
        sweet_spot_pct_rank = round(percent_rank(`Sweet Spot%`) * 100, 1),
        launch_angle_avg_rank = round(percent_rank(`Avg LA`) * 100, 1),
        hard_hit_pct_rank = round(percent_rank(`HH LA`) * 100, 1),
        .groups = "drop"
      ) %>%
      ungroup()
  
    
    # 5. Select and reorder final columns for output
#     final_output <- angles_with_percentiles %>%
#       select(
#         # Base identifiers
#         season, batter, batter_name, total_bbe,
        
#         # Opposite-field metrics (raw + percentiles)
#         oppo_fb_pct, oppo_fb_pct_rank,
#         oppo_fb_ev, oppo_fb_ev_pct_rank,
        
#         # Attack angle (proxy for swing loft)
#         attack_angle_avg, attack_angle_avg_rank,
#         attack_angle_std,
#         high_aa_pct, high_aa_pct_rank,
        
#         # Sweet spot & launch angle quality
#         sweet_spot_pct, sweet_spot_pct_rank,
#         launch_angle_avg, launch_angle_avg_rank,
#         launch_angle_std,
#         la_8_16_pct, la_17_32_pct,
        
#         # Contact quality
#         hard_hit_pct, hard_hit_pct_rank,
#         barrel_pct, barrel_pct_rank,
#         avg_exit_velocity, avg_ev_rank
#       ) %>%
#       arrange(season, batter_name)
#   }
  
#   # 6. Write to CSV
#   output_path <- file.path(OUTPUT_DIR, "angles_history_player_season.csv")
#   write.csv(angles_with_percentiles, "data/processed/angles_history_player_season.csv")
#   cat("\nOutput saved to:", output_path, "\n")
  
#   # 7. Print summary statistics
#   cat("\n=== SUMMARY STATISTICS ===\n")
#   cat("Seasons covered:", paste(sort(unique(final_output$season)), collapse = ", "), "\n")
#   cat("Total player-seasons:", nrow(final_output), "\n")
#   cat("Unique players:", n_distinct(final_output$batter_name), "\n")
  
#   # Find players with multiple seasons
#   multi_season_players <- final_output %>%
#     group_by(batter_name) %>%
#     summarise(seasons_count = n_distinct(season), .groups = "drop") %>%
#     filter(seasons_count > 1)
  
#   cat("Players with 2+ seasons:", nrow(multi_season_players), "\n")
  
#   # Spot-check the focal players
#   focal_players <- c("Hamilton, David", "Donovan, Brendan", "Horwitz, Spencer")
#   cat("\n=== FOCAL PLAYERS CHECK ===\n")
#   for (player in focal_players) {
#     player_data <- final_output %>% filter(batter_name == player)
#     if (nrow(player_data) > 0) {
#       cat("\n", player, ":\n")
#       print(player_data %>% select(season, batter_name, sweet_spot_pct, sweet_spot_pct_rank, 
#                                      oppo_fb_pct, oppo_fb_pct_rank, oppo_fb_ev, oppo_fb_ev_pct_rank))
#     } else {
#       cat("\n", player, ": NOT FOUND in dataset\n")
#     }
#   }
  
#   return(final_output)
# }

# # =============================================================================
# # Execute
# # =============================================================================

# # Run the pipeline
# angles_data <- build_angles_history()

# cat("\n✓ Step 1 complete: Historical angles dataset created.\n")

