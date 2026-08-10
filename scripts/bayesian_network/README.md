# Bayesian Network for Pitch-Level Biomechanics Imputation

## Overview

This system implements a Bayesian network to infer missing biomechanics variables in Minor League Baseball (MiLB) Statcast data by leveraging:

1. **Pitch context** (stand, zone, pitch type)
2. **Observable outcomes** (launch speed, launch angle, spray angle)  
3. **Domain knowledge** relationships from swing mechanics research
4. **MLB training data** where biomechanics are fully measured

### Missing Variables (Inference Targets)

The network predicts probability distributions for these biomechanics variables that are available in MLB but not in MiLB:

- `attack_angle` - Angle of bat swing attack relative to horizontal
- `swing_path_tilt` - Tilt of swing plane (vertical inclination)
- `contact_depth` - Distance from back of plate where contact occurs
- `attack_direction` - Horizontal direction of bat swing
- `bat_speed` - Speed of bat at contact
- `intercept_x` - Horizontal position of contact (ball-batter)
- `intercept_y` - Vertical position of contact (height)

### Observable Evidence

Variables available in both MLB and MiLB used to condition inferences:

- **Pitch context**: `stand` (L/R), `zone` (1-14), `pitch_name`
- **Batted ball outcomes**: `launch_speed`, `launch_angle`, `spray_angle`

## Architecture

### Causal DAG (Domain Knowledge)

```
Pitch Context (stand, zone, pitch_name)
    ↓
Swing Mechanics (attack_angle, swing_tilt, contact_depth, attack_direction)
    ↓
Intermediate Outcomes (launch_angle, launch_speed, spray_angle)
    ↓
Observable Results (hit/out/strikeout)
```

**Key relationships encoded**:
- `zone` → `swing_tilt`, `contact_depth`, `intercept_x/y`
- `pitch_name` → `attack_angle`, `swing_tilt`
- `swing_tilt` → `attack_angle`, `launch_angle`
- `contact_depth` → `attack_angle`, `attack_direction`, `launch_angle`
- `attack_angle`, `swing_tilt` → `launch_angle`
- `attack_direction` → `spray_angle`
- `bat_speed` → `launch_speed`
- `stand` influences interpretation of directional variables

## Files

### Core Modules

| File | Purpose |
|------|---------|
| `bn_network_definition.R` | DAG structure, domain knowledge encoding, discretization scheme |
| `bn_data_preparation.R` | Load MLB Statcast, normalize field names, discretize variables |
| `bn_parameter_learning.R` | Learn conditional probability tables (CPTs) from MLB data |
| `bn_inference_engine.R` | Query network, perform backward inference on MiLB pitches |
| `bn_milb_application.R` | Load MiLB data, preprocess, run inference at scale |
| `bn_validation_framework.R` | Validate predictions when actual data arrives, guide refinement |
| `bn_orchestrate.R` | Master script coordinating all steps |

### Output Files

Generated in `/data/processed/bayesian_imputation/`:

- `biomech_predictions_long.csv` - Probability for each biomech level per pitch
- `biomech_predictions_wide.csv` - Top prediction + confidence per pitch
- `inference_confidence.csv` - Confidence assessment for each prediction
- `audit_trail.csv` - Original pitch data + all predictions (for validation)
- `fitted_network.rds` - Serialized learned network (for reuse)
- `validation_report.csv` - Accuracy metrics (when real data available)
- `network_evolution_log.csv` - Track network versions and improvements

## Workflow

### Phase 1: Initial Imputation

```r
# Load and run full pipeline
source("scripts/bayesian_network/bn_orchestrate.R")
result <- run_full_pipeline()

# Or step by step:
source("scripts/bayesian_network/bn_orchestrate.R")

network_cfg <- setup_network()
training <- prepare_training(network_cfg)
fitted <- learn_parameters(training, network_cfg)
imputed <- apply_to_milb(fitted, network_cfg)
```

**Outputs**: Probability distributions for all 7 biomechanics variables for every MiLB pitch without them.

### Phase 2: Validation & Refinement (When Real Data Arrives)

When actual MiLB biomechanics measurements become available:

```r
# Load saved objects
network_cfg <- setup_network()
fitted <- load_network("data/processed/bayesian_imputation/fitted_network.rds")

# Reload prior results
imputed <- list(
  results = list(predictions_wide = fread("data/processed/bayesian_imputation/biomech_predictions_wide.csv")),
  milb_data = fread("data/processed/bayesian_imputation/audit_trail.csv")
)

# Load actual biomechanics data from new MiLB files (optional - for future validation)
# NOTE: This file doesn't exist yet. When real biomechanics data arrives, save it as:
# data/raw/milb_statcast_with_biomechanics.csv
# Then uncomment the line below to validate predictions

# actual_biomechanics <- fread("data/raw/milb_statcast_with_biomechanics.csv")

# Validate (optional - only when actual data is available)
# validation <- validate_network(imputed, actual_biomechanics)
```

**Outputs** (when actual biomechanics data arrives): 
- Accuracy by variable and confounding factors
- Error patterns (e.g., "swing_tilt predictions wrong for LHB on inside pitches")
- Recommendations for network refinement

### Phase 3: Iterate (Future)

```r
# Implement recommended changes to bn_network_definition.R
# (e.g., add new edges, condition on new variables)

# Re-run learning and inference
network_cfg <- setup_network()
training <- prepare_training(network_cfg)
fitted <- learn_parameters(training, network_cfg)
imputed <- apply_to_milb(fitted, network_cfg)

# Validate improvements
validation <- validate_network(imputed, actual_biomechanics)

# Log this iteration
refine_network(fitted, validation$validation, "Added contact_depth→swing_tilt edge")
```

## Configuration

Edit `CONFIG` list in `bn_orchestrate.R` to adjust:

```r
CONFIG <- list(
  # Learning method
  learning_method = "bayes",      # or "mle"
  smoothing_parameter = 1,        # Laplace smoothing
  
  # Inference
  inference_method = "exact",     # or "ls" (likelihood sampling)
  confidence_threshold = 0.4,     # Flag low-confidence predictions
  
  # Data quality
  min_data_retention = 0.80       # Min % of complete cases
)
```

## Discretization Scheme

Continuous variables are discretized into 3-5 levels for efficient CPT learning:

| Variable | Levels | Example Breaks |
|----------|--------|-----------------|
| `attack_angle` | 4 | (-90°, 0°, 15°, 30°, 90°) |
| `swing_path_tilt` | 4 | (-90°, -15°, 0°, 15°, 90°) |
| `bat_speed` | 4 | (0, 50, 65, 80, 150 mph) |
| `launch_speed` | 4 | (0, 70, 85, 95, 120 mph) |
| `launch_angle` | 4 | (-90°, 10°, 20°, 35°, 90°) |
| `contact_depth` | 3 | (0, 8, 20, 40 inches) |
| `intercept_x` | 5 | (-30, -10, -2, 2, 10, 30 inches) |
| `intercept_y` | 3 | (0, 24, 42, 55 inches) |

Adjust in `create_discretization_scheme()` if finer/coarser granularity needed.

## Normalization: Stand-Relative Directions

Since "pull" vs "oppo" is opposite for LHB vs RHB, the network normalizes `spray_angle` and `attack_direction` to handedness-relative categories:

- **LHB**: spray_angle > 15° → "pull" (toward 1B)
- **RHB**: spray_angle < -15° → "pull" (toward 3B)

This ensures the same network relationships apply regardless of batter handedness.

## Inference Methods

### Exact Inference (Default)
Uses analytical computation to compute exact posterior distributions. Slower for large networks but precise.

```r
inference_results <- infer_biomechanics_batch(
  fitted_bn, milb_data, 
  method = "exact"  
)
```

### Likelihood Sampling (Optional)
Faster approximate inference using Monte Carlo sampling. Useful if exact becomes slow.

```r
inference_results <- infer_biomechanics_batch(
  fitted_bn, milb_data,
  method = "ls",  # n=10000 samples per query
)
```

## Common Tasks

### View a single pitch's inference
```r
example_evidence <- list(
  stand = "L",
  zone = "1",
  pitch_name = "Fastball",
  launch_angle = "fly",
  launch_speed = "hard",
  spray_angle = "pull"
)

result <- explore_network_inference(fitted_bn, example_evidence)
```

### Check which pitches have low-confidence predictions
```r
confidence <- assess_inference_confidence(inference_results, threshold = 0.4)
low_conf <- confidence %>% filter(confidence_flag == "LOW")
```

### Identify which relationships matter most
```r
diagnose_parameter_quality(fitted_bn, training_data)
```

### When do predictions go wrong?
```r
analyze_error_patterns(
  predictions_wide, actual_data, milb_pitch_data,
  variable = "attack_angle"  # breaks down errors by pitch type, zone, etc.
)
```

## Future Enhancements

As domain knowledge improves and real data arrives, consider:

1. **Add player-specific nodes**: Create tiers (power hitter, contact hitter) to capture swing style differences
2. **Include pitch sequencing**: Previous pitch type might influence current swing mechanics
3. **Temporal dependencies**: Early-season vs late-season mechanics
4. **Pitcher handedness**: RHP vs LHP may influence batter mechanics differently
5. **Hierarchical modeling**: Share parameters across similar players
6. **Continuous nodes**: Use Conditional Gaussian Networks for finer-grained inference
7. **Missing data handling**: Model which observations are intentionally missing vs missing at random

## Performance Notes

- **Training time**: ~30 seconds for 100k MLB pitches (depends on CPU)
- **Inference time**: ~0.1 seconds per pitch with exact method
- **Memory**: ~500MB for fitted network + cached computations
- **Scalability**: Likelihood sampling allows handling 1M+ MiLB pitches

## Troubleshooting

### Zero probability states
If you see warnings about near-zero probabilities:
```r
# Increase Laplace smoothing in bn_orchestrate.R
CONFIG$smoothing_parameter <- 5  # Higher = smoother
```

### Inference fails
Check that evidence values match discretization levels:
```r
# Evidence must use exact factor level names
# e.g., "low", "medium", "high" not "1", "2", "3"
```

### Low validation accuracy
Likely needs network refinement. Use `generate_refinement_recommendations()` to guide changes.

## References

- **bnlearn documentation**: <https://www.bnlearn.com/>
- **Domain knowledge**: SWING_LOFT_STABILITY_RESEARCH_PLAN.md
- **Data structure**: MILB_ARCHITECTURE.md
