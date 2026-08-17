# Ad-Hoc Analysis Workflow

## Your New Pipeline (Recommended)

Instead of pre-computing predictions for all 326K pitches, use this smarter workflow:

### Step 1: Train Network (One Time)
```bash
Rscript /Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/QUICKSTART.R
```

This creates:
- `fitted_network.rds` - Trained Bayesian network (~5 MB)
- `training_data.rds` - Factor levels for encoding (~50 MB)
- `discretization_scheme.rds` - Binning rules (~1 MB)

**Total: ~60 MB** (vs. ~1 GB for all predictions)

### Step 2: Load Network (Anytime, Seconds)
```r
fitted_bn <- readRDS("fitted_network.rds")
discretization_scheme <- readRDS("discretization_scheme.rds")
training_data <- readRDS("training_data.rds")
```

### Step 3: Load Smaller Sample
```r
# Query specific subset (one team, date range, etc.)
sample_data <- dbGetQuery(conn,
  "SELECT * FROM sc_milb WHERE game_date >= '2026-04-01' LIMIT 1000"
)
```

### Step 4: Preprocess & Predict
```r
milb_prepared <- prepare_milb_for_inference(sample_data)
results <- infer_biomechanics_batch(fitted_bn, milb_prepared)
predictions <- format_inference_results_wide(results)
```

## Why This is Better

| Aspect | Pre-Compute All | Ad-Hoc (Recommended) |
|--------|-----------------|----------------------|
| **Storage** | ~1 GB (all predictions) | ~60 MB (network) |
| **Runtime** | 8-12 hours (full run) | 5 min train + 2 sec per 1000 pitches |
| **Flexibility** | Fixed dataset | Query any subset |
| **Analysis** | Limited to pre-computed | Unlimited |
| **Updates** | Recompute everything | Quick retrain |

## Example: Chicago Cubs Pitchers Analysis

```r
# Load network (cached)
fitted_bn <- readRDS("fitted_network.rds")
discretization_scheme <- readRDS("discretization_scheme.rds")

# Get Cubs pitchers
cubs_pitchers <- dbGetQuery(conn,
  "SELECT * FROM sc_milb 
   WHERE pitcher.team = 'Chicago Cubs'
   AND game_date BETWEEN '2026-04-01' AND '2026-08-31'"
)

# Preprocess
cubs_prep <- prepare_milb_for_inference(cubs_pitchers, discretization_scheme)

# Predict (fast!)
results <- infer_biomechanics_batch(fitted_bn, cubs_prep)
predictions <- format_inference_results_wide(results)

# Analysis
cubs_pitchers %>%
  bind_cols(predictions) %>%
  group_by(pitcher.name) %>%
  summarise(
    avg_attack_angle = mean(attack_angle_confidence),
    avg_bat_speed = mean(bat_speed_confidence),
    n_pitches = n()
  ) %>%
  arrange(desc(avg_bat_speed))
```

## .RDS vs .XGB

- **.rds** - R's native serialization format
  - Stores any R object (fitted networks, data frames, lists)
  - Smaller file sizes than many alternatives
  - Fast to load/save
  - ✓ What we use for Bayesian networks

- **.xgb** - XGBoost model format
  - Specific to XGBoost package
  - Doesn't work for bnlearn networks
  - Would need different inference approach

## Disabling CSV Export

The pipeline now skips CSV export by default. To enable:

```r
# In orchestrate.R or your script:
apply_network_to_milb(
  fitted_bn, 
  milb_data,
  export_predictions = TRUE  # Only if you need CSVs
)
```

This lets you skip the slow formatting step entirely for ad-hoc analysis.

## Next Steps

1. ✓ Network trained and saved
2. Load network + small sample
3. Run analysis
4. Repeat with different subsets as needed

See `WORKFLOW_ADHOC_ANALYSIS.R` for complete working example.
