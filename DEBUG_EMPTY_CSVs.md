# Debugging Empty CSV Files - Action Plan

## Problem
Pipeline completes but output CSVs are empty (only headers, no data rows).

## Root Cause
Inference is returning empty lists (no probability distributions), which means `cpdist()` is not finding matching CPT rows. This happens when evidence doesn't match factor levels.

## Diagnostic Steps (Run in Order)

### Step 1: Test on Small Sample (2 minutes)
```bash
Rscript test_small_sample.R
```

This tests the complete pipeline on just 10 pitches and shows:
- ✓ Data types at each step
- ✓ How many pitches have valid evidence
- ✓ Whether inference returns non-empty results
- ✓ Structure of the results (if any)

**What to look for**:
- All evidence columns should show `class: factor`
- If any show `character` or `integer`, factor conversion isn't working
- If "Non-empty results: 0", then inference is still failing silently

### Step 2: Detailed Preprocessing Diagnostic (5 minutes)
```bash
Rscript diagnostic_preprocessing.R
```

This traces through each preprocessing step and shows:
- Column names and types after each transformation
- Whether factor conversion works
- Whether hidden biomechanics columns are created properly
- Whether any rows are filtered out

**What to look for**:
- After "normalize_milb_field_names()", stand/zone/pitch_name should exist
- After "discretize_milb_variables()", launch_speed_binned and launch_angle_binned should be factors
- After "convert_to_network_factors()", all evidence columns should be factors with proper levels
- Should see "✅ YES - Data is ready for inference" at the end

### Step 3: Check Training Data (1 minute)
If diagnostics show factor conversion working but inference still returns empty:

```r
# In R console
source("scripts/bayesian_network/bn_data_preparation.R")
discretization_scheme <- create_discretization_scheme()
training <- prepare_training_data(discretization_scheme = discretization_scheme)

# Check factor levels
levels(training$stand)       # Should be: "L" "R"
levels(training$zone)       # Should be: "1" "2" ... "13"
levels(training$pitch_name) # Should be: "Fastball", "Slider", etc.
levels(training$spray_angle) # Should be: "center" "oppo" "pull"

# Check structure
str(training[, c("stand", "zone", "pitch_name", "spray_angle")])
```

**What to look for**:
- All should be `Factor w/ X levels`
- Levels should match what you see in MiLB data after conversion

---

## Most Likely Issues (In Order)

### Issue 1: Factor Conversion Not Happening
**Symptom**: Evidence columns still show `character` or `integer` class

**Fix**: Verify `convert_to_network_factors()` is being called in `prepare_milb_for_inference()`
- Check line 214 in bn_milb_application.R
- Should see: `milb_data <- convert_to_network_factors(milb_data, training_data)`
- If not present, add it back

### Issue 2: Training Data Doesn't Have Proper Factor Levels
**Symptom**: Factors are created but with wrong levels

**Fix**: Check what levels training data actually has vs what MiLB data has
```r
# Compare pitch_name levels
training_levels <- levels(training$pitch_name)
milb_sample <- "Knuckle Ball"  # example from database

milb_sample %in% training_levels  # Should be TRUE or map to "Other"
```

### Issue 3: MiLB Data Missing Critical Columns
**Symptom**: Error during column selection or renaming

**Fix**: Check database query in `load_milb_statcast_files()` returns all required columns

### Issue 4: All Rows Filtered Out
**Symptom**: Final filtered data has 0 rows

**Fix**: Relax filtering in `prepare_milb_for_inference()` to see how many rows you actually have:
```r
# After all preprocessing steps, before filters:
nrow(milb_for_inference)  # Before filter
# Then add filters back one by one
```

---

## Quick Fixes to Try

### If all diagnostics show data types are wrong:
1. Verify `convert_to_network_factors()` is being called
2. Make sure it's being called AFTER column renaming
3. Check that training_data is being passed correctly

### If data types are correct but inference still empty:
1. Check `bn_inference_engine.R` - look for the new logging output
2. Count how many pitches have evidence vs return empty results
3. If evidence count is low, the issue is data quality

### If pipeline runs but doesn't show new logging:
1. Check you're using the latest code (verify file was saved)
2. Try running with a simple test:
   ```bash
   Rscript test_small_sample.R
   ```

---

## What the New Fixes Do

### 1. Error Checking in `convert_to_network_factors()`
Now validates that training data has proper factor columns before attempting conversion. Will show clear error if something is missing.

### 2. Logging in `infer_biomechanics_batch()`
Now tracks:
- Data type verification for all evidence columns
- Count of successful vs failed inferences
- Count of pitches with no evidence
- Progress with success rates

This helps you see exactly where results are being lost.

### 3. Better NA Handling
Now properly handles NA values in pitch_name and spray_angle instead of creating invalid factors.

---

## Action Plan

1. **Run diagnostics in order** (most help narrow down the issue quickly)
   ```bash
   Rscript test_small_sample.R
   Rscript diagnostic_preprocessing.R
   ```

2. **Read the output carefully** - look for where data types change or are wrong

3. **Report back with**:
   - Output from test_small_sample.R (data types, success count)
   - Output from diagnostic_preprocessing.R (which step fails?)
   - Any error messages

4. **Then we can pinpoint exactly what's wrong** and fix it

---

## Expected Output If Everything Works

After running test_small_sample.R, you should see:
```
Evidence column types:
  stand: factor
  zone: factor
  pitch_name: factor
  launch_speed: factor
  launch_angle: factor
  spray_angle: factor

Final data ready: X rows (after filtering)

=== Inferring Biomechanics for X Pitches ===
Data Type Verification
Evidence columns:
  stand: factor
  zone: factor
  ...

Inference Complete
Total pitches: X
  ✓ Successful: X (Y%)
  ✗ No evidence: X (Y%)
  ✗ Inference failed: X (Y%)

✅ SUCCESS: Inference returned non-empty results
```

If you see "✗ Inference failed" or "✗ No evidence" percentage is high, that's the next thing to debug.

---

## TL;DR

```bash
# Run these two commands
Rscript test_small_sample.R
Rscript diagnostic_preprocessing.R

# Look for:
# 1. Do all evidence columns show "factor" class?
# 2. Does the final summary show "✅ Data is ready for inference"?
# 3. Does test_small_sample.R show "SUCCESS: Inference returned non-empty results"?

# If YES to all three → Pipeline should work on full data
# If NO to any → Look at the output to see what's wrong
```
