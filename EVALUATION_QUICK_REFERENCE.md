# Evaluation Without CSVs: Quick Reference

## One-Line Evaluation

After running inference in your script, just add:

```r
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_evaluation.R")

# Your inference results
results <- infer_biomechanics_batch(fitted_bn, milb_data)

# Complete evaluation
evaluation <- evaluate_predictions(results, milb_data)
```

This runs 5 checks automatically:
1. **Evidence Quality** - Are observations available?
2. **Confidence Assessment** - How sure are the predictions?
3. **Entropy Analysis** - How uncertain is the network?
4. **Consistency Check** - Do similar pitches get similar predictions?
5. **Validation** - (If actual data available) How accurate?

## What You Get

### 1. Confidence Assessment
```
Confidence Distribution:
  variable    mean median  min   max  low_conf_pct
  attack_angle 0.26  0.25  0.25  0.29      100.0
  swing_path_tilt 0.25  0.25  0.25  0.29   100.0
  ...
```

**Red flags:**
- Very low mean confidence (< 0.30) = Network uncertain
- High % low-conf (> 20%) = Many unreliable predictions

### 2. Entropy Analysis
```
Entropy by Variable:
  variable    mean_entropy  median_entropy  mean_top_prob
  attack_angle    1.38         1.39          0.26
  swing_path_tilt 1.38         1.38          0.25
  ...
```

**Interpretation:**
- Entropy ~1.4 = Predictions are distributed (moderate confidence)
- Entropy ~0.3 = Predictions are peaked (high confidence)
- High entropy = Network doesn't strongly prefer any level

### 3. Consistency Check
```
By pitch type:
  pitch_type    n_pitches  n_unique_predictions  consistency
  Fastball      450        2                     0.996
  Slider        320        3                     0.991
  ...
```

**Green flags:**
- Consistency > 0.90 = Similar pitches predict similarly ✓
- Similar pitch types cluster predictions ✓

**Red flags:**
- Consistency < 0.70 = Random predictions ✗
- Wildly different predictions for same pitch type ✗

### 4. Validation (When Real Data Available)
```r
# Once you get actual biomechanics measurements:
evaluation <- evaluate_predictions(
  results, 
  milb_data,
  actual_biomechanics = real_data_df
)

# Output:
# Accuracy by Variable:
#   variable         match_rate  n_predictions
#   attack_angle        45.2            1200
#   swing_path_tilt     48.1            1200
#   ...
# Overall Accuracy: 46.8%
```

## Key Evaluation Metrics

| Metric | Good Range | Action If Low |
|--------|-----------|---------------|
| **Mean Confidence** | > 0.35 | Re-examine network structure |
| **Low-Conf %** | < 15% | May need more training data |
| **Entropy** | 0.5 - 1.5 | < 0.3 = too confident, > 1.8 = too uncertain |
| **Consistency** | > 0.85 | < 0.70 = network may have bugs |
| **Accuracy** | > 40% | Network is learning relationships |

## Common Issues & Fixes

### "All predictions have 25% confidence (uniform distribution)"
**Cause:** Network parameters not learned properly, or evidence doesn't constrain predictions
**Fix:** Check training data quality, verify network structure

### "High consistency but low confidence"
**Cause:** Network makes consistent but weak predictions
**Fix:** Add more training data, increase smoothing parameter, adjust network structure

### "Low consistency"
**Cause:** Network is overfitting or has conflicting dependencies
**Fix:** Reduce smoothing, check for circular logic in network structure

### "Very peaked predictions (>95% confidence)"
**Cause:** Training data too small or network is deterministic
**Fix:** Decrease smoothing parameter, add more varied training data

## In Your Analysis Script

```r
library(tidyverse)
library(bnlearn)

# Load network
fitted_bn <- readRDS("fitted_network.rds")
discretization_scheme <- readRDS("discretization_scheme.rds")

# Load sample
cubs_data <- dbGetQuery(conn, 
  "SELECT * FROM sc_milb WHERE pitcher.team = 'Chicago Cubs' LIMIT 1000"
)

# Prepare
cubs_prep <- prepare_milb_for_inference(cubs_data, discretization_scheme)

# Predict
results <- infer_biomechanics_batch(fitted_bn, cubs_prep)

# EVALUATE HERE
source("bn_evaluation.R")
eval_report <- evaluate_predictions(results, cubs_prep)

# Now proceed with analysis
predictions <- format_inference_results_wide(results)
cubs_analysis <- cubs_prep %>%
  bind_cols(predictions) %>%
  # ... your analysis ...
```

## When Actual Data Arrives

MiLB will eventually provide actual biomechanics measurements. Then:

```r
# Load actual measurements (when available)
actual_biomech <- read_csv("milb_biomechanics_2026.csv")

# Evaluate with truth
evaluation <- evaluate_predictions(
  results, 
  cubs_prep,
  actual_biomechanics = actual_biomech
)
```

This will show real accuracy instead of just diagnostics.
