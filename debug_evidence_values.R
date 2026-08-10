#!/usr/bin/env Rscript
# ==============================================================================
# Debug: Show exact evidence values being passed to inference
# ==============================================================================

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   DEBUG: Evidence Values vs CPT Levels                        ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# ==============================================================================
# STEP 1: Setup
# ==============================================================================

cat("\n[1/3] Setting up network and training data...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("[2/3] Learning network parameters...\n")
fitted_bn <- learn_network_parameters(
  training_data = training_data,
  bn_structure = bn,
  method = "bayes",
  smoothing = 1
)

# ==============================================================================
# STEP 2: Load MiLB data
# ==============================================================================

cat("\n[3/3] Loading and preparing MiLB data...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 5"
)

milb_prepared <- prepare_milb_for_inference(
  raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = discretization_scheme,
  training_data = training_data
)

DBI::dbDisconnect(conn)

# ==============================================================================
# STEP 3: Compare each pitch's evidence with CPT
# ==============================================================================

cat("\n═══════════════════════════════════════════════════════════════════\n")
cat("ANALYZING EACH PITCH'S EVIDENCE\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")

for (i in 1:min(3, nrow(milb_prepared))) {
  pitch <- milb_prepared[i, ]
  
  cat(sprintf("\n┌─ PITCH #%d ─────────────────────────────────────────────\n", i))
  cat(sprintf("Batter: %s\n", pitch$matchup.batter.fullName))
  cat(sprintf("Date: %s\n\n", pitch$game_date))
  
  # Show factor levels available in CPT
  cat("CPT Factor Levels Available:\n")
  for (col in evidence_cols) {
    cpt_node <- fitted_bn$cpt[[col]]
    cpt_dimnames <- attr(cpt_node, "dimnames")
    cpt_levels <- cpt_dimnames[[1]]
    cat(sprintf("  %s: %s\n", col, paste(cpt_levels, collapse=", ")))
  }
  
  cat("\nEvidence from this pitch:\n")
  
  # Build evidence from the pitch
  evidence_list <- list()
  has_evidence <- FALSE
  
  for (col in evidence_cols) {
    value <- pitch[[col]]
    is_na <- is.na(value)
    
    if (!is_na) {
      evidence_list[[col]] <- value
      has_evidence <- TRUE
      
      # Check if this value is in CPT
      cpt_node <- fitted_bn$cpt[[col]]
      cpt_dimnames <- attr(cpt_node, "dimnames")
      cpt_levels <- cpt_dimnames[[1]]
      
      in_cpt <- as.character(value) %in% cpt_levels
      
      cat(sprintf("  %s = %s (type: %s) ", col, as.character(value), class(value)[1]))
      if (in_cpt) {
        cat("✓ IN CPT\n")
      } else {
        cat(sprintf("✗ NOT IN CPT (levels: %s)\n", paste(cpt_levels, collapse=", ")))
      }
    } else {
      cat(sprintf("  %s = NA (skipped)\n", col))
    }
  }
  
  if (!has_evidence) {
    cat("  ✗ NO EVIDENCE - Cannot run inference\n")
  } else {
    cat(sprintf("\n  Total evidence variables: %d\n", length(evidence_list)))
    
    # Try inference
    cat("\n  Running inference...\n")
    tryCatch({
      result <- cpdist(
        fitted_bn,
        nodes = "attack_angle",
        evidence = evidence_list,
        method = "exact"
      )
      
      if (nrow(result) == 0) {
        cat("  ✗ Empty result from cpdist\n")
        cat("    This means NO CPT entries match ALL evidence variables together\n")
      } else {
        cat(sprintf("  ✓ Success: %d CPT entries matched\n", nrow(result)))
        print(head(result))
      }
    }, error = function(e) {
      cat(sprintf("  ✗ Error: %s\n", as.character(e)))
    })
  }
  
  cat("└─────────────────────────────────────────────────────────\n")
}

cat("\n")
