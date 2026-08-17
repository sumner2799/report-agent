#!/usr/bin/env Rscript
# ==============================================================================
# EVALUATION GUIDE: Ad-Hoc Prediction Assessment
# ==============================================================================
# Evaluate predictions on-the-fly without creating massive CSV files
# Run these checks right after inference in your analysis script

library(tidyverse)
library(data.table)
library(bnlearn)

# ==============================================================================
# PART 1: CONFIDENCE ASSESSMENT (Always Do This)
# ==============================================================================

evaluate_prediction_confidence <- function(inference_results, milb_data) {
  cat("\n=== CONFIDENCE ASSESSMENT ===\n\n")
  
  # Calculate confidence metrics
  confidence_list <- list()
  
  for (pitch_idx in seq_along(inference_results)) {
    pitch_result <- inference_results[[pitch_idx]]
    
    if (is.null(pitch_result) || length(pitch_result) == 0) next
    
    for (var in names(pitch_result)) {
      top_prob <- pitch_result[[var]]$top_probability
      
      confidence_list[[paste(pitch_idx, var, sep = "_")]] <- data.frame(
        pitch_id = pitch_idx,
        variable = var,
        top_prediction = pitch_result[[var]]$top_level,
        confidence = top_prob
      )
    }
  }
  
  confidence_df <- rbindlist(confidence_list)
  
  # Summary statistics
  cat("Confidence Distribution:\n")
  print(confidence_df %>%
    group_by(variable) %>%
    summarise(
      mean = mean(confidence),
      median = median(confidence),
      min = min(confidence),
      max = max(confidence),
      low_conf_pct = sum(confidence < 0.40) / n() * 100
    ) %>%
    mutate(across(is.numeric, ~round(., 4)))
  )
  
  cat("\nLow Confidence (<40%) Predictions:\n")
  low_conf <- confidence_df %>% filter(confidence < 0.40)
  cat(sprintf("  Total: %d out of %d (%.1f%%)\n", 
              nrow(low_conf), 
              nrow(confidence_df),
              nrow(low_conf) / nrow(confidence_df) * 100))
  
  if (nrow(low_conf) > 0) {
    cat("\n  Top 10 lowest confidence:\n")
    print(low_conf %>% slice_head(n = 10))
  }
  
  return(confidence_df)
}

# ==============================================================================
# PART 2: PROBABILITY DISTRIBUTION ANALYSIS
# ==============================================================================

analyze_probability_distributions <- function(inference_results) {
  cat("\n=== PROBABILITY DISTRIBUTION ANALYSIS ===\n\n")
  
  # For each variable, look at entropy (how "sure" the predictions are)
  # Low entropy = confident (peaked), High entropy = uncertain (flat)
  
  entropy_list <- list()
  
  for (pitch_idx in seq_along(inference_results)) {
    pitch_result <- inference_results[[pitch_idx]]
    
    if (is.null(pitch_result) || length(pitch_result) == 0) next
    
    for (var in names(pitch_result)) {
      probs <- pitch_result[[var]]$posterior
      
      # Calculate entropy: -sum(p * log(p))
      entropy <- -sum(probs[probs > 0] * log(probs[probs > 0]))
      
      entropy_list[[paste(pitch_idx, var, sep = "_")]] <- data.frame(
        pitch_id = pitch_idx,
        variable = var,
        entropy = entropy,
        max_prob = max(probs)
      )
    }
  }
  
  entropy_df <- rbindlist(entropy_list)
  
  cat("Entropy by Variable (Higher = More Uncertain):\n")
  print(entropy_df %>%
    group_by(variable) %>%
    summarise(
      mean_entropy = mean(entropy),
      median_entropy = median(entropy),
      mean_top_prob = mean(max_prob),
      n = n()
    ) %>%
    mutate(across(is.numeric, ~round(., 4)))
  )
  
  return(entropy_df)
}

# ==============================================================================
# PART 3: EVIDENCE QUALITY CHECK
# ==============================================================================

assess_evidence_quality <- function(milb_data) {
  cat("\n=== EVIDENCE QUALITY ASSESSMENT ===\n\n")
  
  evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")
  
  quality_summary <- data.frame()
  
  for (col in evidence_cols) {
    if (col %in% colnames(milb_data)) {
      n_total <- nrow(milb_data)
      n_na <- sum(is.na(milb_data[[col]]))
      pct_na <- (n_na / n_total) * 100
      
      quality_summary <- rbind(quality_summary, data.frame(
        variable = col,
        n_observed = n_total - n_na,
        n_missing = n_na,
        pct_observed = 100 - pct_na
      ))
    }
  }
  
  cat("Evidence Availability:\n")
  print(quality_summary)
  
  cat("\nNote:\n")
  cat("  - launch_speed/launch_angle often NA (pitches without hit data)\n")
  cat("  - spray_angle always available (computed from ball trajectory)\n")
  cat("  - stand/zone/pitch_name should always be observed\n")
  
  return(quality_summary)
}

# ==============================================================================
# PART 4: PREDICTION CONSISTENCY CHECK
# ==============================================================================

check_prediction_consistency <- function(inference_results, milb_data) {
  cat("\n=== PREDICTION CONSISTENCY CHECK ===\n\n")
  
  # Group pitches by similar evidence and check if predictions are similar
  # High consistency = network is stable
  # Low consistency = network might have issues
  
  consistency_checks <- list()
  
  cat("Checking prediction consistency by pitch type:\n")
  
  if ("pitch_name" %in% colnames(milb_data)) {
    pitch_types <- unique(milb_data$pitch_name)
    
    for (pitch_type in pitch_types) {
      pitch_indices <- which(milb_data$pitch_name == pitch_type)
      
      if (length(pitch_indices) < 2) next  # Need at least 2 to compare
      
      # Get predictions for this pitch type
      attack_angles <- sapply(pitch_indices, function(idx) {
        if (!is.null(inference_results[[idx]]) && 
            "attack_angle" %in% names(inference_results[[idx]])) {
          inference_results[[idx]]$attack_angle$top_level
        } else {
          NA_character_
        }
      })
      
      unique_predictions <- length(unique(na.omit(attack_angles)))
      
      consistency_checks[[pitch_type]] <- data.frame(
        pitch_type = pitch_type,
        n_pitches = length(pitch_indices),
        n_unique_attack_angles = unique_predictions,
        consistency = 1 - (unique_predictions / length(pitch_indices))
      )
    }
    
    consistency_df <- rbindlist(consistency_checks)
    print(consistency_df %>%
      arrange(desc(n_pitches)) %>%
      head(10)
    )
  }
  
  cat("\nInterpretation:\n")
  cat("  - High consistency (>0.7) = Similar pitches get similar predictions ✓\n")
  cat("  - Low consistency (<0.3) = Predictions vary widely ⚠\n")
  
  return(consistency_df)
}

# ==============================================================================
# PART 5: SANITY CHECKS (If Actual Data Available)
# ==============================================================================

validate_against_actual <- function(predictions, actual_biomechanics, threshold = 0.4) {
  cat("\n=== VALIDATION AGAINST ACTUAL DATA ===\n\n")
  
  cat("Comparing predicted vs actual biomechanics...\n")
  
  validation_results <- data.frame()
  
  for (var in names(actual_biomechanics)) {
    pred_col <- paste0(var, "_predicted")
    
    if (pred_col %in% colnames(predictions) && var %in% colnames(actual_biomechanics)) {
      # Count matches
      matches <- predictions[[pred_col]] == actual_biomechanics[[var]]
      match_rate <- sum(matches, na.rm = TRUE) / sum(!is.na(matches)) * 100
      
      validation_results <- rbind(validation_results, data.frame(
        variable = var,
        match_rate = match_rate,
        n_predictions = sum(!is.na(matches))
      ))
    }
  }
  
  cat("\nAccuracy by Variable:\n")
  print(validation_results %>%
    arrange(desc(match_rate)) %>%
    mutate(match_rate = round(match_rate, 1))
  )
  
  overall_accuracy <- mean(validation_results$match_rate)
  cat("\nOverall Accuracy:", round(overall_accuracy, 1), "%\n")
  
  return(validation_results)
}

# ==============================================================================
# PART 6: COMPLETE EVALUATION PIPELINE (USE THIS!)
# ==============================================================================

evaluate_predictions <- function(inference_results, milb_data, actual_biomechanics = NULL) {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║        COMPREHENSIVE PREDICTION EVALUATION                    ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  
  # 1. Evidence quality
  evidence_quality <- assess_evidence_quality(milb_data)
  
  # 2. Confidence assessment
  confidence_df <- evaluate_prediction_confidence(inference_results, milb_data)
  
  # 3. Probability distributions
  entropy_df <- analyze_probability_distributions(inference_results)
  
  # 4. Consistency checks
  tryCatch({
    consistency_df <- check_prediction_consistency(inference_results, milb_data)
  }, error = function(e) {
    cat("\nConsistency check skipped (error):", as.character(e), "\n")
  })
  
  # 5. Validation (if actual data provided)
  if (!is.null(actual_biomechanics)) {
    predictions_wide <- format_inference_results_wide(inference_results, milb_data)
    validate_against_actual(predictions_wide, actual_biomechanics)
  } else {
    cat("\n--- VALIDATION AGAINST ACTUAL DATA ---\n")
    cat("Skipped: No actual biomechanics data provided\n")
    cat("When MiLB measurements become available, pass actual_biomechanics parameter\n")
  }
  
  cat("\n✓ Evaluation complete\n\n")
  
  return(list(
    evidence_quality = evidence_quality,
    confidence = confidence_df,
    entropy = entropy_df
  ))
}

# ==============================================================================
# USAGE EXAMPLE
# ==============================================================================

# After running inference:
#
# results <- infer_biomechanics_batch(fitted_bn, milb_data)
# evaluation <- evaluate_predictions(results, milb_data)
#
# Or with actual data (when available):
#
# evaluation <- evaluate_predictions(results, milb_data, actual_biomechanics_df)

cat("\n✓ Evaluation functions loaded\n")
cat("  Call: evaluate_predictions(inference_results, milb_data)\n")
cat("  Or with actual data: evaluate_predictions(results, milb_data, actual_biomechanics)\n\n")
