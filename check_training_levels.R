#!/usr/bin/env Rscript
# Check what zone values are in training data

library(tidyverse)
library(data.table)
library(bnlearn)

source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")

cat("\n[Setup] Creating training data...\n")
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("\nTRAINING DATA FACTOR LEVELS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")

for (col in cols) {
  levels_vec <- levels(training_data[[col]])
  cat(sprintf("%s: %s\n", col, paste(levels_vec, collapse=" | ")))
}

cat("\n\nCHECK: Do zone 14 exist?\n")
cat("All zone values:", levels(training_data$zone), "\n")
cat("Max zone:", max(as.integer(levels(training_data$zone))), "\n")
