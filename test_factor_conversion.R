#!/usr/bin/env Rscript
# ==============================================================================
# Test Factor Conversion in MiLB Preprocessing
# ==============================================================================
# Tests that MiLB data is properly converted to factors before inference

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n=== Testing Factor Conversion ===\n")

# 1. Load necessary modules
cat("\n1. Loading modules...\n")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_inference_engine.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# 2. Create network and discretization scheme
cat("\n2. Creating network...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()

# 3. Prepare training data
cat("\n3. Preparing training data...\n")
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme
)
cat("   Training data types:\n")
sapply(training_data, class) %>% head(10) %>% print()

# 4. Prepare MiLB data WITHOUT factor conversion first
cat("\n4. Preparing MiLB data (WITHOUT factor conversion)...\n")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# Manually prepare to see intermediate steps
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 100"
)

cat("   Raw MiLB data types (first 10 columns):\n")
sapply(milb_raw, class) %>% head(10) %>% print()

# 5. Apply normalization
cat("\n5. Normalizing field names...\n")
milb_normalized <- normalize_milb_field_names(milb_raw)

cat("\n6. After normalization:\n")
cat("   stand class:", class(milb_normalized$stand), "\n")
cat("   stand unique values:", paste(unique(milb_normalized$stand), collapse=", "), "\n")
cat("   zone class:", class(milb_normalized$zone), "\n")
cat("   zone unique values:", paste(unique(milb_normalized$zone), collapse=", "), "\n")

# 6. Normalize spray angle
cat("\n7. Normalizing spray angle...\n")
milb_spray <- normalize_milb_spray_angle(milb_normalized)
cat("   spray_angle class:", class(milb_spray$spray_angle), "\n")

# 7. Discretize
cat("\n8. Discretizing observed variables...\n")
milb_disc <- discretize_milb_variables(milb_spray, discretization_scheme)
cat("   launch_speed_binned class:", class(milb_disc$launch_speed_binned), "\n")
cat("   launch_angle_binned class:", class(milb_disc$launch_angle_binned), "\n")

# 8. TEST: Convert to network factors
cat("\n9. TESTING: Converting to network factors...\n")
milb_factors <- convert_to_network_factors(milb_disc, training_data)

cat("\n   AFTER CONVERSION:\n")
cat("   stand class:", class(milb_factors$stand), "\n")
if(class(milb_factors$stand) == "factor") {
  cat("   stand levels:", paste(levels(milb_factors$stand), collapse=", "), "\n")
}

cat("   zone class:", class(milb_factors$zone), "\n")
if(class(milb_factors$zone) == "factor") {
  cat("   zone levels:", paste(levels(milb_factors$zone), collapse=", "), "\n")
}

cat("   pitch_name class:", class(milb_factors$pitch_name), "\n")
if(class(milb_factors$pitch_name) == "factor") {
  cat("   pitch_name levels:", paste(levels(milb_factors$pitch_name), collapse=", "), "\n")
}

cat("   spray_angle class:", class(milb_factors$spray_angle), "\n")
if(class(milb_factors$spray_angle) == "factor") {
  cat("   spray_angle levels:", paste(levels(milb_factors$spray_angle), collapse=", "), "\n")
}

cat("\n✓ Factor conversion test complete\n")
cat("\n   Next step: Test inference with factor-typed evidence\n")

DBI::dbDisconnect(conn)
