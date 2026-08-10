#!/usr/bin/env Rscript
# Test cpdist with simple evidence

library(tidyverse)
library(data.table)
library(bnlearn)

source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")

cat("\n[Setup] Creating and learning network...\n")
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

cat("\n\nTESTING CPDIST\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Test 1: Simplest evidence
cat("Test 1: Only stand=L\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = list(stand = factor("L", levels = c("L", "R"))),
    method = "lw",
    n = 10000
  )
  cat(sprintf("  Result: %d rows\n", nrow(result)))
  if (nrow(result) > 0) print(head(result))
}, error = function(e) cat(sprintf("  ERROR: %s\n", e)))

# Test 2: Add zone
cat("\nTest 2: stand=L, zone=1\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = list(
      stand = factor("L", levels = levels(training_data$stand)),
      zone = factor("1", levels = levels(training_data$zone))
    ),
    method = "lw",
    n = 10000
  )
  cat(sprintf("  Result: %d rows\n", nrow(result)))
  if (nrow(result) > 0) print(head(result))
}, error = function(e) cat(sprintf("  ERROR: %s\n", e)))

# Test 3: Add spray_angle
cat("\nTest 3: stand=L, zone=1, spray_angle=center\n")
tryCatch({
  result <- cpdist(
    fitted_bn,
    nodes = "attack_angle",
    evidence = list(
      stand = factor("L", levels = levels(training_data$stand)),
      zone = factor("1", levels = levels(training_data$zone)),
      spray_angle = factor("center", levels = levels(training_data$spray_angle))
    ),
    method = "lw",
    n = 10000
  )
  cat(sprintf("  Result: %d rows\n", nrow(result)))
  if (nrow(result) > 0) print(head(result))
}, error = function(e) cat(sprintf("  ERROR: %s\n", e)))

cat("\n")
