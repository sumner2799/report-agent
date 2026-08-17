# ==============================================================================
# Apply Bayesian Network to MiLB Data
# ==============================================================================
# Purpose: Load MiLB Statcast data, preprocess to match network format,
# run inference to impute missing biomechanics, and create audit trail
# for future validation and network refinement

library(tidyverse)
library(data.table)
library(bnlearn)
library(stringr)
library(RMySQL)

# ==============================================================================
# LOAD AND PREPROCESS MiLB DATA
# ==============================================================================

load_milb_statcast_files <- function(raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw") {
  # Load all MiLB Statcast CSV files
  # Assumes different field structure than MLB (e.g., matchup.batSide.code, pitchData.zone)
  
  conn <- dbConnect(
    MySQL(),
    host = "127.0.0.1",
    user = "root",
    password = "Fletcher!23",
    dbname = "DBPuzz"
  )


  ## These game_pk's are good for week 6/3
  statcast_data <- dbGetQuery(conn,glue::glue(
    "select
  *   
  from
  sc_milb
  where
  game_date >= '2026-01-01'
  and game_date <= '2026-05-31'

  ",
    .con = conn
    )
  )
  
  cat("Total rows loaded:", nrow(statcast_data), "\n")
  return(statcast_data)
}

# ==============================================================================
# NORMALIZE MiLB DATA TO NETWORK FORMAT
# ==============================================================================

normalize_milb_field_names <- function(df) {
  # Map MiLB field names to network node names
  # MiLB uses different structure: matchup.batSide.code, pitchData.zone, hitData.launchSpeed
  # vs MLB: stand, zone, launch_speed
  
  df_normalized <- df %>%
    rename(
      # Pitch context - normalize field names
      stand = if_else("matchup.batSide.code" %in% names(df),
                     "matchup.batSide.code",
                     if_else("stand" %in% names(df), "stand", NA_character_)),
      zone = if_else("pitchData.zone" %in% names(df),
                    "pitchData.zone",
                    if_else("zone" %in% names(df), "zone", NA_character_)),
      pitch_name = if_else("details.type.description" %in% names(df),
                          "details.type.description",
                          if_else("pitch_type" %in% names(df), "pitch_type", NA_character_)),
      
      # Observable outcomes
      launch_speed = if_else("hitData.launchSpeed" %in% names(df),
                            "hitData.launchSpeed",
                            if_else("launch_speed" %in% names(df), "launch_speed", NA_character_)),
      launch_angle = if_else("hitData.launchAngle" %in% names(df),
                            "hitData.launchAngle",
                            if_else("launch_angle" %in% names(df), "launch_angle", NA_character_)),
      
      # Spray angle (computed from hc_x, hc_y in both)
      hc_x = if_else("hitData.coordinates.coordX" %in% names(df),
                    "hitData.coordinates.coordX",
                    if_else("hc_x" %in% names(df), "hc_x", NA_character_)),
      hc_y = if_else("hitData.coordinates.coordY" %in% names(df),
                    "hitData.coordinates.coordY",
                    if_else("hc_y" %in% names(df), "hc_y", NA_character_))
    )
  
  return(df_normalized)
}

discretize_milb_variables <- function(df, discretization_scheme) {
  # Apply same discretization to MiLB data as training data
  # Important: Only discretize observable variables (launch_speed, launch_angle)
  # Hidden biomechanics will be filled in by inference as NA (by design)
  
  df <- df %>%
    mutate(
      launch_speed_binned = cut(
        launch_speed,
        breaks = discretization_scheme$launch_speed$breaks,
        labels = discretization_scheme$launch_speed$levels,
        include.lowest = TRUE
      ),
      
      launch_angle_binned = cut(
        launch_angle,
        breaks = discretization_scheme$launch_angle$breaks,
        labels = discretization_scheme$launch_angle$levels,
        include.lowest = TRUE
      )
    )
  
  return(df)
}

normalize_milb_spray_angle <- function(df) {
  # Normalize spray angle by batter handedness (same as MLB preprocessing)
  
  df <- df %>%
    mutate(
      spray_angle_raw = case_when(
        is.na(hc_x) | is.na(hc_y) ~ NA_real_,
        TRUE ~ round(
          (atan(
            (hc_x - 125.42) / (198.27 - hc_y)
          ) * 180 / pi * 0.75),
          1
        )  # Correct spray angle formula with field-specific constants
      ),
      
      spray_angle_normalized = case_when(
        stand == "L" & spray_angle_raw > 15 ~ "pull",
        stand == "L" & spray_angle_raw < -15 ~ "oppo",
        stand == "L" ~ "center",
        stand == "R" & spray_angle_raw < -15 ~ "pull",
        stand == "R" & spray_angle_raw > 15 ~ "oppo",
        stand == "R" ~ "center",
        TRUE ~ NA_character_
      )
    )
  
  return(df)
}

convert_to_network_factors <- function(df, training_data) {
  # Convert MiLB character/integer columns to factors matching training data
  # This is essential for inference to work - evidence must match network factor levels
  
  # Verify training data has ALL required factor columns
  required_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")
  for (col in required_cols) {
    if (!col %in% colnames(training_data)) {
      stop(sprintf("ERROR: training_data$%s doesn't exist", col))
    }
    if (!is.factor(training_data[[col]])) {
      stop(sprintf("ERROR: training_data$%s is not a factor (class: %s)", col, class(training_data[[col]])[1]))
    }
  }
  
  df <- df %>%
    mutate(
      # Convert stand to factor (should already be L/R, but ensure consistency)
      stand = factor(stand, levels = levels(training_data$stand)),
      
      # Convert zone to factor matching training levels
      zone = factor(as.character(zone), levels = levels(training_data$zone)),
      
      # Convert pitch_name to factor, mapping unknown values to "Other"
      pitch_name = case_when(
        is.na(pitch_name) ~ NA_character_,
        pitch_name %in% levels(training_data$pitch_name) ~ pitch_name,
        TRUE ~ "Other"
      ),
      pitch_name = factor(pitch_name, levels = levels(training_data$pitch_name)),
      
      # Convert launch_speed to factor (must already be in bin format from discretization)
      launch_speed = if_else(
        is.na(launch_speed),
        NA_character_,
        as.character(launch_speed)
      ),
      launch_speed = factor(launch_speed, levels = levels(training_data$launch_speed)),
      
      # Convert launch_angle to factor (must already be in bin format from discretization)
      launch_angle = if_else(
        is.na(launch_angle),
        NA_character_,
        as.character(launch_angle)
      ),
      launch_angle = factor(launch_angle, levels = levels(training_data$launch_angle)),
      
      # Convert spray_angle to factor (handle NAs properly)
      spray_angle = if_else(
        is.na(spray_angle),
        NA_character_,
        spray_angle
      ),
      spray_angle = factor(spray_angle, levels = levels(training_data$spray_angle))
    )
  
  return(df)
}

prepare_milb_for_inference <- function(
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = NULL,
  training_data = NULL
) {
  # Master function to load and preprocess MiLB data for inference
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
  
  if (is.null(discretization_scheme)) {
    discretization_scheme <- create_discretization_scheme()
  }
  
  # If training_data not provided, prepare it (to get factor levels)
  if (is.null(training_data)) {
    training_data <- prepare_training_data(
      discretization_scheme = discretization_scheme,
      min_data_quality_threshold = 0.0  # Prepare with all data for levels
    )
  }
  
  cat("\n=== Preparing MiLB Data for Inference ===\n")
  
  # 1. Load
  cat("\nStep 1: Loading MiLB Statcast...\n")
  milb_data <- load_milb_statcast_files(raw_data_dir)
  
  # 2. Normalize field names
  cat("\nStep 2: Normalizing field names...\n")
  milb_data <- normalize_milb_field_names(milb_data)
  
  # 3. Normalize spray angle
  cat("\nStep 3: Normalizing spray angle...\n")
  milb_data <- normalize_milb_spray_angle(milb_data)
  
  # 4. Discretize observed variables
  cat("\nStep 4: Discretizing variables...\n")
  milb_data <- discretize_milb_variables(milb_data, discretization_scheme)
  
  # 5. Select and rename for network
  cat("\nStep 5: Selecting and renaming network columns...\n")
  
  milb_for_inference <- milb_data %>%
    # Select only the binned/normalized columns we need, drop originals
    select(stand, zone, pitch_name, 
           launch_speed_binned, launch_angle_binned, spray_angle_normalized,
           matchup.batter.id, matchup.batter.fullName, game_date) %>%
    # Rename binned columns to standard names
    rename(
      launch_speed = launch_speed_binned,
      launch_angle = launch_angle_binned,
      spray_angle = spray_angle_normalized
    )
  
  # 6. Convert to factors matching training data (after column renaming)
  cat("\nStep 6: Converting to network factors...\n")
  milb_for_inference <- convert_to_network_factors(milb_for_inference, training_data)
  
  # 7. Add hidden biomechanics columns as NA (will be filled by inference)
  cat("\nStep 7: Adding hidden biomechanics columns...\n")
  milb_for_inference <- milb_for_inference %>%
    # Add hidden biomechanics columns as NA (will be filled by inference)
    mutate(
      attack_angle = factor(NA_character_, levels = discretization_scheme$attack_angle$levels),
      swing_path_tilt = factor(NA_character_, levels = discretization_scheme$swing_path_tilt$levels),
      attack_direction = factor(NA_character_, levels = discretization_scheme$attack_direction$levels),
      bat_speed = factor(NA_character_, levels = discretization_scheme$bat_speed$levels),
      intercept_x = factor(NA_character_, levels = discretization_scheme$intercept_x$levels),
      intercept_y = factor(NA_character_, levels = discretization_scheme$intercept_y$levels),
      outcome = factor(NA_character_, levels = c("hit", "out", "strikeout"))
    ) %>%
    # Remove rows missing critical evidence
    filter(!is.na(stand) & !is.na(zone) & !is.na(pitch_name)) %>%
    # Keep at least one observable outcome
    filter(!is.na(launch_angle) | !is.na(launch_speed) | !is.na(spray_angle))
  
  cat("\n✓ Prepared", nrow(milb_for_inference), "pitches for inference\n")
  
  return(milb_for_inference)
}

# ==============================================================================
# RUN INFERENCE AND COLLECT RESULTS
# ==============================================================================

apply_network_to_milb <- function(
  fitted_bn,
  milb_data,
  output_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation",
  export_predictions = FALSE  # Set to TRUE only if you need CSV exports
) {
  # Master function to run inference on MiLB pitches
  # By default, just returns predictions (doesn't export CSVs)
  # Set export_predictions=TRUE to save CSV files
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
  
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }
  
  cat("\n=== Applying Network to MiLB Data ===\n")
  
  # Run batch inference
  inference_results <- infer_biomechanics_batch(
    fitted_bn,
    milb_data,
    query_nodes = c(
      "attack_angle", "swing_path_tilt", 
      "attack_direction", "bat_speed", "intercept_x", "intercept_y"
    ),
    method = "exact",
    verbose = TRUE
  )
  
  # Only format if exporting
  results_long <- NULL
  results_wide <- NULL
  confidence_summary <- NULL
  
  if (export_predictions) {
    cat("\nFormatting results...\n")
    results_long <- format_inference_results_long(inference_results, milb_data)
    results_wide <- format_inference_results_wide(inference_results, milb_data)
    
    cat("\nAssessing inference confidence...\n")
    confidence_summary <- assess_inference_confidence(inference_results, milb_data, confidence_threshold = 0.4)
    
    # Save outputs
    cat("\nSaving results...\n")
    fwrite(results_long, file.path(output_dir, "biomech_predictions_long.csv"))
    fwrite(results_wide, file.path(output_dir, "biomech_predictions_wide.csv"))
    fwrite(confidence_summary, file.path(output_dir, "inference_confidence.csv"))
    
    cat("\n✓ Results saved to:", output_dir, "\n")
    cat("  - biomech_predictions_long.csv (probabilities for each level)\n")
    cat("  - biomech_predictions_wide.csv (top predictions + confidence)\n")
    cat("  - inference_confidence.csv (confidence assessment)\n")
  } else {
    cat("\nSkipping CSV export (export_predictions=FALSE)\n")
    cat("Predictions can be accessed via returned list\n")
  }
  
  return(list(
    predictions_long = results_long,
    predictions_wide = results_wide,
    confidence = confidence_summary,
    raw_inference = inference_results
  ))
}

# ==============================================================================
# CREATE AUDIT TRAIL FOR VALIDATION
# ==============================================================================

create_audit_trail <- function(
  milb_data,
  predictions_wide,
  output_path = NULL
) {
  # Create detailed audit trail linking each pitch to:
  # - Original observations (stand, zone, pitch_name, outcomes)
  # - Imputed biomechanics predictions
  # - Confidence scores
  # For future validation when real biomechanics data arrives
  
  if (is.null(output_path)) {
    output_path <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation/audit_trail.csv"
  }
  
  # Combine original data with predictions
  audit_trail <- milb_data %>%
    mutate(pitch_id = row_number()) %>%
    left_join(predictions_wide, by = "pitch_id") %>%
    select(
      pitch_id, matchup.batter.id, matchup.batter.fullName, game_date,
      stand, zone, pitch_name,
      launch_speed, launch_angle, spray_angle,
      starts_with("attack_angle"),
      starts_with("swing_path_tilt"),
      # starts_with("contact_depth"),
      starts_with("attack_direction"),
      starts_with("bat_speed"),
      starts_with("intercept")
    )
  
  fwrite(audit_trail, output_path)
  
  cat("✓ Audit trail saved to:", output_path, "\n")
  cat("  Use this to validate predictions when actual biomechanics data becomes available\n")
  
  return(audit_trail)
}

# ==============================================================================
# EXPORT
# ==============================================================================

if (!exists("milb_application_config")) {
  milb_application_config <- list(
    load_milb_statcast_files = load_milb_statcast_files,
    normalize_milb_field_names = normalize_milb_field_names,
    discretize_milb_variables = discretize_milb_variables,
    normalize_milb_spray_angle = normalize_milb_spray_angle,
    prepare_milb_for_inference = prepare_milb_for_inference,
    apply_network_to_milb = apply_network_to_milb,
    create_audit_trail = create_audit_trail
  )
}
