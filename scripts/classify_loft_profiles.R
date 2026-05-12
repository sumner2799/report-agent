# Step 2: Classify Players by Loft Profile
# Creates loft deficiency scores and cohort classifications
# Input: data/processed/angles_history_player_season.csv
# Output: data/processed/loft_profile_classification.csv

library(dplyr)
library(tidyr)
library(readr)

# =============================================================================
# Configuration
# =============================================================================

DATA_DIR <- "data/processed"

# Loft deficiency score weights
OPPO_FB_PCT_WEIGHT <- 0.40
OPPO_FB_EV_WEIGHT <- 0.35
HIGH_AA_PCT_WEIGHT <- 0.25

# Loft cohort thresholds
POOR_LOFT_THRESHOLD <- 0.60
GOOD_LOFT_THRESHOLD <- 0.35

# Sweet spot (angles quality) thresholds
EXCELLENT_ANGLES_THRESHOLD <- 75
GOOD_ANGLES_THRESHOLD <- 60
AVERAGE_ANGLES_LOWER <- 40

# =============================================================================
# Main Classification Function
# =============================================================================

classify_loft_profiles <- function() {
  cat("Classifying loft profiles...\n")
  
  # Load angles history data
  input_file <- file.path(DATA_DIR, "angles_history_player_season.csv")
  if (!file.exists(input_file)) {
    stop("Input file not found: ", input_file)
  }
  
  angles_data <- read_csv(input_file, show_col_types = FALSE)
  cat("Loaded", nrow(angles_data), "player-season records.\n")
  
  # Step 1: Calculate loft deficiency score
  # Composite score using percentile ranks across all players
  # Higher score = worse loft
  
  loft_classified <- angles_data %>%
    mutate(
      # Normalize percentile ranks to 0-1 scale
      oppo_fb_pct_norm = oppo_fb_pct_rank / 100,
      oppo_fb_ev_norm = (100 - oppo_fb_ev_pct_rank) / 100,  # Inverse (low EV = bad)
      high_aa_pct_norm = (100 - high_aa_pct_rank) / 100,    # Inverse (low AA% = bad)
      
      # Composite loft deficiency score (0-1 scale)
      loft_deficiency_score = (
        oppo_fb_pct_norm * OPPO_FB_PCT_WEIGHT +
        oppo_fb_ev_norm * OPPO_FB_EV_WEIGHT +
        high_aa_pct_norm * HIGH_AA_PCT_WEIGHT
      ),
      
      # Classify loft profile
      loft_cohort = case_when(
        loft_deficiency_score < GOOD_LOFT_THRESHOLD ~ "Good Loft",
        loft_deficiency_score < POOR_LOFT_THRESHOLD ~ "Neutral Loft",
        TRUE ~ "Poor Loft"
      ),
      
      # Classify angles performance
      angles_tier = case_when(
        sweet_spot_pct_rank >= EXCELLENT_ANGLES_THRESHOLD ~ "Excellent",
        sweet_spot_pct_rank >= GOOD_ANGLES_THRESHOLD ~ "Good",
        sweet_spot_pct_rank >= AVERAGE_ANGLES_LOWER ~ "Average",
        TRUE ~ "Below Average"
      ),
      
      # Interaction cohort (primary focus)
      interaction_cohort = case_when(
        loft_cohort == "Poor Loft" & angles_tier == "Excellent" ~ "Compensators",
        (loft_cohort == "Neutral Loft" | loft_cohort == "Good Loft") & angles_tier == "Excellent" ~ "Structural",
        loft_cohort == "Poor Loft" & angles_tier %in% c("Average", "Below Average") ~ "Rebuilders",
        (loft_cohort == "Neutral Loft" | loft_cohort == "Good Loft") & angles_tier %in% c("Average", "Below Average") ~ "Underperformers",
        TRUE ~ "Other"
      )
    ) %>%
    select(
      season, batter, batter_name, total_bbe,
      
      # Loft metrics (raw + ranks + normalized)
      oppo_fb_pct, oppo_fb_pct_rank, oppo_fb_pct_norm,
      oppo_fb_ev, oppo_fb_ev_pct_rank, oppo_fb_ev_norm,
      high_aa_pct, high_aa_pct_rank, high_aa_pct_norm,
      attack_angle_avg, attack_angle_avg_rank,
      attack_angle_std,
      
      # Loft deficiency score
      loft_deficiency_score, loft_cohort,
      
      # Angles quality metrics
      sweet_spot_pct, sweet_spot_pct_rank,
      launch_angle_avg, launch_angle_avg_rank,
      launch_angle_std,
      la_8_16_pct, la_17_32_pct,
      
      # Angles tier
      angles_tier,
      
      # Interaction cohort
      interaction_cohort,
      
      # Contact quality (reference)
      hard_hit_pct, hard_hit_pct_rank,
      barrel_pct, barrel_pct_rank,
      avg_exit_velocity, avg_ev_rank
    ) %>%
    arrange(season, loft_cohort, interaction_cohort, batter_name)
  
  # Write output
  output_file <- file.path(DATA_DIR, "loft_profile_classification.csv")
  write_csv(loft_classified, output_file)
  cat("\nOutput saved to:", output_file, "\n")
  
  # Print summary statistics
  cat("\n=== CLASSIFICATION SUMMARY ===\n")
  
  cat("\nLoft Cohort Distribution:\n")
  loft_dist <- loft_classified %>%
    group_by(loft_cohort) %>%
    summarise(count = n(), .groups = "drop") %>%
    arrange(desc(count))
  print(loft_dist)
  
  cat("\nAngles Tier Distribution:\n")
  angles_dist <- loft_classified %>%
    group_by(angles_tier) %>%
    summarise(count = n(), .groups = "drop") %>%
    arrange(desc(count))
  print(angles_dist)
  
  cat("\nInteraction Cohort Distribution:\n")
  interaction_dist <- loft_classified %>%
    group_by(interaction_cohort) %>%
    summarise(count = n(), .groups = "drop") %>%
    arrange(desc(count))
  print(interaction_dist)
  
  cat("\nCross-Tabulation (Loft x Angles):\n")
  cross_tab <- loft_classified %>%
    group_by(loft_cohort, angles_tier) %>%
    summarise(count = n(), .groups = "drop") %>%
    pivot_wider(names_from = angles_tier, values_from = count, values_fill = 0)
  print(cross_tab)
  
  # Focal players summary
  cat("\n=== FOCAL PLAYERS LOFT PROFILES ===\n")
  focal_players <- c("Hamilton, David", "Donovan, Brendan", "Horwitz, Spencer")
  for (player in focal_players) {
    player_data <- loft_classified %>% filter(batter_name == player)
    if (nrow(player_data) > 0) {
      cat("\n", player, ":\n")
      print(player_data %>% select(
        season, loft_deficiency_score, loft_cohort, 
        sweet_spot_pct, angles_tier, interaction_cohort,
        oppo_fb_pct, oppo_fb_ev, high_aa_pct,
        attack_angle_avg
      ))
    } else {
      cat("\n", player, ": NOT FOUND\n")
    }
  }
  
  cat("\n✓ Step 2 complete: Loft profile classification created.\n")
  
  return(loft_classified)
}

# =============================================================================
# Execute
# =============================================================================

loft_data <- classify_loft_profiles()
