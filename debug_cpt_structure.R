#!/usr/bin/env Rscript
# ==============================================================================
# Debug: Examine CPT structure
# ==============================================================================

library(tidyverse)
library(data.table)
library(bnlearn)

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_parameter_learning.R")

cat("\n[1/2] Setting up...\n")
bn <- create_biomech_network()
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("\n[2/2] Learning network parameters...\n")
fitted_bn <- learn_network_parameters(
  training_data = training_data,
  bn_structure = bn,
  method = "bayes",
  smoothing = 1
)

cat("\n═══════════════════════════════════════════════════════════════════\n")
cat("CPT STRUCTURE ANALYSIS\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Examine a single CPT
cpt_node <- fitted_bn$cpt$stand
cat("Node: stand\n")
cat("Class:", class(cpt_node), "\n")
cat("Dimensions:", dim(cpt_node), "\n")
cat("Names of CPT object:\n")
print(names(attributes(cpt_node)))

cat("\nDimnames:\n")
print(dimnames(cpt_node))

cat("\nActual CPT values:\n")
print(cpt_node)

cat("\n\nExtracting dimnames correctly:\n")
dimnames_list <- dimnames(cpt_node)
if (!is.null(dimnames_list)) {
  cat("Number of dimensions:", length(dimnames_list), "\n")
  for (i in seq_along(dimnames_list)) {
    cat(sprintf("  Dimension %d: %s\n", i, paste(dimnames_list[[i]], collapse=", ")))
  }
}
