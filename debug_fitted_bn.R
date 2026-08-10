#!/usr/bin/env Rscript
# ==============================================================================
# Debug: Check fitted_bn structure
# ==============================================================================

library(tidyverse)
library(data.table)
library(bnlearn)

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")

cat("\n[Setup] Creating training data...\n")
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("Training data columns:", colnames(training_data), "\n")
cat("Training data types:\n")
for (col in colnames(training_data)) {
  cat(sprintf("  %s: %s\n", col, class(training_data[[col]][1])))
}

cat("\n[1/2] Creating network...\n")
bn <- create_biomech_network()
cat("Network structure:\n")
print(bn)

cat("\n[2/2] Learning network parameters...\n")
fitted_bn <- bn.fit(
  x = bn,
  data = training_data,
  method = "bayes",
  iss = 1
)

cat("\nFitted BN class:", class(fitted_bn), "\n")
cat("Fitted BN attributes:\n")
print(names(attributes(fitted_bn)))

cat("\nFitted BN structure (first 500 chars):\n")
str_out <- capture.output(str(fitted_bn, max.level = 1))
cat(paste(str_out[1:30], collapse="\n"))

cat("\n\nAccessing fitted_bn elements:\n")
cat("Names of fitted_bn:", names(fitted_bn), "\n\n")

# Try different access methods
cat("Method 1: fitted_bn$stand\n")
result1 <- fitted_bn$stand
cat("  Class:", class(result1), "\n")
if (!is.null(result1)) {
  cat("  Dimensions:", dim(result1), "\n")
  print(result1)
}

cat("\n\nMethod 2: fitted_bn[[1]]\n")
result2 <- fitted_bn[[1]]
cat("  Class:", class(result2), "\n")
if (!is.null(result2)) {
  cat("  Dimensions:", dim(result2), "\n")
  print(head(result2))
}
