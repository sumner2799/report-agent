#!/usr/bin/env Rscript
# ==============================================================================
# Extract proper factor levels from bn.fit.dnode
# ==============================================================================

library(tidyverse)
library(data.table)
library(bnlearn)

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")

cat("\n[Setup] Creating training data...\n")
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("\n[1/2] Creating and fitting network...\n")
bn <- create_biomech_network()

fitted_bn <- bn.fit(
  x = bn,
  data = training_data,
  method = "bayes",
  iss = 1
)

cat("\nEXAMINING CPT STRUCTURE\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

# Get a node
node_obj <- fitted_bn$stand
cat("Node object class:", class(node_obj), "\n")
cat("Node object structure:\n")
str(node_obj, max.level = 2)

cat("\n\nAccessing the probability table:\n")
prob_table <- node_obj$prob
print(prob_table)

cat("\n\nFactor levels from prob table:\n")
cat("Names:", names(prob_table), "\n")

# For a node with parents (conditional)
cat("\n\nNow checking a node WITH PARENTS:\n")
node_obj2 <- fitted_bn$spray_angle
cat("Node: spray_angle\n")
cat("Node structure:\n")
str(node_obj2, max.level = 2)

cat("\n\nProbability table:\n")
print(node_obj2$prob)

cat("\n\nFactor levels from dimnames:\n")
dimnames_list <- dimnames(node_obj2$prob)
if (!is.null(dimnames_list)) {
  for (i in seq_along(dimnames_list)) {
    cat(sprintf("Dimension %d (%s): %s\n", i, names(dimnames_list)[i], 
                paste(dimnames_list[[i]], collapse=", ")))
  }
}
