# ==============================================================================
# Bayesian Network Inference Engine
# ==============================================================================
# Purpose: Query the learned network to perform backward inference
# Given observed pitch outcomes + context, predict posterior distributions
# over hidden biomechanics variables (attack_angle, swing_tilt, etc.)

library(bnlearn)
library(tidyverse)
library(data.table)

# ==============================================================================
# CORE INFERENCE FUNCTION: Query Single Pitch
# ==============================================================================

infer_biomechanics_single_pitch <- function(
  fitted_bn,
  evidence = list(),
  query_nodes = c(
    "attack_angle", "swing_path_tilt",
    "attack_direction", "bat_speed", "intercept_x", "intercept_y"
  ),
  method = "exact"  # "exact" or "ls" (likelihood sampling for large networks)
) {
  # Perform Bayesian inference on a single pitch
  #
  # Args:
  #   fitted_bn: Learned network (bn.fit object)
  #   evidence: Named list of observed variables
  #             Example: list(stand="L", zone="3", pitch_name="Four-Seam Fastball",
  #                           launch_angle="fly", launch_speed="hard", spray_angle="pull")
  #   query_nodes: Which hidden variables to infer posteriors for
  #   method: "exact" for analytical solution, "ls" for sampling-based
  #
  # Returns:
  #   List with posterior probabilities for each query node
  
  if (length(evidence) == 0) {
    stop("Must provide at least one piece of evidence to condition on")
  }
  
  results <- list()
  
  for (node in query_nodes) {
    if (!(node %in% names(fitted_bn))) {
      warning("Query node not in network:", node)
      next
    }
    
    tryCatch({
      if (method == "exact") {
        # Use likelihood weighting as approximate exact inference
        # (bnlearn doesn't have a true "exact" inference method for cpdist)
        prob_dist <- cpdist(
          fitted_bn,
          nodes = node,
          evidence = evidence,
          method = "lw",
          n = 10000
        )
      } else if (method == "ls") {
        # Use logic sampling (forward sampling)
        prob_dist <- cpdist(
          fitted_bn,
          nodes = node,
          evidence = evidence,
          method = "ls",
          n = 10000
        )
      }
      
      # Check if cpdist returned empty result (evidence doesn't match CPT)
      if (is.null(prob_dist) || nrow(prob_dist) == 0) {
        # Return empty result - will be skipped in formatting
        return(NULL)
      }
      
      # Convert frequency table to probabilities
      if (is.null(nrow(prob_dist))) {
        # Single column result
        prob_table <- table(prob_dist) / length(prob_dist)
      } else {
        # Multiple columns (shouldn't happen for single node query)
        prob_table <- table(prob_dist[[node]]) / nrow(prob_dist)
      }
      
      results[[node]] <- list(
        posterior = as.numeric(prob_table),
        levels = names(prob_table),
        top_level = names(prob_table)[which.max(prob_table)],
        top_probability = max(prob_table),
        all_probabilities = as.data.frame(prob_table) %>%
          setNames(c("level", "probability")) %>%
          mutate(probability = as.numeric(probability))
      )
      
    }, error = function(e) {
      warning("Inference failed for node", node, ":", e$message)
    })
  }
  
  return(results)
}

# ==============================================================================
# BATCH INFERENCE: Query Multiple Pitches
# ==============================================================================

infer_biomechanics_batch <- function(
  fitted_bn,
  milb_data,
  query_nodes = c(
    "attack_angle", "swing_path_tilt",
    "attack_direction", "bat_speed", "intercept_x", "intercept_y"
  ),
  method = "exact",
  verbose = TRUE
) {
  # Perform inference on multiple pitches from MiLB dataset
  #
  # Args:
  #   fitted_bn: Learned network
  #   milb_data: Data frame with pitch-level data (stand, zone, pitch_name, 
  #              launch_angle, launch_speed, spray_angle, etc.)
  #   query_nodes: Biomechanics to infer
  #   method: "exact" or "ls"
  #   verbose: Print progress
  #
  # Returns:
  #   List of inference results for each pitch
  
  n_pitches <- nrow(milb_data)
  results_list <- list()
  
  # Verify input data types
  if (verbose) {
    cat("\n=== Data Type Verification ===\n")
    cat("Evidence columns:\n")
    for (col in c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")) {
      if (col %in% colnames(milb_data)) {
        col_class <- class(milb_data[[col]])
        cat(sprintf("  %s: %s\n", col, col_class))
        if (col_class != "factor") {
          cat(sprintf("    WARNING: Expected factor, got %s\n", col_class))
        }
      }
    }
  }
  
  if (verbose) {
    cat(sprintf("\n=== Inferring Biomechanics for %d Pitches ===\n", n_pitches))
  }
  
  n_success <- 0
  n_no_evidence <- 0
  n_inference_failed <- 0
  
  for (i in seq_len(n_pitches)) {
    if (verbose && i %% 1000 == 0) {
      cat(sprintf("  Progress: %d/%d pitches (Success: %d, No evidence: %d, Failed: %d)\n", 
                  i, n_pitches, n_success, n_no_evidence, n_inference_failed))
    }
    
    # Extract pitch row
    pitch_row <- milb_data[i, ]
    
    # Convert to evidence list (only observed variables)
    evidence <- list()
    
    # Pitch context - keep as factors
    if (!is.na(pitch_row$stand)) {
      evidence$stand <- pitch_row$stand
    }
    if (!is.na(pitch_row$zone)) {
      evidence$zone <- pitch_row$zone
    }
    if (!is.na(pitch_row$pitch_name)) {
      evidence$pitch_name <- pitch_row$pitch_name
    }
    
    # Observable outcomes - keep as factors
    if (!is.na(pitch_row$launch_angle)) {
      evidence$launch_angle <- pitch_row$launch_angle
    }
    if (!is.na(pitch_row$launch_speed)) {
      evidence$launch_speed <- pitch_row$launch_speed
    }
    if (!is.na(pitch_row$spray_angle)) {
      evidence$spray_angle <- pitch_row$spray_angle
    }
    
    # Check if we have evidence
    if (length(evidence) == 0) {
      n_no_evidence <- n_no_evidence + 1
      results_list[[i]] <- list()
      next
    }
    
    # Run inference
    inference_result <- infer_biomechanics_single_pitch(
      fitted_bn,
      evidence = evidence,
      query_nodes = query_nodes,
      method = method
    )
    
    # Track success
    if (!is.null(inference_result) && length(inference_result) > 0) {
      n_success <- n_success + 1
    } else {
      n_inference_failed <- n_inference_failed + 1
    }
    
    # Attach to results
    results_list[[i]] <- inference_result
  }
  
  if (verbose) {
    cat(sprintf("\n=== Inference Complete ===\n"))
    cat(sprintf("Total pitches: %d\n", n_pitches))
    cat(sprintf("  ✓ Successful: %d (%.1f%%)\n", n_success, n_success/n_pitches*100))
    cat(sprintf("  ✗ No evidence: %d (%.1f%%)\n", n_no_evidence, n_no_evidence/n_pitches*100))
    cat(sprintf("  ✗ Inference failed: %d (%.1f%%)\n", n_inference_failed, n_inference_failed/n_pitches*100))
  }
  
  return(results_list)
}

# ==============================================================================
# FORMAT INFERENCE RESULTS FOR EXPORT
# ==============================================================================

format_inference_results_long <- function(inference_results, milb_data = NULL) {
  # Convert list of inference results to long-format data frame
  # One row per pitch-variable combination
  #
  # Returns:
  #   Data frame with columns:
  #     pitch_id, variable, level, probability
  
  formatted_list <- list()
  
  for (pitch_idx in seq_along(inference_results)) {
    pitch_result <- inference_results[[pitch_idx]]
    
    # Skip if no results for this pitch
    if (is.null(pitch_result) || length(pitch_result) == 0) {
      next
    }
    
    for (var in names(pitch_result)) {
      prob_df <- pitch_result[[var]]$all_probabilities %>%
        mutate(
          pitch_id = pitch_idx,
          variable = var,
          .before = "level"
        )
      
      formatted_list[[paste(pitch_idx, var, sep = "_")]] <- prob_df
    }
  }
  
  # Handle empty results
  if (length(formatted_list) == 0) {
    return(data.frame(
      pitch_id = integer(),
      variable = character(),
      level = character(),
      probability = numeric()
    ))
  }
  
  result_df <- bind_rows(formatted_list) %>%
    select(pitch_id, variable, level, probability)
  
  return(result_df)
}

format_inference_results_wide <- function(inference_results, milb_data = NULL) {
  # Convert list of inference results to wide-format data frame
  # One row per pitch, columns for each variable's top prediction + confidence
  #
  # Returns:
  #   Data frame with columns like:
  #     pitch_id, attack_angle_pred, attack_angle_prob, swing_tilt_pred, ...
  
  formatted_list <- list()
  
  # Get list of all variables from first non-empty result
  all_vars <- c()
  for (pitch_result in inference_results) {
    if (!is.null(pitch_result) && length(pitch_result) > 0) {
      all_vars <- names(pitch_result)
      break
    }
  }
  
  for (pitch_idx in seq_along(inference_results)) {
    pitch_result <- inference_results[[pitch_idx]]
    
    row_data <- data.frame(pitch_id = pitch_idx)
    
    # If no results for this pitch, create row with NAs for all variables
    if (is.null(pitch_result) || length(pitch_result) == 0) {
      for (var in all_vars) {
        row_data[[paste0(var, "_predicted")]] <- NA_character_
        row_data[[paste0(var, "_confidence")]] <- NA_real_
      }
      formatted_list[[pitch_idx]] <- row_data
      next
    }
    
    for (var in names(pitch_result)) {
      row_data[[paste0(var, "_predicted")]] <- pitch_result[[var]]$top_level
      row_data[[paste0(var, "_confidence")]] <- pitch_result[[var]]$top_probability
    }
    
    formatted_list[[pitch_idx]] <- row_data
  }
  
  # Handle empty results
  if (length(formatted_list) == 0) {
    return(data.frame(pitch_id = integer()))
  }
  
  result_df <- bind_rows(formatted_list)
  return(result_df)
}

# ==============================================================================
# DIAGNOSTIC QUERIES
# ==============================================================================

explore_network_inference <- function(fitted_bn, example_evidence = list()) {
  # Interactive exploration of network inference
  # Show how posterior distributions change with different evidence
  
  if (length(example_evidence) == 0) {
    # Use reasonable defaults
    example_evidence <- list(
      stand = "L",
      zone = "1",
      pitch_name = "Four-Seam Fastball",
      launch_angle = "fly",
      launch_speed = "hard",
      spray_angle = "pull"
    )
  }
  
  cat("\n=== Network Inference Exploration ===\n")
  cat("Evidence provided:\n")
  print(example_evidence)
  
  results <- infer_biomechanics_single_pitch(
    fitted_bn,
    evidence = example_evidence,
    query_nodes = c("attack_angle", "swing_path_tilt",
                   "attack_direction", "bat_speed", "intercept_x", "intercept_y")
  )
  
  cat("\n=== Posterior Distributions ===\n")
  for (node in names(results)) {
    cat(sprintf("\n%s:\n", node))
    cat(sprintf("  Top prediction: %s (confidence: %.1f%%)\n",
                results[[node]]$top_level,
                results[[node]]$top_probability * 100))
    cat("  Full distribution:\n")
    print(results[[node]]$all_probabilities)
  }
  
  invisible(results)
}

# ==============================================================================
# CONFIDENCE ASSESSMENT
# ==============================================================================

assess_inference_confidence <- function(inference_results, milb_data = NULL, confidence_threshold = 0.4) {
  # Assess confidence in inferences across all pitches
  # Flag low-confidence predictions for manual review or alternative methods
  
  cat("\n=== Inference Confidence Assessment ===\n")
  
  confidence_summary <- data.frame()
  
  for (pitch_idx in seq_along(inference_results)) {
    pitch_result <- inference_results[[pitch_idx]]
    
    # Skip if no results
    if (is.null(pitch_result) || length(pitch_result) == 0) {
      next
    }
    
    for (var in names(pitch_result)) {
      conf <- pitch_result[[var]]$top_probability
      
      confidence_summary <- rbind(confidence_summary, data.frame(
        pitch_id = pitch_idx,
        variable = var,
        top_prediction = pitch_result[[var]]$top_level,
        confidence = conf,
        confidence_flag = ifelse(conf < confidence_threshold, "LOW", "OK")
      ))
    }
  }
  
  # Handle empty results
  if (nrow(confidence_summary) == 0) {
    cat("No inference results to assess confidence for.\n")
    return(data.frame(
      pitch_id = integer(),
      variable = character(),
      top_prediction = character(),
      confidence = numeric(),
      confidence_flag = character()
    ))
  }
  
  # Summary statistics
  cat("\nConfidence Distribution:\n")
  cat("  Mean confidence:", sprintf("%.2f%%", mean(confidence_summary$confidence) * 100), "\n")
  cat("  Median confidence:", sprintf("%.2f%%", median(confidence_summary$confidence) * 100), "\n")
  cat("  Min confidence:", sprintf("%.2f%%", min(confidence_summary$confidence) * 100), "\n")
  
  low_conf_count <- sum(confidence_summary$confidence_flag == "LOW")
  cat("\nLow confidence predictions (<", confidence_threshold * 100, "%):", low_conf_count, "\n")
  
  if (low_conf_count > 0) {
    cat("\nExamples of low-confidence inferences:\n")
    print(head(confidence_summary %>% filter(confidence_flag == "LOW")))
  }
  
  return(confidence_summary)
}

# ==============================================================================
# EXPORT
# ==============================================================================

if (!exists("inference_engine_config")) {
  inference_engine_config <- list(
    infer_biomechanics_single_pitch = infer_biomechanics_single_pitch,
    infer_biomechanics_batch = infer_biomechanics_batch,
    format_inference_results_long = format_inference_results_long,
    format_inference_results_wide = format_inference_results_wide,
    explore_network_inference = explore_network_inference,
    assess_inference_confidence = assess_inference_confidence
  )
}
