#!/usr/bin/env Rscript
# ==============================================================================
# RECOMMENDED WORKFLOW: Train Once, Predict on Demand
# ==============================================================================
# This shows how to use the trained network for ad-hoc analysis
# Much faster and more flexible than pre-computing all predictions

library(tidyverse)
library(data.table)
library(bnlearn)

# ==============================================================================
# STEP 1: Train Network (One Time Only)
# ==============================================================================

cat("\n=== STEP 1: Train Network (run once, save forever) ===\n\n")

# Source orchestration script
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_orchestrate.R")

# Run full pipeline - this trains the network and saves it
results <- run_full_pipeline(
  # Optional: limit to smaller sample for faster testing
  # sample_size = 10000  # Comment out to use all data
)

# Network is now saved to disk at:
# /Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/fitted_network.rds
# /Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/discretization_scheme.rds

# ==============================================================================
# STEP 2: Load Network (For Any Later Analysis)
# ==============================================================================

cat("\n=== STEP 2: Load Saved Network ===\n\n")

# Load the trained network
fitted_bn <- readRDS(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/fitted_network.rds"
)

# Load the discretization scheme
discretization_scheme <- readRDS(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/discretization_scheme.rds"
)

cat("✓ Network loaded\n")
cat("✓ Discretization scheme loaded\n")

# ==============================================================================
# STEP 3: Load Smaller Sample of Data
# ==============================================================================

cat("\n=== STEP 3: Load Sample Data ===\n\n")

# Example: Load just 1000 pitches for analysis
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

# Query specific subset (e.g., one team, date range, pitcher, etc.)
sample_data <- DBI::dbGetQuery(conn,
  "SELECT * FROM sc_milb 
   WHERE game_date >= '2026-04-01' AND game_date <= '2026-04-30'
   AND pitcher.handedness = 'R'
   LIMIT 1000"
)

sample_data <- long_df %>%
    filter(details.isInPlay == TRUE)

cat("✓ Loaded", nrow(sample_data), "pitches\n")

# ==============================================================================
# STEP 4: Preprocess Your Sample
# ==============================================================================

cat("\n=== STEP 4: Preprocess Sample Data ===\n\n")

milb_norm <- normalize_milb_field_names(sample_data)
milb_spray <- normalize_milb_spray_angle(milb_norm)
milb_disc <- discretize_milb_variables(milb_spray, discretization_scheme)

milb_sel <- milb_disc %>%
  select(stand, zone, pitch_name, 
         launch_speed_binned, launch_angle_binned, spray_angle_normalized,
         matchup.batter.id, matchup.batter.fullName, game_date) %>%
  rename(
    launch_speed = launch_speed_binned,
    launch_angle = launch_angle_binned,
    spray_angle = spray_angle_normalized
  )

milb_factors <- convert_to_network_factors(milb_sel, 
  # Need training data for factor levels - you can save this too
  training_data = readRDS("/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/training_data.rds")
)

cat("✓ Data preprocessed and ready for inference\n")

# ==============================================================================
# STEP 5: Apply Network to Your Sample (Fast!)
# ==============================================================================

cat("\n=== STEP 5: Run Inference ===\n\n")

source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")

inference_results <- infer_biomechanics_batch(
  fitted_bn,
  milb_factors,
  query_nodes = c(
    "attack_angle", "swing_path_tilt", 
    "attack_direction", "bat_speed", "intercept_x", "intercept_y"
  ),
  method = "exact",
  verbose = TRUE
)

cat("\n✓ Inference complete on", length(inference_results), "pitches\n")

# ==============================================================================
# STEP 6: Format Results (Only If Needed)
# ==============================================================================

cat("\n=== STEP 6: Format Results ===\n\n")

# Option A: Wide format (one row per pitch)
predictions_wide <- format_inference_results_wide(inference_results, milb_factors)
cat("Wide format:", nrow(predictions_wide), "pitches ×", ncol(predictions_wide), "columns\n")
print(head(predictions_wide))

# Option B: Long format (one row per pitch × variable × level)
predictions_long <- format_inference_results_long(inference_results, milb_factors)
cat("\nLong format:", nrow(predictions_long), "rows\n")
print(head(predictions_long))

# ==============================================================================
# STEP 7: Do Your Analysis
# ==============================================================================

cat("\n=== STEP 7: Your Analysis ===\n\n")

# Now combine with your sample data and do analysis
sample_with_predictions <- milb_factors %>%
  bind_cols(predictions_wide %>% select(-pitch_id))

# Example analyses:
cat("Average attack angle for RHH vs LHH:\n")
print(sample_with_predictions %>%
  group_by(stand) %>%
  summarise(avg_attack = mean(attack_angle_confidence, na.rm = TRUE)))

cat("\nPrediction confidence by zone:\n")
print(sample_with_predictions %>%
  group_by(zone) %>%
  summarise(
    mean_conf = mean(c(attack_angle_confidence, swing_path_tilt_confidence), na.rm = TRUE),
    n = n()
  ))

DBI::dbDisconnect(conn)

cat("\n✓ Analysis complete!\n\n")

# ==============================================================================
# KEY BENEFITS OF THIS WORKFLOW
# ==============================================================================
cat("\nBENEFITS:\n")
cat("  ✓ Network trained once, used many times\n")
cat("  ✓ No need to store predictions for all 326K pitches\n")
cat("  ✓ Predict on any subset, any time\n")
cat("  ✓ Easy to update network when new data arrives\n")
cat("  ✓ Flexible - filter data before inference, not after\n")
cat("\n")
