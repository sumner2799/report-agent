#!/usr/bin/env Rscript
# ==============================================================================
# Detailed Preprocessing Diagnostic
# ==============================================================================
# Tests each step of the MiLB preprocessing to find where data types go wrong

library(tidyverse)
library(data.table)
library(bnlearn)

cat("\n")
cat("╔════════════════════════════════════════════════════════════════╗\n")
cat("║   DETAILED PREPROCESSING DIAGNOSTIC                           ║\n")
cat("╚════════════════════════════════════════════════════════════════╝\n")

# Load modules
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_data_preparation.R")
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_milb_application.R")

# ==============================================================================
# STEP 1: Create discretization scheme and training data
# ==============================================================================

cat("\n[SETUP] Creating network and training data...\n")
discretization_scheme <- create_discretization_scheme()
training_data <- prepare_training_data(
  discretization_scheme = discretization_scheme,
  min_data_quality_threshold = 0.80
)

cat("✓ Training data ready:", nrow(training_data), "rows\n")
cat("  Training data types (first 10 columns):\n")
training_types <- sapply(training_data[1:10], class)
for (i in seq_along(training_types)) {
  cat(sprintf("    %s: %s\n", names(training_types)[i], training_types[i]))
}

# ==============================================================================
# STEP 2: Load raw MiLB data
# ==============================================================================

cat("\n[STEP 1] Loading raw MiLB data...\n")

conn <- DBI::dbConnect(
  RMySQL::MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

# Load only first 100 rows for diagnostic
milb_raw <- DBI::dbGetQuery(conn,
  "select * from sc_milb where game_date >= '2026-01-01' and game_date <= '2026-05-31' limit 100"
)

cat("✓ Raw data loaded:", nrow(milb_raw), "rows\n")
cat("  Data types (first 10 columns):\n")
raw_types <- sapply(milb_raw[1:10], class)
for (i in seq_along(raw_types)) {
  cat(sprintf("    %s: %s\n", names(raw_types)[i], raw_types[i]))
}

# ==============================================================================
# STEP 3: Normalize field names
# ==============================================================================

cat("\n[STEP 2] After normalize_milb_field_names()...\n")

milb_norm <- normalize_milb_field_names(milb_raw)

cat("  Key columns present?\n")
key_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "hc_x", "hc_y")
for (col in key_cols) {
  present <- col %in% colnames(milb_norm)
  cat(sprintf("    %-20s: %s\n", col, if(present) "✓" else "✗"))
}

cat("  Key column types:\n")
for (col in key_cols) {
  if (col %in% colnames(milb_norm)) {
    cat(sprintf("    %-20s: %s\n", col, class(milb_norm[[col]]))
    )
  }
}

# ==============================================================================
# STEP 4: Normalize spray angle
# ==============================================================================

cat("\n[STEP 3] After normalize_milb_spray_angle()...\n")

milb_spray <- normalize_milb_spray_angle(milb_norm)

cat("  spray_angle_normalized created?\n")
if ("spray_angle_normalized" %in% colnames(milb_spray)) {
  cat(sprintf("    ✓ Present, type: %s\n", class(milb_spray$spray_angle_normalized)))
  cat(sprintf("    Unique values: %s\n", paste(unique(milb_spray$spray_angle_normalized), collapse=", ")))
} else {
  cat("    ✗ NOT FOUND\n")
}

# ==============================================================================
# STEP 5: Discretize variables
# ==============================================================================

cat("\n[STEP 4] After discretize_milb_variables()...\n")

milb_disc <- discretize_milb_variables(milb_spray, discretization_scheme)

cat("  Binned columns created?\n")
bin_cols <- c("launch_speed_binned", "launch_angle_binned")
for (col in bin_cols) {
  if (col %in% colnames(milb_disc)) {
    cat(sprintf("    %-25s: %s\n", col, class(milb_disc[[col]]))
    )
    if (class(milb_disc[[col]]) == "factor") {
      cat(sprintf("      Levels: %s\n", paste(levels(milb_disc[[col]]), collapse=", "))
      )
    }
  } else {
    cat(sprintf("    %-25s: ✗ NOT FOUND\n", col))
  }
}

# ==============================================================================
# STEP 5b: Column selection and renaming
# ==============================================================================

cat("\n[STEP 5] After select() and rename()...\n")

milb_selected <- milb_disc %>%
  select(stand, zone, pitch_name, 
         launch_speed_binned, launch_angle_binned, spray_angle_normalized,
         matchup.batter.id, matchup.batter.fullName, game_date) %>%
  rename(
    launch_speed = launch_speed_binned,
    launch_angle = launch_angle_binned,
    spray_angle = spray_angle_normalized
  )

cat("  Selected columns and types:\n")
for (col in c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")) {
  if (col %in% colnames(milb_selected)) {
    cat(sprintf("    %-20s: %s\n", col, class(milb_selected[[col]]))
    )
  } else {
    cat(sprintf("    %-20s: ✗ NOT FOUND\n", col))
  }
}

# ==============================================================================
# STEP 6: Factor conversion
# ==============================================================================

cat("\n[STEP 6] After convert_to_network_factors()...\n")

tryCatch({
  milb_factors <- convert_to_network_factors(milb_selected, training_data)
  
  cat("  ✓ Factor conversion completed\n")
  cat("  Factor columns and levels:\n")
  
  for (col in c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")) {
    if (col %in% colnames(milb_factors)) {
      actual_class <- class(milb_factors[[col]])
      cat(sprintf("    %-20s: %s", col, actual_class))
      
      if (actual_class == "factor") {
        levels_str <- paste(levels(milb_factors[[col]]), collapse=", ")
        if (nchar(levels_str) > 50) {
          levels_str <- paste0(substr(levels_str, 1, 50), "...")
        }
        cat(sprintf(" | Levels: %s\n", levels_str))
      } else {
        cat("\n")
      }
    }
  }
  
  # Check for NAs
  cat("\n  NA values in evidence columns:\n")
  for (col in c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")) {
    if (col %in% colnames(milb_factors)) {
      na_count <- sum(is.na(milb_factors[[col]]))
      pct_na <- na_count / nrow(milb_factors) * 100
      cat(sprintf("    %-20s: %d (%.1f%%)\n", col, na_count, pct_na))
    }
  }
  
}, error = function(e) {
  cat("  ✗ ERROR during factor conversion:\n")
  cat(sprintf("    %s\n", as.character(e)))
})

# ==============================================================================
# STEP 7: Hidden biomechanics columns
# ==============================================================================

cat("\n[STEP 7] Adding hidden biomechanics columns...\n")

tryCatch({
  milb_final <- milb_factors %>%
    mutate(
      attack_angle = factor(NA_character_, levels = discretization_scheme$attack_angle$levels),
      swing_path_tilt = factor(NA_character_, levels = discretization_scheme$swing_path_tilt$levels),
      attack_direction = factor(NA_character_, levels = discretization_scheme$attack_direction$levels),
      bat_speed = factor(NA_character_, levels = discretization_scheme$bat_speed$levels),
      intercept_x = factor(NA_character_, levels = discretization_scheme$intercept_x$levels),
      intercept_y = factor(NA_character_, levels = discretization_scheme$intercept_y$levels),
      outcome = factor(NA_character_, levels = c("hit", "out", "strikeout"))
    ) %>%
    filter(!is.na(stand) & !is.na(zone) & !is.na(pitch_name)) %>%
    filter(!is.na(launch_angle) | !is.na(launch_speed) | !is.na(spray_angle))
  
  cat("✓ Final data prepared\n")
  cat(sprintf("  Rows after filtering: %d\n", nrow(milb_final)))
  cat(sprintf("  Total columns: %d\n", ncol(milb_final)))
  
  cat("\n  Final data types (all columns):\n")
  final_types <- sapply(milb_final, class)
  for (i in seq_along(final_types)) {
    cat(sprintf("    %-25s: %s\n", names(final_types)[i], final_types[i]))
  }
  
}, error = function(e) {
  cat("  ✗ ERROR adding hidden biomechanics:\n")
  cat(sprintf("    %s\n", as.character(e)))
})

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n")
cat("═══════════════════════════════════════════════════════════════════\n")
cat("PREPROCESSING SUMMARY\n")
cat("═══════════════════════════════════════════════════════════════════\n\n")

cat("Evidence columns ready for inference?\n")
all_factors <- all(c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle") %in% colnames(milb_final))
all_good_type <- all(sapply(milb_final[c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")], class) == "factor")
all_no_na <- all(sapply(milb_final[c("stand", "zone", "pitch_name")], function(x) sum(is.na(x)) == 0) > 0)

if (all_factors && all_good_type && nrow(milb_final) > 0) {
  cat("✅ YES - Data is ready for inference\n\n")
  cat("Proceed to run full pipeline:\n")
  cat("  Rscript /Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/QUICKSTART.R\n\n")
} else {
  cat("❌ NO - Issues found:\n\n")
  if (!all_factors) {
    cat("  • Some columns are missing or not created properly\n")
  }
  if (!all_good_type) {
    cat("  • Some columns are not factors (should be after convert_to_network_factors)\n")
  }
  if (nrow(milb_final) == 0) {
    cat("  • All rows were filtered out (no valid evidence)\n")
  }
}

DBI::dbDisconnect(conn)

cat("\n")
