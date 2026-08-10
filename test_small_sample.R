#!/usr/bin/env Rscript
# ==============================================================================
# Quick Test: Preprocessing + Inference on 10 Pitches
# ==============================================================================
# This tests the complete pipeline on a small sample to find where it breaks

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     QUICK TEST: Preprocessing + Inference (10 Pitches)        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Load modules
cat("\n[Setup] Loading modules...\n")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# ==============================================================================
# STEP 1: Create network and train
# ==============================================================================

cat("\n[1/5] Creating network...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()

cat("[2/5] Preparing training data...\n")
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)
cat(sprintf("✓ Training data: %d rows\n", nrow(training_data)))

cat("[3/5] Learning network parameters...\n")
tryCatch({
  fitted_bn <- learn_network_parameters(
    training_data = training_data,
    bn_structure = bn,
    method = "bayes",
    smoothing = 1
  )
  cat("✓ Network parameters learned\n")
}, error = function(e) {
  cat(sprintf("✗ ERROR: %s\n", as.character(e)))
  stop("Cannot continue without trained network")
})

# ==============================================================================
# STEP 2: Prepare MiLB data (SMALL SAMPLE)
# ==============================================================================

cat("\n[4/5] Preparing MiLB data (first 10 pitches)...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

# Get only 10 pitches
milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 10"
)

cat(sprintf("✓ Raw data: %d rows\n", nrow(milb_raw)))

# Process through pipeline
cat("  • Normalizing field names...\n")
milb_norm <- normalize_milb_field_names(milb_raw)

cat("  • Normalizing spray angle...\n")
milb_spray <- normalize_milb_spray_angle(milb_norm)

cat("  • Discretizing variables...\n")
milb_disc <- discretize_milb_variables(milb_spray, discretization_scheme)

cat("  • Selecting columns...\n")
milb_sel <- milb_disc %>%
  select(stand, zone, pitch_name, 
         launch_speed_binned, launch_angle_binned, spray_angle_normalized,
         matchup.batter.id, matchup.batter.fullName, game_date) %>%
  rename(
    launch_speed = launch_speed_binned,
    launch_angle = launch_angle_binned,
    spray_angle = spray_angle_normalized
  )

cat(sprintf("  • Before factor conversion: %d rows\n", nrow(milb_sel)))

cat("  • Converting to factors...\n")
tryCatch({
  milb_factors <- convert_to_network_factors(milb_sel, training_data)
  cat(sprintf("    ✓ After factor conversion: %d rows\n", nrow(milb_factors)))
  
  # Check data types
  cat("    Evidence column types:\n")
  for (col in c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")) {
    if (col %in% colnames(milb_factors)) {
      cat(sprintf("      %s: %s\n", col, class(milb_factors[[col]])))
    }
  }
}, error = function(e) {
  cat(sprintf("    ✗ ERROR: %s\n", as.character(e)))
  stop("Factor conversion failed")
})

cat("  • Adding hidden biomechanics...\n")
milb_final <- milb_factors %>%
  mutate(
    attack_angle = factor(NA_character_, levels = discretization_scheme$attack_angle$levels),
    swing_path_tilt = factor(NA_character_, levels = discretization_scheme$swing_path_tilt$levels),
    attack_direction = factor(NA_character_, levels = discretization_scheme$attack_direction$levels),
    bat_speed = factor(NA_character_, levels = discretization_scheme$bat_speed$levels),
    intercept_x = factor(NA_character_, levels = discretization_scheme$intercept_x$levels),
    intercept_y = factor(NA_character_, levels = discretization_scheme$intercept_y$levels),
    outcome = factor(NA_character_, levels = c("hit", "out", "strikeout"))
  ) %>%
  filter(!is.na(stand) & !is.na(zone) & !is.na(pitch_name)) %>%
  filter(!is.na(launch_angle) | !is.na(launch_speed) | !is.na(spray_angle))

cat(sprintf("✓ Final data ready: %d rows (after filtering)\n", nrow(milb_final)))

# ==============================================================================
# STEP 3: Run inference
# ==============================================================================

cat("\n[5/5] Running inference...\n")

tryCatch({
  inference_results <- infer_biomechanics_batch(
    fitted_bn,
    milb_final,
    query_nodes = c(
      "attack_angle", "swing_path_tilt", 
      "attack_direction", "bat_speed", "intercept_x", "intercept_y"
    ),
    method = "exact",
    verbose = TRUE
  )
  
  cat("\n=== INFERENCE RESULTS ===\n")
  cat(sprintf("Total results returned: %d\n", length(inference_results))
  )
  
  # Check results
  n_empty <- sum(sapply(inference_results, function(x) length(x) == 0))
  n_nonempty <- sum(sapply(inference_results, function(x) length(x) > 0))
  
  cat(sprintf("  Empty results: %d\n", n_empty))
  cat(sprintf("  Non-empty results: %d\n", n_nonempty))
  
  # Show first non-empty result
  cat("\nFirst non-empty result structure:\n")
  for (i in seq_along(inference_results)) {
    if (length(inference_results[[i]]) > 0) {
      cat(sprintf("  Pitch %d:\n", i))
      str(inference_results[[i]], max.level=2)
      break
    }
  }
  
  if (n_nonempty > 0) {
    cat("\n✅ SUCCESS: Inference returned non-empty results\n")
  } else {
    cat("\n❌ FAILURE: All inference results are empty\n")
    cat("\nDiagnostics:\n")
    cat("  1. Check factor types above - should all be 'factor'\n")
    cat("  2. Check if training_data has proper factor levels\n")
    cat("  3. Run: Rscript diagnostic_preprocessing.R\n")
  }
  
}, error = function(e) {
  cat(sprintf("\n✗ ERROR during inference: %s\n", as.character(e)))
  traceback()
})

DBI::dbDisconnect(conn)

cat("\n")
