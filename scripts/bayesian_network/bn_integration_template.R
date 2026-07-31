# ==============================================================================
# Integration Template: Connect Bayesian Network to Existing Pipeline
# ==============================================================================
# This script shows how to integrate imputed biomechanics into your
# existing process_statcast.R workflow
#
# Use this as a reference for incorporating imputed values into
# metric calculations, percentile rankings, and report generation

library(tidyverse)
library(data.table)

# ==============================================================================
# STEP 1: Load Imputed Biomechanics
# ==============================================================================

load_imputed_biomechanics <- function(
  imputation_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"
) {
  # Load the audit trail which has original MiLB data + predictions
  
  cat("Loading imputed biomechanics...\n")
  
  audit_trail <- fread(file.path(imputation_dir, "audit_trail.csv"))
  predictions_wide <- fread(file.path(imputation_dir, "biomech_predictions_wide.csv"))
  confidence <- fread(file.path(imputation_dir, "inference_confidence.csv"))
  
  # Combine predictions with confidence
  imputed_data <- predictions_wide %>%
    left_join(
      confidence %>%
        select(pitch_id, variable, confidence_flag) %>%
        pivot_wider(
          names_from = variable,
          values_from = confidence_flag,
          names_glue = "{variable}_confidence_flag"
        ),
      by = "pitch_id"
    )
  
  return(imputed_data)
}

# ==============================================================================
# STEP 2: Merge with Original MiLB Data
# ==============================================================================

merge_imputed_with_original <- function(
  milb_statcast,
  imputed_biomechanics,
  include_confidence_flags = TRUE
) {
  # Add imputed biomechanics columns to original MiLB pitch data
  # Flag low-confidence predictions for review/exclusion
  
  milb_with_imputed <- milb_statcast %>%
    mutate(pitch_id = row_number()) %>%
    left_join(imputed_biomechanics, by = "pitch_id")
  
  # Identify pitches with imputed values (for tracking)
  milb_with_imputed <- milb_with_imputed %>%
    mutate(
      attack_angle_source = ifelse(is.na(attack_angle), "imputed", "measured"),
      swing_path_tilt_source = ifelse(is.na(swing_path_tilt), "imputed", "measured"),
      # ... etc for other variables
      
      # Flag low-confidence imputations
      attack_angle_high_confidence = ifelse(
        attack_angle_source == "imputed" & attack_angle_confidence_flag == "LOW",
        FALSE, TRUE
      )
    )
  
  return(milb_with_imputed)
}

# ==============================================================================
# STEP 3: Use Imputed Values in Metrics
# ==============================================================================

# When calculating metrics, you can now use:
# - Measured biomechanics where available
# - Imputed values (with appropriate uncertainty handling) where missing

example_metric_calculation <- function(milb_with_imputed) {
  # Example: Calculate average attack angle for a player
  
  metrics <- milb_with_imputed %>%
    group_by(player_id, player_name) %>%
    summarise(
      # Only use high-confidence measurements or imputations
      avg_attack_angle = mean(attack_angle[attack_angle_high_confidence], na.rm = TRUE),
      n_attack_angle = sum(attack_angle_high_confidence, na.rm = TRUE),
      
      # Alternative: separate measured vs imputed
      avg_attack_angle_measured = mean(
        attack_angle[attack_angle_source == "measured"],
        na.rm = TRUE
      ),
      avg_attack_angle_imputed = mean(
        attack_angle[attack_angle_source == "imputed" & attack_angle_high_confidence],
        na.rm = TRUE
      ),
      n_attack_angle_measured = sum(attack_angle_source == "measured", na.rm = TRUE),
      n_attack_angle_imputed = sum(
        attack_angle_source == "imputed" & attack_angle_high_confidence,
        na.rm = TRUE
      ),
      
      .groups = "drop"
    )
  
  return(metrics)
}

# ==============================================================================
# STEP 4: Create Uncertainty Estimates
# ==============================================================================

compute_imputation_uncertainty <- function(imputed_biomechanics) {
  # For each variable, compute uncertainty from full posterior distribution
  # Useful for weighting in downstream analyses
  
  uncertainty <- imputed_biomechanics %>%
    group_by(pitch_id, variable) %>%
    summarise(
      # Entropy of distribution (higher = more uncertain)
      posterior_entropy = -sum(probability * log(probability), na.rm = TRUE),
      
      # Confidence in top prediction
      top_prediction_probability = max(probability),
      
      # "Margin" between top 2 predictions
      second_best_probability = sort(probability, decreasing = TRUE)[2],
      margin = max(probability) - second_best_probability,
      
      .groups = "drop"
    )
  
  return(uncertainty)
}

# ==============================================================================
# STEP 5: Handling Uncertainty in Analysis
# ==============================================================================

# Three approaches for using imputed values:

# Approach 1: Point estimates only (simplest)
# Use top prediction from imputed biomechanics
# → Accept inherent uncertainty from imputation

approach_1_point_estimate <- function(imputed_wide) {
  # imputed_wide already has _predicted and _confidence columns
  # Just use the _predicted values in calculations
  return(imputed_wide)
}

# Approach 2: Confidence-weighted averaging (recommended for most uses)
# Weight contribution of each observation by confidence in imputation
compute_confidence_weighted_avg <- function(data, group_var, metric_var) {
  result <- data %>%
    group_by(!!sym(group_var)) %>%
    summarise(
      # Numeric metrics weighted by confidence
      weighted_avg = weighted.mean(
        !!sym(metric_var),
        w = confidence_score,
        na.rm = TRUE
      ),
      # Also track unweighted average for comparison
      unweighted_avg = mean(!!sym(metric_var), na.rm = TRUE),
      .groups = "drop"
    )
  
  return(result)
}

# Approach 3: Probabilistic inference (most principled)
# Integrate over full posterior distribution
# → Use for high-stakes decisions, not everyday analysis
compute_posterior_distribution <- function(pitch_data, query_metric) {
  # For each pitch, maintain full distribution over possible metric values
  # Aggregate across pitches to get posterior distribution of player metric
  
  # This is overkill for most uses but available if needed
  # (Would require computing player-level metrics from pitch-level posteriors)
  
  return(NULL)  # Placeholder
}

# ==============================================================================
# STEP 6: Quality Control & Tracking
# ==============================================================================

create_imputation_qc_report <- function(milb_with_imputed) {
  # Summary of imputation coverage and quality
  
  report <- list(
    total_pitches = nrow(milb_with_imputed),
    
    coverage_by_variable = milb_with_imputed %>%
      summarise(
        attack_angle_coverage = mean(!is.na(attack_angle)),
        swing_path_tilt_coverage = mean(!is.na(swing_path_tilt)),
        # contact_depth_coverage = mean(!is.na(contact_depth)),
        attack_direction_coverage = mean(!is.na(attack_direction)),
        bat_speed_coverage = mean(!is.na(bat_speed)),
        intercept_x_coverage = mean(!is.na(intercept_x)),
        intercept_y_coverage = mean(!is.na(intercept_y))
      ) %>%
      mutate(across(everything(), ~. * 100)) %>%
      rename_with(~gsub("_coverage", " (% available)", .), everything()),
    
    imputation_quality = milb_with_imputed %>%
      summarise(
        attack_angle_high_conf = mean(
          attack_angle_source == "imputed" & attack_angle_high_confidence,
          na.rm = TRUE
        ) * 100,
        attack_angle_low_conf = mean(
          attack_angle_source == "imputed" & !attack_angle_high_confidence,
          na.rm = TRUE
        ) * 100
      ),
    
    sample_sizes = list(
      measured = sum(milb_with_imputed$attack_angle_source == "measured", na.rm = TRUE),
      imputed_high_conf = sum(
        milb_with_imputed$attack_angle_source == "imputed" &
          milb_with_imputed$attack_angle_high_confidence,
        na.rm = TRUE
      ),
      imputed_low_conf = sum(
        milb_with_imputed$attack_angle_source == "imputed" &
          !milb_with_imputed$attack_angle_high_confidence,
        na.rm = TRUE
      )
    )
  )
  
  return(report)
}

# ==============================================================================
# STEP 7: Integration with Existing Pipeline
# ==============================================================================

# In your existing process_statcast.R workflow, add something like:

# modified_workflow <- function() {
#   # ... existing code to load and process MLB data ...
#   
#   # Load MiLB data
#   milb_data <- load_milb_statcast()
#   
#   # ADD THIS NEW STEP:
#   imputed_biomech <- load_imputed_biomechanics()
#   milb_data <- merge_imputed_with_original(milb_data, imputed_biomech)
#   
#   # ... continue with existing metric calculations ...
#   # Now metrics will include imputed biomechanics where available
#   
#   # ... existing report generation ...
# }

# ==============================================================================
# STEP 8: Future Validation Integration
# ==============================================================================

integrate_validation_results <- function(
  network_version,
  validation_results,
  milb_with_imputed
) {
  # When validation against actual biomechanics is complete,
  # use results to automatically adjust handling:
  
  # Example: If validation shows attack_angle predictions are poor,
  # reduce weight or exclude low-confidence predictions
  
  if (!is.null(validation_results)) {
    accuracy_by_var <- validation_results %>%
      arrange(overall_accuracy)
    
    cat("\nAccuracy by variable:\n")
    print(accuracy_by_var)
    
    # Dynamically adjust confidence thresholds
    poor_performers <- accuracy_by_var %>%
      filter(overall_accuracy < 0.65) %>%
      pull(variable)
    
    if (length(poor_performers) > 0) {
      cat("\nLow-accuracy variables (may want to exclude or reduce weight):\n")
      cat(paste(poor_performers, collapse = ", "), "\n")
    }
  }
  
  return(NULL)
}

# ==============================================================================
# EXAMPLE USAGE
# ==============================================================================

# Run integrated workflow:
#
# 1. Start with your existing MiLB Statcast load:
#    milb_data <- fread("data/raw/milb_statcast.csv")
#
# 2. Load imputed biomechanics:
#    imputed <- load_imputed_biomechanics()
#
# 3. Merge them:
#    milb_enhanced <- merge_imputed_with_original(milb_data, imputed)
#
# 4. Use in calculations (confidence-weighted approach recommended):
#    player_metrics <- compute_confidence_weighted_avg(
#      milb_enhanced,
#      group_var = "player_name",
#      metric_var = "attack_angle"
#    )
#
# 5. Track quality:
#    qc <- create_imputation_qc_report(milb_enhanced)

cat("\n✓ Integration template loaded\n")
cat("Use these functions to connect Bayesian imputed biomechanics to your pipeline\n")
