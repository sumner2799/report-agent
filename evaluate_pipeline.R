#!/usr/bin/env Rscript
# ==============================================================================
# Quick Pipeline Evaluation Script
# ==============================================================================
# Run this immediately after the pipeline completes to assess results

library(tidyverse)
library(data.table)

output_dir <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║     BAYESIAN NETWORK PIPELINE - EVALUATION SUMMARY            ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# ==============================================================================
# 1. FILE CHECK
# ==============================================================================

cat("\n[1/6] OUTPUT FILES\n")
cat("─────────────────────────────────────────────────────────────────\n")

files_to_check <- list(
  "biomech_predictions_wide.csv" = "Wide format predictions",
  "biomech_predictions_long.csv" = "Long format predictions",
  "inference_confidence.csv" = "Confidence scores",
  "fitted_network.rds" = "Trained network",
  "audit_trail.csv" = "Audit trail"
)

file_status <- list()
for (fname in names(files_to_check)) {
  path <- file.path(output_dir, fname)
  if (file.exists(path)) {
    size_mb <- file.size(path) / 1024 / 1024
    rows <- 0
    if (grepl("\\.csv$", fname)) {
      tryCatch({
        rows <- nrow(fread(path, select=1))
      }, error = function(e) { rows <<- 0 })
    }
    status <- sprintf("✓ %s (%.2f MB, %s rows)", fname, size_mb, 
                      if(rows > 0) format(rows, big.mark=",") else "?")
    cat(sprintf("%s\n", status))
    file_status[[fname]] <- TRUE
  } else {
    cat(sprintf("✗ %s - MISSING\n", fname))
    file_status[[fname]] <- FALSE
  }
}

# ==============================================================================
# 2. CONFIDENCE ANALYSIS
# ==============================================================================

cat("\n[2/6] CONFIDENCE ANALYSIS (KEY METRIC)\n")
cat("─────────────────────────────────────────────────────────────────\n")

if (file_status$"inference_confidence.csv") {
  conf <- fread(file.path(output_dir, "inference_confidence.csv"))
  
  if (nrow(conf) > 0) {
    overall_mean <- mean(conf$confidence, na.rm=T)
    overall_median <- median(conf$confidence, na.rm=T)
    
    cat(sprintf("Overall Confidence:\n"))
    cat(sprintf("  Mean:   %.1f%%\n", overall_mean * 100))
    cat(sprintf("  Median: %.1f%%\n", overall_median * 100))
    cat(sprintf("  Min:    %.1f%%\n", min(conf$confidence, na.rm=T) * 100))
    cat(sprintf("  Max:    %.1f%%\n", max(conf$confidence, na.rm=T) * 100))
    
    # Quality interpretation
    cat("\n  Quality Assessment: ")
    if (overall_mean > 0.70) {
      cat("✅ EXCELLENT (>70%)\n")
    } else if (overall_mean > 0.60) {
      cat("✓ GOOD (60-70%)\n")
    } else if (overall_mean > 0.50) {
      cat("⚠ FAIR (50-60%) - Usable with caution\n")
    } else {
      cat("❌ POOR (<50%) - May need debugging\n")
    }
    
    # By variable
    cat("\nConfidence by Variable:\n")
    conf_by_var <- conf %>%
      group_by(variable) %>%
      summarise(
        mean_conf = mean(confidence, na.rm=T),
        median_conf = median(confidence, na.rm=T),
        pct_high = mean(confidence >= 0.7, na.rm=T) * 100,
        .groups = "drop"
      ) %>%
      arrange(mean_conf)
    
    for (i in seq_len(nrow(conf_by_var))) {
      row <- conf_by_var[i,]
      icon <- if (row$mean_conf > 0.7) "✅" else if (row$mean_conf > 0.5) "⚠" else "❌"
      cat(sprintf("  %s %-20s Mean: %.0f%% | High: %.0f%%\n",
                  icon, row$variable, row$mean_conf * 100, row$pct_high))
    }
  } else {
    cat("  ✗ No confidence data (empty file)\n")
  }
} else {
  cat("  ✗ File not found\n")
}

# ==============================================================================
# 3. PREDICTION COVERAGE
# ==============================================================================

cat("\n[3/6] PREDICTION COVERAGE\n")
cat("─────────────────────────────────────────────────────────────────\n")

if (file_status$"biomech_predictions_wide.csv") {
  wide <- fread(file.path(output_dir, "biomech_predictions_wide.csv"))
  
  cat(sprintf("Total pitches processed: %s\n", format(nrow(wide), big.mark=",")))
  
  # Count non-NA predictions
  pred_cols <- grep("_pred$", colnames(wide), value=TRUE)
  if (length(pred_cols) > 0) {
    na_counts <- sapply(wide[, ..pred_cols], function(x) sum(is.na(x)))
    coverage <- (1 - na_counts / nrow(wide)) * 100
    
    cat(sprintf("\nPredictions by variable:\n")
    for (col in names(coverage)) {
      var_name <- sub("_pred$", "", col)
      cat(sprintf("  %-20s: %.1f%% complete\n", var_name, coverage[col]))
    }
  } else {
    cat("  ⚠ No prediction columns found (only pitch_id?)\n")
  }
  
  cat("\nSample Predictions (First Pitch):\n")
  if (nrow(wide) > 0) {
    print(wide[1, 1:min(5, ncol(wide))])
  }
} else {
  cat("  ✗ File not found\n")
}

# ==============================================================================
# 4. EVIDENCE QUALITY
# ==============================================================================

cat("\n[4/6] EVIDENCE QUALITY\n")
cat("─────────────────────────────────────────────────────────────────\n")

if (file_status$"audit_trail.csv") {
  audit <- fread(file.path(output_dir, "audit_trail.csv"))
  
  evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")
  evidence_cols <- evidence_cols[evidence_cols %in% colnames(audit)]
  
  cat("Evidence Completeness:\n")
  for (col in evidence_cols) {
    na_count <- sum(is.na(audit[[col]]))
    pct_complete <- (1 - na_count/nrow(audit)) * 100
    icon <- if (pct_complete > 95) "✅" else if (pct_complete > 80) "⚠" else "❌"
    cat(sprintf("  %s %-15s: %.1f%% complete\n", icon, col, pct_complete))
  }
  
  # Evidence per pitch
  audit$evidence_count <- rowSums(!is.na(audit[, ..evidence_cols]))
  cat("\nEvidence Distribution:\n")
  evidence_dist <- table(audit$evidence_count)
  for (i in names(evidence_dist)) {
    pct <- evidence_dist[i] / nrow(audit) * 100
    cat(sprintf("  %s variables: %d pitches (%.1f%%)\n", i, evidence_dist[i], pct))
  }
} else {
  cat("  ✗ File not found\n")
}

# ==============================================================================
# 5. PATTERN CHECK
# ==============================================================================

cat("\n[5/6] PATTERN ANALYSIS\n")
cat("─────────────────────────────────────────────────────────────────\n")

if (file_status$"biomech_predictions_wide.csv" && file_status$"audit_trail.csv") {
  wide <- fread(file.path(output_dir, "biomech_predictions_wide.csv"))
  audit <- fread(file.path(output_dir, "audit_trail.csv"))
  
  # Join and check patterns
  if ("pitch_id" %in% colnames(wide) && "pitch_id" %in% colnames(audit)) {
    data <- audit %>%
      left_join(wide %>% select(pitch_id), by="pitch_id")
    
    # By handedness
    if ("stand" %in% colnames(data)) {
      cat("By Batter Handedness:\n")
      hs_dist <- table(data$stand)
      for (hand in names(hs_dist)) {
        cat(sprintf("  %s: %s pitches\n", hand, format(hs_dist[hand], big.mark=",")))
      }
    }
    
    # Top pitch types
    if ("pitch_name" %in% colnames(data)) {
      cat("\nTop 5 Pitch Types:\n")
      pitch_dist <- data %>%
        group_by(pitch_name) %>%
        summarise(n = n(), .groups="drop") %>%
        arrange(desc(n)) %>%
        head(5)
      
      for (i in seq_len(nrow(pitch_dist))) {
        row <- pitch_dist[i,]
        cat(sprintf("  %-20s: %s\n", row$pitch_name, format(row$n, big.mark=",")))
      }
    }
  }
} else {
  cat("  ✗ Cannot analyze patterns (missing files)\n")
}

# ==============================================================================
# 6. NEXT STEPS
# ==============================================================================

cat("\n[6/6] RECOMMENDED NEXT STEPS\n")
cat("─────────────────────────────────────────────────────────────────\n")

if (file_status$"inference_confidence.csv") {
  conf <- fread(file.path(output_dir, "inference_confidence.csv"))
  if (nrow(conf) > 0) {
    overall_mean <- mean(conf$confidence, na.rm=T)
    
    if (overall_mean > 0.70) {
      cat("\n✅ RESULTS ARE EXCELLENT\n")
      cat("   • Confidence > 70% - predictions are reliable\n")
      cat("   • Proceed to: Integrate with analysis pipeline\n")
      cat("   • Save results and await real biomechanics data for validation\n")
    } else if (overall_mean > 0.60) {
      cat("\n✓ RESULTS ARE GOOD\n")
      cat("   • Confidence 60-70% - predictions usable with caution\n")
      cat("   • Consider: Which variables have low confidence?\n")
      cat("   • Next: Examine discretization and network structure\n")
    } else if (overall_mean > 0.50) {
      cat("\n⚠ RESULTS ARE FAIR\n")
      cat("   • Confidence 50-60% - marginal predictions\n")
      cat("   • Check: Evidence completeness and data quality\n")
      cat("   • Next: Rerun diagnostic and consider network adjustments\n")
    } else {
      cat("\n❌ RESULTS NEED IMPROVEMENT\n")
      cat("   • Confidence < 50% - predictions unreliable\n")
      cat("   • Debug: Run diagnose_output.R for detailed analysis\n")
      cat("   • Check: Factor conversion, discretization scheme\n")
      cat("   • Next: Verify preprocessing pipeline is working\n")
    }
  }
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════════\n")
cat("For detailed evaluation, see: EVALUATION_GUIDE.md\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")
