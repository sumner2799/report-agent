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

# =============================================================================
# LOFT DEFINITION (Simple thresholds, no score)
# =============================================================================
# Poor Loft = Oppo FB% >= 60th percentile AND Oppo FB EV <= 40th percentile
OPPO_FB_PCT_POOR_THRESHOLD <- 60  # percentile
OPPO_FB_EV_POOR_THRESHOLD <- 40   # percentile (inverted: low EV is bad)

# =============================================================================
# ANGLES QUALITY SCORE (Weighted composite of 3 KPIs)
# =============================================================================
# 1. Hard Hit Launch Angle (HHLA) - % of BBE in hard-hit sweet spot zone
# 2. Average Launch Angle (Avg LA) - mean LA, ideally 10-20°
# 3. Ideal Attack Angle Rate - % of PA with "ideal" attack angle (>15°)

# Weights for angles score
HHLA_WEIGHT <- 0.25
AVG_LA_WEIGHT <- 0.25
HHLA_WEIGHT_old <- 0.33
AVG_LA_WEIGHT_old <- 0.33
IDEAL_AA_WEIGHT <- 0.25
SWSPOT_WEIGHT <- 0.25
SWSPOT_WEIGHT_old <- 0.34

# Angles tier thresholds
EXCELLENT_ANGLES_THRESHOLD <- 75  # 75th+ percentile
GOOD_ANGLES_THRESHOLD <- 50.25       # 60th+ percentile

# =============================================================================
# Main Classification Function
# =============================================================================

# classify_loft_profiles <- function() {
#   cat("Classifying loft profiles...\n")
  
#   # Load angles history data
#   input_file <- file.path(DATA_DIR, "angles_history_player_season.csv")
#   if (!file.exists(input_file)) {
#     stop("Input file not found: ", input_file)
#   }
  
  angles_data <- read_csv(input_file, show_col_types = FALSE)
  angles_data <- read.csv("report-agent/data/processed/angles_history_player_season.csv") 
  cat("Loaded", nrow(angles_data), "player-season records.\n")
  
  # Step 1: Calculate loft deficiency score
  # Composite score using percentile ranks across all players
  # Higher score = worse loft
  
  loft_classified <- angles_data %>%
    mutate(
      # LOFT DEFINITION (Simple thresholds - no score needed)
      # Poor Loft: Oppo FB% >= 60th percentile AND Oppo FB EV <= 40th percentile
      poor_loft = (oppo_fb_pct_rank >= OPPO_FB_PCT_POOR_THRESHOLD & 
                   oppo_fb_ev_pct_rank <= OPPO_FB_EV_POOR_THRESHOLD),
      
      loft_cohort = case_when(
        poor_loft ~ "Poor Loft",
        TRUE ~ "Non-Poor Loft"
      ),
      
      # ANGLES QUALITY SCORE (Weighted composite)
      # Using percentile ranks for: HHLA, Avg LA, Ideal AA Rate
      hhla_norm = hard_hit_pct_rank / 100,           # Hard Hit Launch Angle
      avg_la_norm = launch_angle_avg_rank / 100,     # Average Launch Angle
      ideal_aa_norm = high_aa_pct_rank / 100,        # Ideal Attack Angle Rate (>15°)
      sweet_spot_norm = sweet_spot_pct_rank / 100,  # Sweet Spot % (added for 2025+)
      
      angles_score = ifelse(season %in% c(2025,2026),(
        hhla_norm * HHLA_WEIGHT +
        avg_la_norm * AVG_LA_WEIGHT +
        ideal_aa_norm * IDEAL_AA_WEIGHT +
        sweet_spot_norm * SWSPOT_WEIGHT
      ),(
        hhla_norm * HHLA_WEIGHT_old +
        avg_la_norm * AVG_LA_WEIGHT_old +
        sweet_spot_norm * SWSPOT_WEIGHT_old
      )),
      
      # Classify angles performance based on composite score
      angles_tier = case_when(
        angles_score >= EXCELLENT_ANGLES_THRESHOLD / 100 ~ "Excellent",
        angles_score >= GOOD_ANGLES_THRESHOLD / 100 ~ "Good",
        TRUE ~ "Below Average"
      ),
      
      # INTERACTION COHORTS (2 groups for focused analysis)
      interaction_cohort = case_when(
        poor_loft & angles_tier %in% c("Good", "Excellent") ~ "Poor Loft + Good Angles",
        !poor_loft & angles_tier %in% c("Good", "Excellent") ~ "Non-Poor Loft + Good Angles",
        TRUE ~ "Excluded from Analysis"
      ),

      swspt_cohort = case_when(
        poor_loft & sweet_spot_pct_rank >= 65 ~ "Poor Loft + Good Angles",
        !poor_loft & sweet_spot_pct_rank >= 65 ~ "Non-Poor Loft + Good Angles",
        TRUE ~ "Excluded from Analysis"
      )
    )
    #  %>%
    # select(
    #   season, last_first_name, total_bbe,
      
    #   # Loft metrics (raw + ranks + normalized)
    #   oppo_fb_pct, oppo_fb_pct_rank, oppo_fb_pct_norm,
    #   oppo_fb_ev, oppo_fb_ev_pct_rank, oppo_fb_ev_norm,
    #   high_aa_pct, high_aa_pct_rank, high_aa_pct_norm,
    #   attack_angle_avg, attack_angle_avg_rank,
    #   attack_angle_std,
      
    #   # Loft deficiency score
    #   loft_deficiency_score, loft_cohort,
      
    #   # Angles quality metrics
    #   sweet_spot_pct, sweet_spot_pct_rank,
    #   launch_angle_avg, launch_angle_avg_rank,
    #   launch_angle_std,
    #   la_8_16_pct, la_17_32_pct,
      
    #   # Angles tier
    #   angles_tier,
      
    #   # Interaction cohort
    #   interaction_cohort,
      
    #   # Contact quality (reference)
    #   hard_hit_pct, hard_hit_pct_rank,
    #   barrel_pct, barrel_pct_rank,
    #   avg_exit_velocity, avg_ev_rank
    # ) %>%
    # arrange(season, loft_cohort, interaction_cohort, batter_name)
  
  # Write output
  output_file <- file.path(DATA_DIR, "loft_profile_classification.csv")
  write.csv(loft_classified, "report-agent/data/processed/loft_profile_classification.csv")
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
    summarise(count = n(), pct = 100 * n() / nrow(loft_classified), .groups = "drop") %>%
    arrange(desc(count))
  print(interaction_dist)
  
  cat("\nNote: Focused analysis on players with GOOD/EXCELLENT angles only.\n")
  good_angles <- loft_classified %>%
    filter(angles_tier %in% c("Good", "Excellent"))
  cat("Players with Good/Excellent angles:", nrow(good_angles), 
      "(" %+% round(100 * nrow(good_angles) / nrow(loft_classified), 1) %+% "%)\n")
  
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


loft <- loft_classified %>%
  filter(loft_cohort == "Poor Loft")
