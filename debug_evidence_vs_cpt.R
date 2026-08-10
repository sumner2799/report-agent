#!/usr/bin/env Rscript
# ==============================================================================
# Debug: Check Evidence vs CPT Factor Levels
# ==============================================================================
# This script compares the factor levels in evidence with the CPT

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   DEBUG: Evidence vs CPT Factor Levels                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# ==============================================================================
# STEP 1: Setup
# ==============================================================================

cat("\n[1/4] Setting up network and training data...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("[2/4] Learning network parameters...\n")
fitted_bn <- learn_network_parameters(
  training_data = training_data,
  bn_structure = bn,
  method = "bayes",
  smoothing = 1
)

# ==============================================================================
# STEP 2: Load one MiLB pitch
# ==============================================================================

cat("\n[3/4] Loading one MiLB pitch...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 1"
)

milb_norm <- normalize_milb_field_names(milb_raw)
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

milb_factors <- convert_to_network_factors(milb_sel, training_data)

cat("✓ MiLB pitch prepared\n\n")

# ==============================================================================
# STEP 3: Compare factor levels
# ==============================================================================

cat("[4/4] COMPARING FACTOR LEVELS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

pitch_row <- milb_factors[1, ]

# Check each evidence variable
evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")

for (col in evidence_cols) {
  if (col %in% colnames(pitch_row)) {
    value <- pitch_row[[col]]
    
    cat(sprintf("\n%s:\n", col))
    cat(sprintf("  MiLB value: %s (class: %s)\n", 
                if(is.na(value)) "NA" else as.character(value),
                class(value)))
    
    # Get CPT node
    if (col %in% names(fitted_bn$cpt)) {
      cpt_node <- fitted_bn$cpt[[col]]
      cpt_dimnames <- attr(cpt_node, "dimnames")
      
      if (!is.null(cpt_dimnames) && length(cpt_dimnames) > 0) {
        # First dimension is the variable itself
        var_levels <- cpt_dimnames[[1]]
        
        cat(sprintf("  CPT levels: %s\n", paste(var_levels, collapse=", ")))
        
        # Check if value matches
        if (!is.na(value)) {
          matches <- as.character(value) %in% var_levels
          cat(sprintf("  Match in CPT: %s\n", if(matches) "✓ YES" else "✗ NO"))
          
          if (!matches) {
            cat(sprintf("  ERROR: '%s' not in CPT levels!\n", as.character(value)))
          }
        } else {
          cat(sprintf("  Value is NA - will be skipped in inference\n")
          )
        }
      } else {
        cat("  WARNING: Could not extract CPT levels\n")
      }
    } else {
      cat(sprintf("  WARNING: '%s' not in fitted network CPT\n", col))
    }
  }
}

# ==============================================================================
# STEP 4: Try actual inference
# ==============================================================================

cat("\n\n═══════════════════════════════════════════════════════════════════\n")
cat("ATTEMPTING INFERENCE WITH THIS PITCH\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Build evidence from the pitch
evidence <- list()
if (!is.na(pitch_row$stand)) {
  evidence$stand <- pitch_row$stand
  cat(sprintf("Adding evidence: stand = %s\n", pitch_row$stand))
}
if (!is.na(pitch_row$zone)) {
  evidence$zone <- pitch_row$zone
  cat(sprintf("Adding evidence: zone = %s\n", pitch_row$zone))
}
if (!is.na(pitch_row$pitch_name)) {
  evidence$pitch_name <- pitch_row$pitch_name
  cat(sprintf("Adding evidence: pitch_name = %s\n", pitch_row$pitch_name))
}
if (!is.na(pitch_row$launch_angle)) {
  evidence$launch_angle <- pitch_row$launch_angle
  cat(sprintf("Adding evidence: launch_angle = %s\n", pitch_row$launch_angle))
}
if (!is.na(pitch_row$launch_speed)) {
  evidence$launch_speed <- pitch_row$launch_speed
  cat(sprintf("Adding evidence: launch_speed = %s\n", pitch_row$launch_speed))
}
if (!is.na(pitch_row$spray_angle)) {
  evidence$spray_angle <- pitch_row$spray_angle
  cat(sprintf("Adding evidence: spray_angle = %s\n", pitch_row$spray_angle))
}

cat(sprintf("\nTotal evidence variables: %d\n\n", length(evidence)))

# Try inference
cat("Running cpdist()...\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = evidence,
    method = "exact"
  )
  
  if (nrow(result) == 0) {
    cat(sprintf("✗ EMPTY RESULT: cpdist returned 0 rows\n")
    cat("This means NO CPT rows match the evidence!\n\n")
    cat("Possible causes:\n")
    cat("  1. Factor level mismatch (evidence value not in CPT levels)\n")
    cat("  2. Evidence missing critical variables\n")
    cat("  3. Network structure issue\n\n")
    cat("Check the factor level comparison above for mismatches.\n")
  } else {
    cat(sprintf("✓ SUCCESS: Got %d rows from cpdist\n", nrow(result)))
    cat(sprintf("Sample result:\n")
    print(head(result))
  }
}, error = function(e) {
  cat(sprintf("✗ ERROR: %s\n", as.character(e)))
})

DBI::dbDisconnect(conn)

cat("\n")
