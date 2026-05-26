# Quick test of updated cohort definitions
# Tests: Simple poor loft definition, angles score-based tiers

library(dplyr)
library(readr)

# Load existing angles history
angles_data <- read.csv("report-agent/data/processed/angles_history_player_season.csv")

# Recreate classification with NEW logic
OPPO_FB_PCT_POOR_THRESHOLD <- 60
OPPO_FB_EV_POOR_THRESHOLD <- 40
HHLA_WEIGHT <- 0.33
AVG_LA_WEIGHT <- 0.33
IDEAL_AA_WEIGHT <- 0.34
EXCELLENT_ANGLES_THRESHOLD <- 75
GOOD_ANGLES_THRESHOLD <- 60

loft_classified <- angles_data %>%
  mutate(
    # LOFT: Simple thresholds (no score)
    poor_loft = (oppo_fb_pct_rank >= OPPO_FB_PCT_POOR_THRESHOLD & 
                 oppo_fb_ev_rank <= OPPO_FB_EV_POOR_THRESHOLD),
    
    loft_cohort = case_when(
      poor_loft ~ "Poor Loft",
      TRUE ~ "Non-Poor Loft"
    ),
    
    # ANGLES SCORE: Weighted composite of 3 KPIs
    hhla_norm = hard_hit_pct_rank / 100,
    avg_la_norm = launch_angle_avg_rank / 100,
    ideal_aa_norm = high_aa_pct_rank / 100,
    
    angles_score = (
      hhla_norm * HHLA_WEIGHT +
      avg_la_norm * AVG_LA_WEIGHT +
      ideal_aa_norm * IDEAL_AA_WEIGHT
    ),
    
    angles_tier = case_when(
      angles_score >= EXCELLENT_ANGLES_THRESHOLD / 100 ~ "Excellent",
      angles_score >= GOOD_ANGLES_THRESHOLD / 100 ~ "Good",
      TRUE ~ "Below Average"
    ),
    
    # INTERACTION COHORTS
    interaction_cohort = case_when(
      poor_loft & angles_tier %in% c("Good", "Excellent") ~ "Poor Loft + Good Angles",
      !poor_loft & angles_tier %in% c("Good", "Excellent") ~ "Non-Poor Loft + Good Angles",
      TRUE ~ "Excluded from Analysis"
    )
  )

cat("\n=== NEW DEFINITION TEST ===\n")
cat("Poor Loft Criteria: Oppo FB% >= 60th percentile AND Oppo FB EV <= 40th percentile\n")
cat("Angles Score: 40% HHLA + 35% Avg LA + 25% Ideal AA Rate\n\n")

# Loft distribution
cat("LOFT DISTRIBUTION:\n")
loft_dist <- loft_classified %>%
  group_by(loft_cohort) %>%
  summarise(n = n(), pct = 100 * n() / nrow(loft_classified), .groups = "drop")
print(loft_dist)

# Angles distribution
cat("\nANGLES DISTRIBUTION:\n")
angles_dist <- loft_classified %>%
  group_by(angles_tier) %>%
  summarise(n = n(), pct = 100 * n() / nrow(loft_classified), .groups = "drop")
print(angles_dist)

# Cohort distribution
cat("\nCOHORT DISTRIBUTION (GOOD/EXCELLENT ANGLES ONLY):\n")
cohort_dist <- loft_classified %>%
  filter(interaction_cohort != "Excluded from Analysis") %>%
  group_by(interaction_cohort) %>%
  summarise(
    n = n(),
    pct = 100 * n() / nrow(loft_classified),
    .groups = "drop"
  )
print(cohort_dist)

# Cohort characteristics
cat("\nCOHORT CHARACTERISTICS:\n")
cohort_char <- loft_classified %>%
  filter(interaction_cohort != "Excluded from Analysis") %>%
  group_by(interaction_cohort) %>%
  summarise(
    n = n(),
    mean_angles_score = mean(angles_score, na.rm = TRUE),
    mean_oppo_fb_pct = mean(oppo_fb_pct, na.rm = TRUE),
    mean_oppo_fb_ev = mean(oppo_fb_ev, na.rm = TRUE),
    mean_hhla = mean(hard_hit_pct, na.rm = TRUE),
    mean_avg_la = mean(launch_angle_avg, na.rm = TRUE),
    mean_ideal_aa = mean(high_aa_pct, na.rm = TRUE),
    .groups = "drop"
  )
print(cohort_char)

cat("\n=== FOCAL PLAYERS ===\n\n")
focal_players <- c("Hamilton, David", "Donovan, Brendan", "Horwitz, Spencer")
for (player in focal_players) {
  player_data <- loft_classified %>% filter(batter_name == player)
  if (nrow(player_data) > 0) {
    cat(player, ":\n")
    cat("  Poor Loft:", player_data$poor_loft, "\n")
    cat("  Loft Cohort:", player_data$loft_cohort, "\n")
    cat("    - Oppo FB%:", round(player_data$oppo_fb_pct, 1), "% (rank:", player_data$oppo_fb_pct_rank, ")\n")
    cat("    - Oppo FB EV:", round(player_data$oppo_fb_ev, 1), " mph (rank:", player_data$oppo_fb_ev_rank, ")\n")
    cat("  Angles Score:", round(player_data$angles_score, 3), "\n")
    cat("  Angles Tier:", player_data$angles_tier, "\n")
    cat("    - HHLA:", round(player_data$hard_hit_pct, 1), "% (rank:", player_data$hard_hit_pct_rank, ")\n")
    cat("    - Avg LA:", round(player_data$launch_angle_avg, 1), "° (rank:", player_data$launch_angle_avg_rank, ")\n")
    cat("    - Ideal AA Rate:", round(player_data$high_aa_pct, 1), "% (rank:", player_data$high_aa_pct_rank, ")\n")
    cat("  Interaction Cohort:", player_data$interaction_cohort, "\n\n")
  }
}

