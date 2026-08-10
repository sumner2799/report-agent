#!/usr/bin/env Rscript
# Test converting actual MiLB data

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

cat("\n[1/2] Load one MiLB pitch and convert...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

milb_raw <- DBI::dbGetQuery(conn, "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 1")
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

cat("\n[2/2] Convert to factors...\n")
milb_factors <- convert_to_network_factors(milb_sel, training_data)

cat("\nPITCH AFTER FACTOR CONVERSION\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

pitch <- milb_factors[1, ]

cat("Batter:", pitch$matchup.batter.fullName, "\n")
cat("Date:", pitch$game_date, "\n\n")

# Check each evidence column
evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")

for (col in evidence_cols) {
  value <- pitch[[col]]
  is_factor <- is.factor(value)
  
  cat(sprintf("%s:\n", col))
  cat(sprintf("  Value: %s\n", if(is.na(value)) "NA" else as.character(value)))
  cat(sprintf("  Is factor: %s\n", is_factor))
  
  if (is_factor) {
    cat(sprintf("  Factor levels: %s\n", paste(levels(value), collapse=", ")))
    
    # Check if value is in training levels
    training_levels <- levels(training_data[[col]])
    if (!is.na(value)) {
      in_training <- as.character(value) %in% training_levels
      cat(sprintf("  In training levels: %s\n", if(in_training) "✓ YES" else "✗ NO"))
    }
  }
  cat("\n")
}

# Now try inference with this pitch
cat("═══════════════════════════════════════════════════════════════════\n")
cat("ATTEMPT INFERENCE\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

evidence <- list()
for (col in evidence_cols) {
  value <- pitch[[col]]
  if (!is.na(value)) {
    evidence[[col]] <- value
    cat(sprintf("Evidence: %s = %s\n", col, as.character(value)))
  }
}

cat(sprintf("\nTotal evidence variables: %d\n\n", length(evidence)))

# Try inference
cat("Running cpdist()...\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = evidence,
    method = "lw",
    n = 10000
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
