# Post-Pipeline Evaluation Strategy

## Quick Start
Immediately after the pipeline completes, run this evaluation script:

```bash
cd /Users/andrewsumner/Documents/Github/report-agent
Rscript evaluate_pipeline.R
```

This gives you a **2-minute assessment** of whether your pipeline is working correctly.

---

## The Key Metric: Confidence Score

**This is the MOST important number to watch.**

The inference_confidence.csv file contains a `confidence` column (0.0 to 1.0) that indicates how confident the network is in each prediction.

| Confidence | Interpretation | Action |
|------------|---|---|
| > 0.70 (70%) | ✅ Excellent | Use predictions confidently |
| 0.60-0.70 | ✓ Good | Use with some caution |
| 0.50-0.60 | ⚠ Fair | Flag low-confidence predictions |
| < 0.50 | ❌ Poor | Investigate data/network issues |

---

## What the Confidence Score Means

**High Confidence (0.7-1.0)**
- Network found strong evidence for the prediction
- Multiple pieces of information support the same conclusion
- Example: LHB facing middle-in fastball → high confidence in attack angle

**Medium Confidence (0.5-0.7)**
- Network has some evidence but not conclusive
- Multiple possible predictions are plausible
- Example: Unknown pitcher type → less certain swing mechanics

**Low Confidence (0-0.5)**
- Network lacks sufficient evidence or relationships are weak
- Network is essentially guessing
- Example: Very rare pitch-handedness-zone combination

---

## Evaluation Checklist (In Priority Order)

### ✓ Step 1: File Completeness (5 minutes)
Run `evaluate_pipeline.R` and verify:
- [ ] All CSV files exist (predictions_wide, predictions_long, confidence)
- [ ] File sizes are > 1 MB (not empty)
- [ ] Row counts are reasonable (~300,000 pitches)

**If files are missing or empty**: Return to debugging. Inference probably failed silently.

### ✓ Step 2: Confidence Distribution (10 minutes)
Check the output from `evaluate_pipeline.R`:
- [ ] **Mean confidence > 60%?** → Good! Proceed to step 3
- [ ] **Mean confidence 50-60%?** → Check which variables are weak
- [ ] **Mean confidence < 50%?** → Network needs debugging (likely factor issue)

**Critical insight**: If ONE variable has 0% confidence while others have 70%+, that variable's CPT may not be properly initialized.

### ✓ Step 3: Evidence Quality (10 minutes)
From `evaluate_pipeline.R` output, check:
- [ ] Are launch_speed/angle/spray_angle mostly complete (>80%)?
- [ ] How many pitches have all 6 evidence variables?

**Expected**: Most pitches should have 4-6 of 6 evidence variables available.

**If evidence is poor**: This explains low confidence. Network can only work with available data.

### ✓ Step 4: Sanity Checks (10 minutes)

Load the wide predictions and check:

```r
library(data.table)
wide <- fread("data/processed/bayesian_imputation/biomech_predictions_wide.csv")

# Check 1: Do predictions vary or are they all the same?
table(wide$attack_angle_pred)  # Should see multiple levels, not just "low_pos"

# Check 2: Do you see expected columns?
colnames(wide)  # Should have pitch_id + multiple prediction columns

# Check 3: Spot-check a few predictions
head(wide, 10)  # Do they look reasonable?
```

**Red Flags**:
- ❌ All predictions are the same level → Network not learning
- ❌ Only pitch_id column exists → Predictions didn't save
- ❌ All NA values → Inference completely failed

### ✓ Step 5: Pattern Validation (15 minutes)

Check if results follow baseball logic:

```r
wide <- fread("data/processed/bayesian_imputation/biomech_predictions_wide.csv")
conf <- fread("data/processed/bayesian_imputation/inference_confidence.csv")
audit <- fread("data/processed/bayesian_imputation/audit_trail.csv")

# Merge for analysis
df <- audit %>% 
  left_join(wide %>% select(pitch_id, attack_angle_pred), by="pitch_id") %>%
  left_join(conf %>% filter(variable=="attack_angle") %>% select(pitch_id, confidence), 
            by="pitch_id")

# Do LHB and RHB have different predictions? (They should)
table(df$stand, df$attack_angle_pred)

# Does confidence vary by pitch type? (It should)
df %>%
  group_by(pitch_name) %>%
  summarise(mean_conf = mean(confidence, na.rm=T)) %>%
  arrange(desc(mean_conf))
```

**Good signs**:
- ✅ Different predictions for LHB vs RHB
- ✅ Confidence varies by pitch type
- ✅ Fastballs have higher confidence than rare pitches

**Bad signs**:
- ❌ Same predictions regardless of pitch type
- ❌ Constant confidence (like exactly 0.5 for everything)
- ❌ No variation in predictions at all

### ✓ Step 6: Review the Detailed Guide
If everything passes steps 1-5, read through [EVALUATION_GUIDE.md](EVALUATION_GUIDE.md) for deeper analysis.

---

## What If Mean Confidence is Low (<50%)?

### Possible Causes (in order of likelihood):

1. **Factor type mismatch still occurring** (80% probability)
   - Check: Are evidence columns still character/integer?
   - Fix: Verify `convert_to_network_factors()` is being called
   - Test: Run `evaluate_pipeline.R` debug section

2. **Discretization scheme mismatch** (10% probability)
   - Check: Do training and MiLB data use same bins?
   - Fix: Verify `create_discretization_scheme()` matches training
   - Test: Compare histograms of training vs MiLB data

3. **Network structure issue** (7% probability)
   - Check: Are all edges correctly defined in network?
   - Fix: Review `create_biomech_network()` function
   - Test: Verify network is acyclic with correct node count

4. **Insufficient training data** (3% probability)
   - Check: How many complete cases in training data?
   - Fix: Increase data quality threshold
   - Test: Use Option 2 in QUICKSTART.R and print training data info

---

## Expected Output Structure

After successful pipeline run:

```
data/processed/bayesian_imputation/
├── biomech_predictions_wide.csv    ← ~300K rows × 15+ columns
│   Columns: pitch_id, attack_angle_pred, attack_angle_conf,
│            swing_path_tilt_pred, swing_path_tilt_conf, ...
│
├── biomech_predictions_long.csv    ← ~1.8M rows × 4 columns
│   Columns: pitch_id, variable, level, probability
│
├── inference_confidence.csv        ← ~1.8M rows × 3 columns
│   Columns: pitch_id, variable, confidence
│
├── audit_trail.csv                 ← ~300K rows × 20+ columns
│   Original data + pitch_id for joining
│
└── fitted_network.rds              ← Trained network object
```

---

## Decision Tree: What to Do Next

```
Did pipeline complete successfully?
├─ YES: Continue ↓
└─ NO: Run diagnose_output.R for debug info

Mean confidence > 60%?
├─ YES: ✅ PROCEED TO ANALYSIS
│       • Results are reliable for use
│       • Save to persistent storage
│       • Await real data for validation
│
└─ NO: Continue ↓

Mean confidence 50-60%?
├─ YES: ⚠ USE WITH CAUTION
│       • Flag low-confidence pitches
│       • Filter to high-confidence only for critical analysis
│       • Note assumptions in reports
│
└─ NO: Continue ↓

Mean confidence < 50%?
└─ NO: ❌ DEBUG REQUIRED
    1. Check factor types (run eval script debug section)
    2. Verify discretization scheme
    3. Inspect training data quality
    4. Review network structure
    5. Re-run pipeline
```

---

## Key Files to Use

| File | Purpose | Run Command |
|------|---------|---|
| `evaluate_pipeline.R` | Quick 2-minute assessment | `Rscript evaluate_pipeline.R` |
| `EVALUATION_GUIDE.md` | Detailed evaluation with code | Read for deep analysis |
| `diagnose_output.R` | Debug missing/empty outputs | `Rscript diagnose_output.R` |
| `INFERENCE_FIX_SUMMARY.md` | Understand the factor fix | Read if low confidence |

---

## Summary

**Your evaluation workflow**:
1. Pipeline completes → Celebrate! 🎉
2. Run `Rscript evaluate_pipeline.R` (2 min)
3. Check if mean confidence > 60% (this is THE metric)
4. If yes → Results are good! If no → Run debug script
5. Once confident → Proceed to integrate with analysis

**Remember**: The `confidence` score is your guide. Trust it. If it's high, your predictions are good. If it's low, something needs debugging.
