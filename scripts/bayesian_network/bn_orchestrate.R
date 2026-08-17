# ==============================================================================
# Bayesian Network Orchestration Script
# ==============================================================================
# Purpose: Master script to coordinate all steps:
# 1. Define network structure + domain knowledge
# 2. Prepare and learn from MLB training data
# 3. Apply to MiLB data for imputation
# 4. Validate and iterate when real data arrives
#
# Usage:
#   source("bn_orchestrate.R")
#   Then run individual sections or full pipeline

library(tidyverse)
library(data.table)
library(bnlearn)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

CONFIG <- list(
  # Data paths
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  output_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation",
  
  # Network parameters
  learning_method = "bayes",  # "bayes" or "mle"
  smoothing_parameter = 1,    # Laplace smoothing (Imaginary Sample Size)
  inference_method = "exact",  # "exact" or "ls" (likelihood sampling)
  confidence_threshold = 0.4,  # Flag predictions below this confidence
  
  # Data preparation
  min_data_retention = 0.80,   # Minimum % of complete cases to keep
  
  # Variables to infer
  query_nodes = c(
    "attack_angle",
    "swing_path_tilt",
    # "contact_depth",
    "attack_direction",
    "bat_speed",
    "intercept_x",
    "intercept_y"
  )
)

# Create output directory
if (!dir.exists(CONFIG$output_dir)) {
  dir.create(CONFIG$output_dir, recursive = TRUE)
}

cat("Configuration loaded. Output directory:", CONFIG$output_dir, "\n")

# ==============================================================================
# SECTION 0: Source all modules
# ==============================================================================

source_all_modules <- function() {
  cat("\n=== Sourcing Bayesian Network Modules ===\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
  cat("✓ Network definition loaded\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
  cat("✓ Data preparation loaded\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
  cat("✓ Parameter learning loaded\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
  cat("✓ Inference engine loaded\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")
  cat("✓ MiLB application loaded\n")
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_validation_framework.R")
  cat("✓ Validation framework loaded\n")
}

# ==============================================================================
# SECTION 1: Define Network Structure
# ==============================================================================

setup_network <- function() {
  cat("\n=== SECTION 1: Network Definition ===\n")
  
  # Create DAG with domain knowledge
  bn <- create_biomech_network()
  cat("\n✓ DAG created with", length(nodes(bn)), "nodes\n")
  
  # Validate structure
  validate_network_structure(bn)
  
  # Create discretization scheme
  discretization_scheme <- create_discretization_scheme()
  cat("\n✓ Discretization scheme defined\n")
  
  return(list(
    bn = bn,
    discretization_scheme = discretization_scheme
  ))
}

# ==============================================================================
# SECTION 2: Prepare Training Data
# ==============================================================================

prepare_training <- function(network_config) {
  cat("\n=== SECTION 2: Data Preparation (MLB Training) ===\n")
  
  training_data <- prepare_training_data(
    discretization_scheme = network_config$discretization_scheme,
    min_data_quality_threshold = CONFIG$min_data_retention
  )
  
  return(training_data)
}

# ==============================================================================
# SECTION 3: Learn Network Parameters
# ==============================================================================

learn_parameters <- function(training_data, network_config) {
  cat("\n=== SECTION 3: Parameter Learning (from MLB) ===\n")
  
  # Compare methods if desired
  cat("\nLearning with method:", CONFIG$learning_method, "\n")
  
  fitted_bn <- learn_network_parameters(
    training_data = training_data,
    bn_structure = network_config$bn,
    method = CONFIG$learning_method,
    smoothing = CONFIG$smoothing_parameter
  )
  
  # Inspect CPTs for key nodes
  cat("\n--- Sample CPTs ---\n")
  inspect_cpts(fitted_bn, node = "launch_angle")
  
  # Diagnose quality
  diagnose_parameter_quality(fitted_bn, training_data)
  
  # Export for later use
  network_path <- file.path(CONFIG$output_dir, "fitted_network.rds")
  export_network(fitted_bn, network_path)
  
  # Also save training data and discretization scheme for later inference
  saveRDS(training_data, file.path(CONFIG$output_dir, "training_data.rds"))
  saveRDS(network_config$discretization_scheme, file.path(CONFIG$output_dir, "discretization_scheme.rds"))
  
  cat("\n✓ Network components saved:\n")
  cat("  - fitted_network.rds\n")
  cat("  - training_data.rds (for factor levels)\n")
  cat("  - discretization_scheme.rds (for binning)\n")
  
  return(fitted_bn)
}

# ==============================================================================
# SECTION 4: Apply to MiLB Data
# ==============================================================================

apply_to_milb <- function(fitted_bn, network_config) {
  cat("\n=== SECTION 4: Apply Network to MiLB Data ===\n")
  
  # Prepare MiLB data
  milb_data <- prepare_milb_for_inference(
    discretization_scheme = network_config$discretization_scheme
  )
  
  # Run inference (without CSV export by default)
  imputation_results <- apply_network_to_milb(
    fitted_bn,
    milb_data,
    output_dir = CONFIG$output_dir,
    export_predictions = FALSE  # Don't create CSVs
  )
  
  # Create audit trail only if predictions were exported
  audit_trail <- NULL
  if (!is.null(imputation_results$predictions_wide)) {
    audit_trail <- create_audit_trail(
      milb_data,
      imputation_results$predictions_wide,
      output_path = file.path(CONFIG$output_dir, "audit_trail.csv")
    )
  } else {
    cat("\nSkipping audit trail (export_predictions=FALSE)\n")
  }
  
  return(list(
    results = imputation_results,
    milb_data = milb_data,
    audit_trail = audit_trail
  ))
}

# ==============================================================================
# SECTION 5: Validation (when real data arrives)
# ==============================================================================

validate_network <- function(imputation_results, actual_biomechanics_data = NULL) {
  cat("\n=== SECTION 5: Validation Against Actual Data ===\n")
  
  if (is.null(actual_biomechanics_data)) {
    cat("No actual data provided. Skipping validation.\n")
    cat("When MiLB biomechanics measurements become available:\n")
    cat("  1. Load actual data\n")
    cat("  2. Call validate_network() again with actual_biomechanics_data parameter\n")
    cat("  3. Use error patterns to refine network structure\n")
    return(NULL)
  }
  
  # Validate predictions
  validation_results <- validate_predictions(
    imputation_results$results$predictions_wide,
    actual_biomechanics_data,
    output_path = file.path(CONFIG$output_dir, "validation_report.csv")
  )
  
  # Analyze error patterns
  if (!is.null(imputation_results$milb_data)) {
    for (var in CONFIG$query_nodes) {
      analyze_error_patterns(
        imputation_results$results$predictions_wide,
        actual_biomechanics_data,
        imputation_results$milb_data,
        variable = var
      )
    }
  }
  
  # Get refinement suggestions
  recommendations <- generate_refinement_recommendations(validation_results)
  
  return(list(
    validation = validation_results,
    recommendations = recommendations
  ))
}

# ==============================================================================
# SECTION 6: Iteration & Refinement
# ==============================================================================

refine_network <- function(current_network, validation_results, changes_description) {
  cat("\n=== SECTION 6: Network Refinement ===\n")
  cat("Changes to make:", changes_description, "\n")
  
  # Log this iteration
  version_num <- paste0("v", format(Sys.time(), "%Y%m%d_%H%M%S"))
  log_network_version(
    version_number = version_num,
    changes_made = changes_description,
    validation_metrics = validation_results,
    notes = ""
  )
  
  cat("\n✓ Version", version_num, "logged\n")
  cat("Next steps:\n")
  cat("  1. Modify network structure in bn_network_definition.R\n")
  cat("  2. Re-run learn_parameters() to learn new CPTs\n")
  cat("  3. Re-run apply_to_milb() to generate new predictions\n")
  cat("  4. Re-run validate_network() to assess improvements\n")
}

# ==============================================================================
# FULL PIPELINE
# ==============================================================================

run_full_pipeline <- function() {
  cat("\n")
  cat("╔═══════════════════════════════════════════════════════════════╗\n")
  cat("║  Bayesian Network for Pitch-Level Biomechanics Imputation    ║\n")
  cat("║  Baseball Minor League Data                                   ║\n")
  cat("╚═══════════════════════════════════════════════════════════════╝\n")
  
  # Source all modules
  source_all_modules()
  
  # Step 1: Network definition
  network_config <- setup_network()
  
  # Step 2: Prepare training data
  training_data <- prepare_training(network_config)
  
  # Step 3: Learn parameters
  fitted_bn <- learn_parameters(training_data, network_config)
  
  # Step 4: Apply to MiLB
  imputation_results <- apply_to_milb(fitted_bn, network_config)
  
  # Step 5: Validation (requires actual data)
  # validation_results <- validate_network(imputation_results)
  
  cat("\n")
  cat("╔═══════════════════════════════════════════════════════════════╗\n")
  cat("║  Pipeline Complete!                                          ║\n")
  cat("║  Biomechanics imputed for MiLB data                          ║\n")
  cat("║  Results saved to:", CONFIG$output_dir, "\n")
  cat("╚═══════════════════════════════════════════════════════════════╝\n")
  
  return(list(
    network_config = network_config,
    training_data = training_data,
    fitted_bn = fitted_bn,
    imputation_results = imputation_results
  ))
}

# ==============================================================================
# QUICK START
# ==============================================================================

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║  Bayesian Network Orchestration Script                        ║\n")
cat("║  Source: bn_orchestrate.R                                      ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

cat("\nUSAGE:\n")
cat("  1. Run full pipeline:\n")
cat("     > result <- run_full_pipeline()\n")
cat("\n  2. Run individual sections:\n")
cat("     > network_cfg <- setup_network()\n")
cat("     > training <- prepare_training(network_cfg)\n")
cat("     > fitted <- learn_parameters(training, network_cfg)\n")
cat("     > imputed <- apply_to_milb(fitted, network_cfg)\n")
cat("     > validation <- validate_network(imputed)\n")
cat("\n  3. Configuration options in CONFIG list above\n")
cat("\nOutput files saved to:", CONFIG$output_dir, "\n")
