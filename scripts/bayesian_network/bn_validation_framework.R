# ==============================================================================
# Bayesian Network Validation & Iteration Framework
# ==============================================================================
# Purpose: Validate network predictions against actual data when available,
# identify systematic errors, and guide network refinement through iterations

library(tidyverse)
library(data.table)

# ==============================================================================
# VALIDATION: Compare Predictions to Actual Data
# ==============================================================================

validate_predictions <- function(
  predictions_wide,
  actual_data,
  variables_to_validate = c(
    "attack_angle", "swing_path_tilt",
    "attack_direction", "bat_speed", "intercept_x", "intercept_y"
  ),
  output_path = NULL
) {
  # When actual biomechanics data becomes available, compare to predictions
  # Compute accuracy metrics and identify failure patterns
  #
  # Args:
  #   predictions_wide: Predictions from apply_network_to_milb()
  #   actual_data: New MiLB data with actual biomechanics measurements
  #   variables_to_validate: Which variables to check
  #
  # Returns:
  #   Validation report with accuracy by variable, error patterns, etc.
  
  if (is.null(output_path)) {
    output_path <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/validation_report.csv"
  }
  
  cat("\n=== Validation Report ===\n")
  
  validation_results <- data.frame()
  
  for (var in variables_to_validate) {
    pred_col <- paste0(var, "_predicted")
    actual_col <- var
    conf_col <- paste0(var, "_confidence")
    
    if (!(pred_col %in% names(predictions_wide))) {
      cat("Warning: Prediction column not found:", pred_col, "\n")
      next
    }
    
    if (!(actual_col %in% names(actual_data))) {
      cat("Warning: Actual data column not found:", actual_col, "\n")
      next
    }
    
    # Merge predictions and actuals
    comparison <- predictions_wide %>%
      select(pitch_id = pitch_id, prediction = all_of(pred_col), confidence = all_of(conf_col)) %>%
      left_join(
        actual_data %>% select(pitch_id = pitch_id, actual = all_of(actual_col)),
        by = "pitch_id"
      ) %>%
      filter(!is.na(actual))
    
    if (nrow(comparison) == 0) {
      cat("No matching data for validation of:", var, "\n")
      next
    }
    
    # Compute accuracy
    n_total <- nrow(comparison)
    n_correct <- sum(comparison$prediction == comparison$actual, na.rm = TRUE)
    accuracy <- n_correct / n_total
    
    # Break down by confidence quartile
    comparison <- comparison %>%
      mutate(conf_quartile = ntile(confidence, 4))
    
    accuracy_by_conf <- comparison %>%
      group_by(conf_quartile) %>%
      summarise(
        accuracy = sum(prediction == actual, na.rm = TRUE) / n(),
        n_samples = n(),
        .groups = "drop"
      )
    
    # Identify most common errors
    errors <- comparison %>%
      filter(prediction != actual) %>%
      group_by(prediction, actual) %>%
      summarise(count = n(), .groups = "drop") %>%
      arrange(desc(count)) %>%
      head(5)
    
    validation_results <- rbind(validation_results, data.frame(
      variable = var,
      n_total = n_total,
      n_correct = n_correct,
      overall_accuracy = accuracy,
      top_error_from = ifelse(nrow(errors) > 0, errors$prediction[1], NA),
      top_error_to = ifelse(nrow(errors) > 0, errors$actual[1], NA),
      top_error_freq = ifelse(nrow(errors) > 0, errors$count[1], 0)
    ))
    
    cat(sprintf("\n%s:\n", var))
    cat(sprintf("  Overall accuracy: %.1f%% (%d/%d)\n", accuracy * 100, n_correct, n_total))
    cat("  Accuracy by confidence quartile:\n")
    print(accuracy_by_conf)
    if (nrow(errors) > 0) {
      cat("  Most common errors:\n")
      print(errors)
    }
  }
  
  fwrite(validation_results, output_path)
  cat("\n✓ Validation report saved to:", output_path, "\n")
  
  return(validation_results)
}

# ==============================================================================
# ERROR PATTERN ANALYSIS
# ==============================================================================

analyze_error_patterns <- function(
  predictions_wide,
  actual_data,
  milb_pitch_data,
  variable = "attack_angle"
) {
  # Deeper analysis: identify systematic prediction errors
  # Are errors related to pitch type? Batter handedness? Outcome?
  #
  # Args:
  #   predictions_wide: Network predictions
  #   actual_data: Actual biomechanics
  #   milb_pitch_data: Original MiLB pitch context
  #   variable: Which variable to analyze
  #
  # Returns:
  #   Analysis of error patterns and confounding factors
  
  cat(sprintf("\n=== Error Pattern Analysis: %s ===\n", variable))
  
  pred_col <- paste0(variable, "_predicted")
  
  # Merge all datasets
  combined <- milb_pitch_data %>%
    mutate(pitch_id = row_number()) %>%
    left_join(
      predictions_wide %>% select(pitch_id, prediction = all_of(pred_col)),
      by = "pitch_id"
    ) %>%
    left_join(
      actual_data %>% select(pitch_id = pitch_id, actual = all_of(variable)),
      by = "pitch_id"
    ) %>%
    filter(!is.na(actual) & !is.na(prediction)) %>%
    mutate(
      error = prediction != actual,
      correct = !error
    )
  
  # Pattern 1: By pitch type
  cat("\nAccuracy by Pitch Type:\n")
  by_pitch <- combined %>%
    group_by(pitch_name) %>%
    summarise(
      accuracy = sum(correct) / n(),
      n_pitches = n(),
      .groups = "drop"
    ) %>%
    arrange(accuracy)
  print(by_pitch)
  
  # Pattern 2: By batter handedness
  cat("\nAccuracy by Batter Handedness:\n")
  by_stand <- combined %>%
    group_by(stand) %>%
    summarise(
      accuracy = sum(correct) / n(),
      n_pitches = n(),
      .groups = "drop"
    )
  print(by_stand)
  
  # Pattern 3: By pitch zone
  cat("\nAccuracy by Pitch Zone:\n")
  by_zone <- combined %>%
    group_by(zone) %>%
    summarise(
      accuracy = sum(correct) / n(),
      n_pitches = n(),
      .groups = "drop"
    ) %>%
    arrange(accuracy) %>%
    head(10)
  print(by_zone)
  
  # Identify high-error subgroups
  problem_groups <- by_pitch %>%
    filter(accuracy < 0.5)
  
  if (nrow(problem_groups) > 0) {
    cat("\n⚠ Low-accuracy pitch types:\n")
    print(problem_groups)
    cat("Recommendation: Review network relationships for these pitch types\n")
  }
  
  return(invisible(combined))
}

# ==============================================================================
# ITERATIVE REFINEMENT GUIDANCE
# ==============================================================================

generate_refinement_recommendations <- function(validation_results) {
  # Based on validation results, suggest network improvements
  #
  # Args:
  #   validation_results: Output from validate_predictions()
  #
  # Returns:
  #   List of recommended refinements with priority
  
  cat("\n=== Network Refinement Recommendations ===\n")
  
  recommendations <- list()
  
  for (i in seq_len(nrow(validation_results))) {
    row <- validation_results[i, ]
    var <- row$variable
    accuracy <- row$overall_accuracy
    
    if (accuracy < 0.6) {
      priority <- "HIGH"
    } else if (accuracy < 0.75) {
      priority <- "MEDIUM"
    } else {
      priority <- "LOW"
    }
    
    recommendations[[i]] <- list(
      variable = var,
      accuracy = accuracy,
      priority = priority,
      suggestion = generate_suggestion_for_var(var, row)
    )
  }
  
  # Print recommendations in priority order
  sorted_recs <- recommendations[order(sapply(recommendations, "[[", "priority"))]
  
  for (rec in sorted_recs) {
    cat(sprintf("\n[%s] %s (accuracy: %.1f%%)\n",
                rec$priority, rec$variable, rec$accuracy * 100))
    cat(sprintf("  → %s\n", rec$suggestion))
  }
  
  return(recommendations)
}

generate_suggestion_for_var <- function(variable, results_row) {
  # Generate specific refinement suggestion based on variable and error pattern
  
  suggestion <- case_when(
    variable == "attack_angle" ~ 
      "Consider separating attack angle by pitch type in the network. Spin rate or vertical movement may influence this more than currently captured.",
    
    variable == "swing_path_tilt" ~
      "Swing tilt may depend more heavily on pitch location (zone) or previous pitches (sequence). Test adding pitcher hand or handedness interaction.",
    
    # variable == "contact_depth" ~
    #   "Contact depth is hard to infer from outcomes. Consider adding features like batter swing-and-miss rate or patience metrics if available.",
    
    variable == "attack_direction" ~
      "Attack direction shows systematic patterns by batter handedness. Ensure stand variable is properly conditioning all direction nodes.",
    
    variable == "bat_speed" ~
      "Bat speed depends on many unobserved factors (fatigue, count, etc.). Try adding discrete player 'category' (power hitter vs contact hitter).",
    
    variable == "intercept_x" | variable == "intercept_y" ~
      "Contact position predictions may need player-specific calibration. Test learning separate CPTs for subgroups of batters.",
    
    TRUE ~ "Consider adding additional edges or refining discretization for this variable."
  )
  
  return(suggestion)
}

# ==============================================================================
# TRACK NETWORK EVOLUTION
# ==============================================================================

log_network_version <- function(
  version_number,
  changes_made,
  validation_metrics = NULL,
  notes = "",
  log_path = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/network_evolution_log.csv"
) {
  # Create log entry documenting network changes and validation results
  # Allows you to track which versions work best and why
  
  log_entry <- data.frame(
    timestamp = Sys.time(),
    version = version_number,
    changes = changes_made,
    avg_accuracy = ifelse(!is.null(validation_metrics), 
                          mean(validation_metrics$overall_accuracy, na.rm = TRUE),
                          NA),
    notes = notes
  )
  
  if (file.exists(log_path)) {
    existing_log <- fread(log_path)
    updated_log <- rbind(existing_log, log_entry)
  } else {
    updated_log <- log_entry
  }
  
  fwrite(updated_log, log_path)
  
  cat("✓ Logged network version", version_number, "\n")
  
  return(updated_log)
}

print_network_evolution <- function(
  log_path = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/network_evolution_log.csv"
) {
  # Print summary of all network versions tested
  
  if (!file.exists(log_path)) {
    cat("No evolution log found yet.\n")
    return(NULL)
  }
  
  evolution_log <- fread(log_path)
  
  cat("\n=== Bayesian Network Evolution Log ===\n")
  print(evolution_log %>%
          arrange(version) %>%
          select(version, timestamp, avg_accuracy, changes))
  
  return(evolution_log)
}

# ==============================================================================
# EXPECTED VALUE OF PERFECT INFORMATION (EVPI)
# ==============================================================================

compute_evpi <- function(
  actual_data,
  predictions_wide,
  variables = c("attack_angle", "swing_path_tilt", "attack_direction", "bat_speed", "intercept_x", "intercept_y")
) {
  # Compute how much improvement could theoretically be gained
  # by better understanding each variable's relationships
  #
  # EVPI = Expected value if we knew true value perfectly
  #      - Expected value with current predictions
  #
  # High EVPI = high value in improving that variable's prediction
  
  cat("\n=== Expected Value of Perfect Information ===\n")
  
  evpi_results <- data.frame()
  
  for (var in variables) {
    pred_col <- paste0(var, "_predicted")
    
    if (!(pred_col %in% names(predictions_wide))) next
    
    comparison <- predictions_wide %>%
      select(pitch_id, prediction = all_of(pred_col)) %>%
      left_join(
        actual_data %>% select(pitch_id, actual = all_of(var)),
        by = "pitch_id"
      ) %>%
      filter(!is.na(actual))
    
    # Current accuracy
    current_accuracy <- sum(comparison$prediction == comparison$actual) / nrow(comparison)
    
    # Perfect information would give 100% accuracy
    perfect_accuracy <- 1.0
    
    # EVPI as improvement potential (percent points)
    evpi <- perfect_accuracy - current_accuracy
    
    evpi_results <- rbind(evpi_results, data.frame(
      variable = var,
      current_accuracy = current_accuracy,
      evpi = evpi,
      improvement_potential = sprintf("%.1f%%", evpi * 100)
    ))
  }
  
  print(evpi_results)
  
  cat("\nInterpretation: Variables with high EVPI have the most room for improvement\n")
  cat("Priority refinement work on: high EVPI variables\n")
  
  return(evpi_results)
}

# ==============================================================================
# EXPORT
# ==============================================================================

if (!exists("validation_framework_config")) {
  validation_framework_config <- list(
    validate_predictions = validate_predictions,
    analyze_error_patterns = analyze_error_patterns,
    generate_refinement_recommendations = generate_refinement_recommendations,
    log_network_version = log_network_version,
    print_network_evolution = print_network_evolution,
    compute_evpi = compute_evpi
  )
}
