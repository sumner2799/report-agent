#!/usr/bin/env Rscript
# Debug inference batch function

library(tidyverse)
library(data.table)
library(bnlearn)

source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

cat("\n[Setup] Creating network and training data...\n")
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

bn <- create_biomech_network()
fitted_bn <- learn_network_parameters(
  training_data = training_data,
  bn_structure = bn,
  method = "bayes",
  smoothing = 1
)

cat("\n[1/2] Prepare MiLB data...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 2"
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

cat("\n[2/2] Check extracted row...\n\n")

pitch_row <- milb_factors[1, ]

cat("Extracting individual fields:\n")
cat(sprintf("  pitch_row$stand class: %s\n", class(pitch_row$stand)))
cat(sprintf("  pitch_row$zone class: %s\n", class(pitch_row$zone)))
cat(sprintf("  pitch_row$pitch_name class: %s\n", class(pitch_row$pitch_name)))

# Extract as list element vs vector element
cat("\nExtracted as vector element:\n")
stand_vec <- pitch_row$stand
cat(sprintf("  class(stand_vec): %s\n", class(stand_vec)))
cat(sprintf("  length(stand_vec): %d\n", length(stand_vec)))
cat(sprintf("  as.character(stand_vec): %s\n", as.character(stand_vec)))

# Build evidence list
cat("\nBuilding evidence list:\n")
evidence <- list()
if (!is.na(pitch_row$stand)) {
  evidence$stand <- as.character(pitch_row$stand[1])
  cat(sprintf("  Added stand: %s (class=%s)\n", evidence$stand, class(evidence$stand)))
}

if (!is.na(pitch_row$zone)) {
  evidence$zone <- as.character(pitch_row$zone[1])
  cat(sprintf("  Added zone: %s (class=%s)\n", evidence$zone, class(evidence$zone)))
}

if (!is.na(pitch_row$pitch_name)) {
  evidence$pitch_name <- as.character(pitch_row$pitch_name[1])
  cat(sprintf("  Added pitch_name: %s (class=%s)\n", evidence$pitch_name, class(evidence$pitch_name)))
}

if (!is.na(pitch_row$spray_angle)) {
  evidence$spray_angle <- as.character(pitch_row$spray_angle[1])
  cat(sprintf("  Added spray_angle: %s (class=%s)\n", evidence$spray_angle, class(evidence$spray_angle)))
}

cat(sprintf("\nTotal evidence: %d variables\n", length(evidence)))

# Now try inference with the evidence list
cat("\nRunning cpdist()...\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = evidence,
    method = "ls",
    n = 1000
  )
  
  if (nrow(result) == 0) {
    cat("✗ Empty result\n")
  } else {
    cat(sprintf("✓ Success: %d rows\n", nrow(result)))
    print(head(result))
  }
}, error = function(e) {
  cat(sprintf("✗ Error: %s\n", as.character(e)))
})

DBI::dbDisconnect(conn)

cat("\n")
