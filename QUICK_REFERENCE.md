# QUICK REFERENCE: Post-Pipeline Evaluation

## 🚀 Immediate Action (After Pipeline Completes)

```bash
# Run this ONE command - gives you everything you need in 2 minutes
Rscript /Users/andrewsumner/Documents/Github/report-agent/evaluate_pipeline.R
```

---

## 📊 THE ONE NUMBER THAT MATTERS

Look at this line in the output:
```
Overall Confidence:
  Mean: XX.X%
```

| Mean Confidence | Status | Next Action |
|---|---|---|
| > 70% | ✅ EXCELLENT | Use predictions confidently |
| 60-70% | ✓ GOOD | Use, note limitations |
| 50-60% | ⚠ FAIR | Flag low-confidence predictions |
| < 50% | ❌ POOR | Run debug: `Rscript diagnose_output.R` |

---

## 📋 Quick Checklist

Run through in order:

- [ ] **Files exist?** Check for: predictions_wide.csv, inference_confidence.csv, audit_trail.csv
- [ ] **Files have data?** Size should be > 1MB, rows > 100K
- [ ] **Mean confidence high?** Check: `Overall Confidence: Mean: XX.X%`
- [ ] **Variables vary?** Check: Different variables have different confidence (not all 50%)
- [ ] **Predictions vary?** Check: `attack_angle_pred` isn't always "low_pos"

**If any checkbox fails** → Something needs debugging

---

## 🔍 What to Look For in Each Variable

```
Attack Angle    - Should have 50-70%+ confidence (important variable)
Swing Path Tilt - Should have 40-60%+ confidence 
Attack Direction- Should have 40-60%+ confidence
Bat Speed       - Varies widely (30-70% OK)
Intercept X/Y   - May have lower confidence (hidden from direct evidence)
```

If ONE variable has 0% confidence while others > 50%, that's the problem variable.

---

## 🚨 Red Flags & Quick Fixes

### Problem: Mean confidence is very low (<30%)
**Likely cause**: Factor type mismatch (not converted properly)  
**Quick fix**: 
```bash
# Re-run pipeline - factor conversion was just fixed
Rscript /Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/QUICKSTART.R
# Select: Option 1
```

### Problem: Only one variable has predictions (e.g., only attack_angle)
**Likely cause**: CPT initialization error for other variables  
**Quick check**: Run diagnostic
```bash
Rscript /Users/andrewsumner/Documents/Github/report-agent/diagnose_output.R
```

### Problem: All predictions are the same level (e.g., all "low_pos")
**Likely cause**: Network structure issue or wrong evidence  
**Quick fix**: Check that factor conversion happened - verify data types in audit_trail.csv

---

## 📁 Files You'll Get

| File | Size | What It Contains |
|------|------|---|
| `biomech_predictions_wide.csv` | 50-100 MB | One row per pitch, prediction for each biomechanic |
| `inference_confidence.csv` | 100-200 MB | One row per pitch-variable combo, confidence score |
| `biomech_predictions_long.csv` | 200-400 MB | Probability distribution for each prediction level |
| `audit_trail.csv` | 50-100 MB | Original data + pitch_id for joining |
| `fitted_network.rds` | 1-5 MB | Trained network (for future reuse) |

All files should exist and be readable after pipeline completes.

---

## ✅ Success Criteria

Pipeline is working correctly if:

1. ✅ All 5 output files exist and are > 1 MB
2. ✅ Mean confidence > 60%
3. ✅ Different variables have different confidence levels
4. ✅ Predictions vary (not all same value)
5. ✅ Different pitch types have different confidence

If you have 4-5 of these, you're good! Proceed to analysis.  
If you have <3 of these, run debug script.

---

## 🎯 Next Steps by Confidence Level

### Mean Confidence > 70%
```
✅ EXCELLENT RESULTS
→ Save results to backup storage
→ Create imputation reports
→ Await real biomechanics data for validation
→ Use predictions in analysis with confidence
```

### Mean Confidence 60-70%
```
✓ GOOD RESULTS
→ Note that predictions have moderate uncertainty
→ Filter to high-confidence subset for critical analyses
→ Use for exploratory analysis
→ Plan to improve in next iteration
```

### Mean Confidence 50-60%
```
⚠ MARGINAL RESULTS
→ Flag pitches with confidence < 0.4
→ Don't use for publication-quality analysis yet
→ Investigate: Which variables are weak?
→ Rerun with adjusted parameters
```

### Mean Confidence < 50%
```
❌ PROBLEMATIC RESULTS
→ Run: Rscript diagnose_output.R
→ Check: Factor conversion completed?
→ Verify: Discretization scheme correct?
→ Review: Network structure valid?
→ Debug: Rerun pipeline with logging
```

---

## 📞 If You Get Stuck

1. **Read**: [EVALUATION_GUIDE.md](EVALUATION_GUIDE.md) for detailed walkthrough
2. **Run**: `Rscript diagnose_output.R` for structured diagnostics
3. **Check**: [INFERENCE_FIX_SUMMARY.md](INFERENCE_FIX_SUMMARY.md) for factor conversion details
4. **Review**: [NEXT_STEPS.md](NEXT_STEPS.md) for decision tree

---

## 💾 Saving Results

Once you're confident in the results:

```bash
# Copy output directory to backup
cp -r data/processed/bayesian_imputation \
      /path/to/backup/bayesian_imputation_2026-08-07

# Tag the version
echo "2026-08-07: Mean confidence 68%, ready for analysis" > \
     /path/to/backup/bayesian_imputation_2026-08-07/README.txt
```

---

**TL;DR**: Run `evaluate_pipeline.R`. If mean confidence > 60%, you're done! If < 50%, debug.
