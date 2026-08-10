#!/usr/bin/env Rscript
# Test evidence format for cpdist()

library(tidyverse)
library(data.table)
library(bnlearn)

source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")

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

cat("\nTESTING EVIDENCE FORMATS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Method 1: Character strings
cat("Method 1: Evidence as character strings\n")
tryCatch({
  evidence <- list(
    stand = "L",
    zone = "7"
  )
  result <- cpdist(fitted_bn, nodes = "attack_angle", evidence = evidence, method = "lw", n = 1000)
  cat(sprintf("  ✓ Success: %d rows\n", nrow(result)))
}, error = function(e) {
  cat(sprintf("  ✗ Error: %s\n", as.character(e)))
})

# Method 2: Factors with matching levels
cat("\nMethod 2: Evidence as factors with matching levels\n")
tryCatch({
  evidence <- list(
    stand = factor("L", levels = levels(training_data$stand)),
    zone = factor("7", levels = levels(training_data$zone))
  )
  result <- cpdist(fitted_bn, nodes = "attack_angle", evidence = evidence, method = "lw", n = 1000)
  cat(sprintf("  ✓ Success: %d rows\n", nrow(result)))
}, error = function(e) {
  cat(sprintf("  ✗ Error: %s\n", as.character(e)))
})

# Method 3: Factors converted from data
cat("\nMethod 3: Evidence as single-element factors from data\n")
test_data <- data.frame(
  stand = factor("L", levels = levels(training_data$stand)),
  zone = factor("7", levels = levels(training_data$zone))
)
tryCatch({
  evidence <- list(
    stand = test_data$stand,
    zone = test_data$zone
  )
  cat(sprintf("  Evidence types: %s, %s\n", class(evidence$stand), class(evidence$zone)))
  cat(sprintf("  Evidence lengths: %d, %d\n", length(evidence$stand), length(evidence$zone)))
  result <- cpdist(fitted_bn, nodes = "attack_angle", evidence = evidence, method = "lw", n = 1000)
  cat(sprintf("  ✓ Success: %d rows\n", nrow(result)))
}, error = function(e) {
  cat(sprintf("  ✗ Error: %s\n", as.character(e)))
})

# Method 4: Character scalar converted to factor
cat("\nMethod 4: Character scalar, then converted to factor\n")
test_data <- data.frame(
  stand = factor("L", levels = levels(training_data$stand)),
  zone = factor("7", levels = levels(training_data$zone))
)
tryCatch({
  stand_char <- as.character(test_data$stand[1])
  zone_char <- as.character(test_data$zone[1])
  evidence <- list(
    stand = factor(stand_char, levels = levels(training_data$stand)),
    zone = factor(zone_char, levels = levels(training_data$zone))
  )
  result <- cpdist(fitted_bn, nodes = "attack_angle", evidence = evidence, method = "lw", n = 1000)
  cat(sprintf("  ✓ Success: %d rows\n", nrow(result)))
}, error = function(e) {
  cat(sprintf("  ✗ Error: %s\n", as.character(e)))
})

cat("\n")
