#!/usr/bin/env Rscript
# ==============================================================================
# Diagnostic: Check Inference Output
# ==============================================================================

library(tidyverse)
library(data.table)

cat("\n=== BAYESIAN NETWORK OUTPUT DIAGNOSTIC ===\n")

# Check if output files exist
output_dir <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"

if (file.exists(file.path(output_dir, "biomech_predictions_wide.csv"))) {
  cat("\n✓ predictions_wide.csv exists\n")
  pw <- fread(file.path(output_dir, "biomech_predictions_wide.csv"))
  cat("  Rows:", nrow(pw), "\n")
  cat("  Columns:", ncol(pw), "\n")
  cat("  Column names:\n")
  print(colnames(pw))
  cat("\n  First 3 rows:\n")
  print(head(pw, 3))
} else {
  cat("\n✗ predictions_wide.csv does not exist\n")
}

if (file.exists(file.path(output_dir, "inference_confidence.csv"))) {
  cat("\n✓ inference_confidence.csv exists\n")
  conf <- fread(file.path(output_dir, "inference_confidence.csv"))
  cat("  Rows:", nrow(conf), "\n")
  cat("  Columns:", ncol(conf), "\n")
  cat("  Column names:\n")
  print(colnames(conf))
  cat("\n  First 3 rows:\n")
  print(head(conf, 3))
} else {
  cat("\n✗ inference_confidence.csv does not exist\n")
}

if (file.exists(file.path(output_dir, "biomech_predictions_long.csv"))) {
  cat("\n✓ biomech_predictions_long.csv exists\n")
  pl <- fread(file.path(output_dir, "biomech_predictions_long.csv"))
  cat("  Rows:", nrow(pl), "\n")
  cat("  Columns:", ncol(pl), "\n")
  cat("  Column names:\n")
  print(colnames(pl))
  cat("\n  First 5 rows:\n")
  print(head(pl, 5))
} else {
  cat("\n✗ biomech_predictions_long.csv does not exist\n")
}

if (file.exists(file.path(output_dir, "fitted_network.rds"))) {
  cat("\n✓ fitted_network.rds exists\n")
} else {
  cat("\n✗ fitted_network.rds does not exist\n")
}

cat("\n=== END DIAGNOSTIC ===\n")
