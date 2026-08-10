# Post-Pipeline Evaluation Checklist

After the Bayesian network pipeline completes, systematically evaluate these aspects:

---

## 1. Output Files - Basic Validation

### Check File Existence & Size
```r
output_dir <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"

# Verify all files exist and have content
files_to_check <- c(
  "biomech_predictions_wide.csv",
  "biomech_predictions_long.csv", 
  "inference_confidence.csv",
  "fitted_network.rds"
)

for (f in files_to_check) {
  path <- file.path(output_dir, f)
  if (file.exists(path)) {
    size <- file.size(path) / 1024 / 1024  # MB
    cat(sprintf("✓ %s: %.2f MB\n", f, size))
  } else {
    cat(sprintf("✗ %s: MISSING\n", f))
  }
}
```

### Load and Inspect Structure
```r
library(data.table)

# Load all three prediction files
wide <- fread(file.path(output_dir, "biomech_predictions_wide.csv"))
long <- fread(file.path(output_dir, "biomech_predictions_long.csv"))
conf <- fread(file.path(output_dir, "inference_confidence.csv"))

cat("Wide format:\n")
cat("  Rows:", nrow(wide), "\n")
cat("  Columns:", ncol(wide), "\n")
print(head(colnames(wide)))

cat("\nLong format:\n")
cat("  Rows:", nrow(long), "\n")
cat("  Columns:", ncol(long), "\n")
print(head(colnames(long)))

cat("\nConfidence:\n")
cat("  Rows:", nrow(conf), "\n")
cat("  Columns:", ncol(conf), "\n")
print(head(colnames(conf)))
```

**Expected Results**:
- ✅ wide: ~300K rows × 15+ columns (pitch_id + predictions for 6 biomechanics × 2-3 columns each)
- ✅ long: ~1.8M+ rows (300K pitches × 6 biomechanics × probability levels)
- ✅ conf: ~1.8M rows (one confidence score per pitch-variable combination)

---

## 2. Confidence Distribution - Critical Quality Indicator

```r
# Summary statistics
cat("=== CONFIDENCE ANALYSIS ===\n\n")

cat("Overall confidence:\n")
cat("  Mean:", sprintf("%.1f%%", mean(conf$confidence, na.rm=T) * 100), "\n")
cat("  Median:", sprintf("%.1f%%", median(conf$confidence, na.rm=T) * 100), "\n")
cat("  Min:", sprintf("%.1f%%", min(conf$confidence, na.rm=T) * 100), "\n")
cat("  Max:", sprintf("%.1f%%", max(conf$confidence, na.rm=T) * 100), "\n")

# By variable
cat("\nConfidence by variable:\n")
conf_by_var <- conf %>%
  group_by(variable) %>%
  summarise(
    n = n(),
    mean_conf = mean(confidence, na.rm=T),
    median_conf = median(confidence, na.rm=T),
    pct_high = mean(confidence >= 0.7, na.rm=T),
    pct_low = mean(confidence < 0.4, na.rm=T),
    .groups = "drop"
  ) %>%
  arrange(mean_conf)

print(conf_by_var)
```

**What to Look For**:
- ⚠️ **Mean confidence < 50%**: Evidence may be insufficient. Check if launch_speed/angle data is mostly NA
- ✅ **Mean confidence 50-70%**: Normal - some variables have better evidence than others
- ✅ **Mean confidence > 70%**: Excellent - strong relationships in network
- ⚠️ **High variance**: Some biomechanics are easier to infer than others (expected)

**Variable-Specific Patterns**:
- `launch_speed` confidence should be **highest** (observable data directly in evidence)
- `intercept_x`, `intercept_y` confidence should be **lower** (hidden, inferred from context)
- If one variable has 0% confidence, check if it failed to initialize or has no CPT entries

---

## 3. Prediction Distribution - Sanity Checks

```r
# Look at actual predictions for first 10 pitches
cat("\n=== SAMPLE PREDICTIONS (First 5 Pitches) ===\n\n")
print(head(wide, 5))

# Check for excessive NA values
cat("\nMissing predictions:\n")
for (col in colnames(wide)) {
  na_count <- sum(is.na(wide[[col]]))
  if (na_count > 0) {
    pct_na <- na_count / nrow(wide) * 100
    cat(sprintf("  %s: %d (%.1f%%)\n", col, na_count, pct_na))
  }
}

# Distribution of top predictions per variable
cat("\nTop prediction levels (wide format):\n")
if ("attack_angle_pred" %in% colnames(wide)) {
  print(table(wide$attack_angle_pred, useNA="ifany"))
}
```

**Expected Patterns**:
- ✅ Predictions should be **relatively balanced** across levels (not all "low_pos")
- ✅ Should see **variation by pitch type** (fastballs different from breaking balls)
- ⚠️ If all pitches predicted the same level: Network may not be learning relationships
- ⚠️ Many NA values: Insufficient evidence for those pitches

---

## 4. Evidence Quality - How Complete is the Data?

```r
# Check what evidence was actually available
cat("\n=== EVIDENCE QUALITY ===\n\n")

# Load original MiLB data
audit <- fread(file.path(output_dir, "audit_trail.csv"))

evidence_cols <- c("stand", "zone", "pitch_name", "launch_speed", "launch_angle", "spray_angle")

cat("Evidence completeness:\n")
for (col in evidence_cols) {
  if (col %in% colnames(audit)) {
    na_count <- sum(is.na(audit[[col]]))
    pct_complete <- (1 - na_count/nrow(audit)) * 100
    cat(sprintf("  %s: %.1f%% complete (%d NA)\n", col, pct_complete, na_count))
  }
}

# Show which pitches had full vs partial evidence
cat("\nEvidence per pitch:\n")
audit <- audit %>%
  mutate(
    evidence_count = rowSums(!is.na(.[evidence_cols]))
  )

print(table(audit$evidence_count))
cat("  (0-6 indicates number of evidence variables available per pitch)\n")
```

**Interpretation**:
- ✅ **6/6 evidence**: Full evidence, should have highest confidence
- ✅ **4-5/6 evidence**: Good, missing one observable outcome
- ⚠️ **2-3/6 evidence**: Weak, low confidence expected
- ❌ **0-1/6 evidence**: No useful evidence, pitches should be filtered

---

## 5. Pattern Analysis - Baseball Logic

```r
# Join predictions with original data to see patterns
analysis <- audit %>%
  left_join(
    wide %>% select(pitch_id, starts_with("attack_angle")),
    by = "pitch_id"
  )

# Pattern 1: By batter handedness
cat("\n=== PATTERNS BY BATTER HANDEDNESS ===\n\n")

analysis %>%
  group_by(stand) %>%
  summarise(
    n_pitches = n(),
    mean_conf = mean(confidence, na.rm=T),
    .groups = "drop"
  ) %>%
  print()

# Pattern 2: By pitch type (top 5 pitch types)
cat("\nTop pitch types in data:\n")
pitch_counts <- analysis %>%
  group_by(pitch_name) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(desc(n)) %>%
  head(10)
print(pitch_counts)

# Pattern 3: By zone
cat("\nConfidence by zone:\n")
analysis %>%
  group_by(zone) %>%
  summarise(
    n_pitches = n(),
    mean_conf = mean(confidence, na.rm=T),
    .groups = "drop"
  ) %>%
  arrange(zone) %>%
  print()
```

**What to Look For**:
- ✅ **Consistent confidence across groups**: Network generalizes well
- ⚠️ **RHB much lower confidence than LHB**: Network may need more RHB training data
- ⚠️ **Fastballs high confidence, breaking balls low**: May indicate network structure issue
- ✅ **Confidence varies by zone**: Expected - some zones have more discriminative information

---

## 6. Biological Plausibility - Does It Make Baseball Sense?

```r
# Example: Attack angle should correlate with spray angle for similar pitch types
cat("\n=== BIOLOGICAL PLAUSIBILITY ===\n\n")

# Check 1: Launch angle should be reasonable (typically 0-50 degrees)
cat("Launch angle predictions:\n")
if ("launch_angle_pred" %in% colnames(wide)) {
  launch_angle_pred <- wide$launch_angle_pred
  # Extract numeric value if in bin format
  print(table(launch_angle_pred))
}

# Check 2: Spray angle should vary by handedness
cat("\nSpray angle by handedness:\n")
print(table(analysis$stand, analysis$spray_angle))

# Check 3: Bat speed should correlate with result
cat("\nBat speed distribution:\n")
if ("bat_speed_pred" %in% colnames(wide)) {
  print(table(wide$bat_speed_pred, useNA="ifany"))
}
```

**Red Flags**:
- ❌ Attack angles all "mid" (not discriminating)
- ❌ Spray angles independent of handedness (should correlate strongly)
- ❌ High bat speeds on weak contact (doesn't make sense)
- ❌ No relationship between pitch type and predictions

---

## 7. Comparison Across Network Versions

If you re-train the network with different parameters, compare:

```r
# Compare two runs
old <- fread("previous_run/biomech_predictions_wide.csv")
new <- fread("latest_run/biomech_predictions_wide.csv")

# How many predictions changed?
comparison <- old %>%
  left_join(new, by="pitch_id", suffix=c("_old", "_new"))

changes <- sum(comparison$attack_angle_pred_old != comparison$attack_angle_pred_new, na.rm=T)
cat(sprintf("Predictions changed: %d/%d (%.1f%%)\n", 
            changes, nrow(comparison), changes/nrow(comparison)*100))

# Did confidence improve?
old_conf <- fread("previous_run/inference_confidence.csv")
new_conf <- fread("latest_run/inference_confidence.csv")

cat("\nConfidence improvement:\n")
cat("  Old mean:", sprintf("%.1f%%\n", mean(old_conf$confidence, na.rm=T)*100))
cat("  New mean:", sprintf("%.1f%%\n", mean(new_conf$confidence, na.rm=T)*100))
```

---

## 8. Checklist - What to Report

After evaluation, you should have answers to:

- [ ] **File Quality**: Are all output files populated (not empty)?
- [ ] **Coverage**: What % of pitches have valid predictions?
- [ ] **Confidence**: What's the mean confidence? Which variables are strongest?
- [ ] **Evidence**: What % of pitches had complete/partial evidence?
- [ ] **Patterns**: Does confidence vary logically by pitch type, zone, handedness?
- [ ] **Plausibility**: Do predictions follow baseball logic?
- [ ] **Issues**: Which biomechanics have lowest confidence? Why?
- [ ] **Recommendations**: What should be improved in next iteration?

---

## 9. Next Steps Based on Findings

### If Confidence is High (>70% mean)
✅ Network is working well!
- Proceed to save results
- Validate against real data when available
- Use for analysis and reports

### If Confidence is Medium (50-70% mean)
⚠️ Results usable with caution
- Identify which variables need improvement
- Check if training data is sufficient
- Consider network structure refinements

### If Confidence is Low (<50% mean)
❌ Network needs debugging
- Check if factor conversion is working (rerun diagnostic)
- Verify discretization scheme matches training and MiLB data
- Examine inference results structure (use `str()` on inference_results)
- Increase training data quality threshold
- Reconsider network structure (missing edges?)

---

## 10. Quick Evaluation Script

```r
# Run this after pipeline completes
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")

output_dir <- "/Users/andrewsumner/Documents/Github/report-agent/data/processed/bayesian_imputation"

# Load files
wide <- fread(file.path(output_dir, "biomech_predictions_wide.csv"))
conf <- fread(file.path(output_dir, "inference_confidence.csv"))
audit <- fread(file.path(output_dir, "audit_trail.csv"))

cat("\n=== QUICK EVALUATION ===\n\n")
cat("Total pitches processed:", nrow(wide), "\n")
cat("Mean confidence:", sprintf("%.1f%%\n", mean(conf$confidence, na.rm=T)*100))
cat("Median confidence:", sprintf("%.1f%%\n", median(conf$confidence, na.rm=T)*100))

cat("\nConfidence by variable:\n")
print(conf %>%
  group_by(variable) %>%
  summarise(mean_conf = mean(confidence, na.rm=T), .groups="drop") %>%
  arrange(mean_conf))

cat("\nColumns in predictions_wide:\n")
print(colnames(wide))

cat("\nFirst pitch predictions:\n")
print(wide[1,])

cat("\n=== END EVALUATION ===\n")
```

---

## Priority Order for Evaluation

1. **First**: Check file sizes and basic structure (Section 1)
2. **Second**: Examine confidence distribution (Section 2) - this is THE most important metric
3. **Third**: Look for data quality issues (Section 4)
4. **Fourth**: Check for obvious errors in predictions (Section 3)
5. **Fifth**: Validate biological plausibility (Section 6)
6. **Last**: Deep-dive into patterns and comparisons (Sections 5-7)

If mean confidence > 60%, proceed with caution to analysis. If < 50%, return to debugging.
