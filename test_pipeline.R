#!/usr/bin/env Rscript
# ==============================================================================
# End-to-End Test of Bayesian Network Pipeline
# ==============================================================================

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n=== BAYESIAN NETWORK PIPELINE TEST ===\n")

# ==============================================================================
# STEP 1: Load modules
# ==============================================================================
cat("\n[1/5] Loading modules...\n")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

cat("✓ All modules loaded\n")

# ==============================================================================
# STEP 2: Create network and prepare training data
# ==============================================================================
cat("\n[2/5] Setting up network structure...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()
cat("✓ Network created:", length(nodes(bn)), "nodes\n")

cat("\n[3/5] Preparing MLB training data...\n")
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)
cat("✓ Training data:", nrow(training_data), "pitches\n")

# ==============================================================================
# STEP 3: Learn network parameters
# ==============================================================================
cat("\n[4/5] Learning network parameters...\n")
tryCatch({
  fitted_bn <- learn_network_parameters(
    training_data = training_data,
    bn_structure = bn,
    method = "bayes",
    smoothing = 1
  )
  cat("✓ Parameters learned successfully\n")
  
  # Save the trained network
  output_dir <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  saveRDS(fitted_bn, file.path(output_dir, "fitted_network.rds"))
  cat("✓ Network saved to fitted_network.rds\n")
  
}, error = function(e) {
  cat("✗ ERROR during parameter learning:\n")
  print(e)
})

# ==============================================================================
# STEP 4: Test inference on MiLB data
# ==============================================================================
cat("\n[5/5] Testing inference on MiLB data...\n")

tryCatch({
  # Prepare MiLB data with factor conversion
  cat("  - Loading and preprocessing MiLB data...\n")
  milb_for_inference <- prepare_milb_for_inference(
    raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
    discretization_scheme = discretization_scheme,
    training_data = training_data
  )
  cat("  - MiLB data ready:", nrow(milb_for_inference), "pitches\n")
  
  # Verify data types before inference
  cat("  - Verifying factor types:\n")
  cat("    * stand:", class(milb_for_inference$stand), "\n")
  cat("    * zone:", class(milb_for_inference$zone), "\n")
  cat("    * pitch_name:", class(milb_for_inference$pitch_name), "\n")
  
  # Run inference
  cat("  - Running inference...\n")
  results <- apply_network_to_milb(fitted_bn, milb_for_inference)
  
  cat("✓ Inference complete\n")
  cat("  - Long format:", nrow(results$predictions_long), "rows\n")
  cat("  - Wide format:", nrow(results$predictions_wide), "rows\n")
  cat("  - Confidence summary:", nrow(results$confidence), "rows\n")
  
  # Show sample results
  cat("\nSample predictions (first 3 pitches):\n")
  print(head(results$predictions_wide, 3))
  
  cat("\n✓ PIPELINE TEST SUCCESSFUL\n")
  
}, error = function(e) {
  cat("✗ ERROR during inference:\n")
  print(e)
  cat("\nStack trace:\n")
  traceback()
})

cat("\n=== TEST COMPLETE ===\n")
