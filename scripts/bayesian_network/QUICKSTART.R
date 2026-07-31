# ==============================================================================
# Quick Start Example: Minimal Working Code
# ==============================================================================
# Copy and paste to get started immediately
# This is the absolute minimum to run the Bayesian network

# Install required package if needed:
# install.packages("bnlearn")

library(tidyverse)
library(data.table)
library(bnlearn)

# ==============================================================================
# OPTION 1: Run Everything (Recommended First Time)
# ==============================================================================

cat("\n=== Option 1: Full Pipeline (Recommended) ===\n\n")

# Step 1: Source the orchestration script
# This loads all modules and provides run_full_pipeline()
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_orchestrate.R")

# Step 2: Run the complete pipeline
# This takes 5-15 minutes depending on your data size
results <- run_full_pipeline()

# That's it! Results are saved and ready to use.
# Check results$imputation_results to explore predictions

# ==============================================================================
# OPTION 2: Run Step by Step (For Debugging/Understanding)
# ==============================================================================

cat("\n=== Option 2: Step-by-Step (For Learning) ===\n\n")

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_validation_framework.R")

# Step 1: Define network
cat("\nStep 1: Creating network...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()
cat("✓ Network created with", length(nodes(bn)), "nodes\n")

# Step 2: Prepare training data
cat("\nStep 2: Preparing MLB training data...\n")
training_data <- prepare_training_data(
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = discretization_scheme
)
cat("✓ Training data ready:", nrow(training_data), "pitches\n")

# Step 3: Learn network parameters
cat("\nStep 3: Learning network parameters from MLB...\n")
fitted_bn <- learn_network_parameters(
  training_data = training_data,
  bn_structure = bn,
  method = "bayes",
  smoothing = 1
)
cat("✓ Network parameters learned\n")

# Step 4: Apply to MiLB data
cat("\nStep 4: Inferring biomechanics for MiLB pitches...\n")
milb_data <- prepare_milb_for_inference(
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = discretization_scheme
)

imputation_results <- apply_network_to_milb(
  fitted_bn,
  milb_data,
  output_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"
)
cat("✓ Imputation complete\n")

# ==============================================================================
# OPTION 3: Load Pre-Trained Network (If Already Ran Before)
# ==============================================================================

cat("\n=== Option 3: Use Saved Network (If Already Trained) ===\n\n")

# If you've already run the pipeline and want to skip learning:

# Load the network
fitted_bn <- load_network(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/fitted_network.rds"
)

# Load discretization scheme
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
discretization_scheme <- create_discretization_scheme()

# Prepare new MiLB data
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")

milb_data <- prepare_milb_for_inference(
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = discretization_scheme
)

imputation_results <- apply_network_to_milb(fitted_bn, milb_data)

# ==============================================================================
# EXPLORING RESULTS
# ==============================================================================

cat("\n=== Exploring Results ===\n\n")

# Load the predictions
predictions_wide <- fread(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/biomech_predictions_wide.csv"
)
confidence <- fread(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/inference_confidence.csv"
)

# See predictions for first few pitches
cat("\nFirst 5 pitches - top predictions:\n")
print(head(predictions_wide, 5))

# Check confidence in predictions
cat("\nConfidence distribution:\n")
cat("Mean confidence:", sprintf("%.1f%%", mean(confidence$confidence) * 100), "\n")
cat("Pitches with low confidence (<40%):", sum(confidence$confidence < 0.4), "\n")

# See which biomechanics we couldn't predict well
low_conf_by_var <- confidence %>%
  filter(confidence < 0.4) %>%
  group_by(variable) %>%
  summarise(n_low_conf = n(), .groups = "drop") %>%
  arrange(desc(n_low_conf))

cat("\nVariables with lowest average confidence:\n")
print(low_conf_by_var)

# ==============================================================================
# EXAMPLE: Test on Single Pitch
# ==============================================================================

cat("\n=== Example: Single Pitch Inference ===\n\n")

# Manually query the network for one pitch
example_evidence <- list(
  stand = "L",
  zone = "1",
  pitch_name = "Four-Seam Fastball",
  launch_angle = "fly",
  launch_speed = "hard",
  spray_angle = "pull"
)

result <- explore_network_inference(fitted_bn, example_evidence)

cat("\nFor a left-handed batter facing a fastball in zone 1,\n")
cat("with a fly ball outcome (hard contact, pulled):\n\n")
cat("Attack Angle predictions:\n")
print(result$attack_angle$all_probabilities)

# ==============================================================================
# CONFIGURATION CUSTOMIZATION
# ==============================================================================

cat("\n=== Customizing Behavior ===\n\n")

cat("To change learning settings, edit bn_orchestrate.R:\n\n")
cat("  CONFIG$learning_method <- 'mle'      # Switch to Maximum Likelihood\n")
cat("  CONFIG$smoothing_parameter <- 5      # Less smoothing (higher = smoother)\n")
cat("  CONFIG$inference_method <- 'ls'      # Use likelihood sampling (faster)\n")
cat("  CONFIG$confidence_threshold <- 0.5   # Higher threshold for flagging\n")

# ==============================================================================
# WHEN ACTUAL DATA ARRIVES
# ==============================================================================

cat("\n=== Validation (When Real Biomechanics Data Available) ===\n\n")

cat("Once MiLB biomechanics measurements become available:\n\n")
cat("# Load actual data\n")
cat("actual_biomech <- fread('your_biomechanics_data.csv')\n\n")
cat("# Validate\n")
cat("validation <- validate_network(imputation_results, actual_biomech)\n\n")
cat("# See recommendations for improvement\n")
cat("refine_network(fitted_bn, validation$validation, 'Fixed swing_tilt edge')\n")

# ==============================================================================
# FILES CREATED
# ==============================================================================

cat("\n=== Output Files ===\n\n")

output_files <- list.files(
  "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/",
  full.names = FALSE
)

if (length(output_files) > 0) {
  cat("Files created in /data/processed/bayesian_imputation/:\n")
  for (f in output_files) {
    cat(sprintf("  • %s\n", f))
  }
} else {
  cat("No output files yet. Run the pipeline to generate them.\n")
}

# ==============================================================================
# TROUBLESHOOTING
# ==============================================================================

cat("\n=== Troubleshooting ===\n\n")

cat("Issue: 'Object not found' errors\n")
cat("  → Make sure to source() the required scripts first\n\n")

cat("Issue: Data files not found\n")
cat("  → Check raw_data_dir path matches your actual data location\n")
cat("  → Verify file naming (MLB vs MiLB patterns)\n\n")

cat("Issue: Low confidence predictions\n")
cat("  → May need network refinement\n")
cat("  → See bn_validation_framework.R for guidance\n\n")

cat("Issue: Slow inference\n")
cat("  → Switch to likelihood sampling: CONFIG$inference_method <- 'ls'\n")
cat("  → Or check if your network has unnecessary edges\n")

# ==============================================================================
# END
# ==============================================================================

cat("\n✓ Quick start complete!\n")
cat("See README.md for full documentation\n")
cat("See SCRIPTS_SUMMARY.md for overview of all modules\n")
