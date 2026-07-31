# Bayesian Network Scripts - Summary

## What You Have

Six R scripts that work together to build and apply a Bayesian network for imputing missing biomechanics data in Minor League Baseball:

### 1. **bn_network_definition.R** ⚙️
Defines the network structure and domain knowledge

**Key Functions**:
- `create_biomech_network()` - Creates DAG with 16 nodes and causal relationships
- `create_discretization_scheme()` - Defines how to bin continuous variables (3-5 levels each)
- `validate_network_structure()` - Checks DAG validity

**What it does**: Encodes your domain knowledge about swing mechanics into the network structure. All relationships come from your documented swing loft research.

---

### 2. **bn_data_preparation.R** 📊
Loads and prepares MLB training data

**Key Functions**:
- `load_mlb_statcast_files()` - Loads all MLB CSV files
- `normalize_spray_angle()` - Converts to handedness-relative directions (pull/oppo/center)
- `discretize_variables()` - Bins continuous variables into levels
- `prepare_training_data()` - Master function orchestrating all preprocessing

**What it does**: Takes raw MLB Statcast data and transforms it into the format needed for learning the network's conditional probabilities.

---

### 3. **bn_parameter_learning.R** 🧠
Learns network parameters from MLB data

**Key Functions**:
- `learn_network_parameters()` - Uses Bayesian or MLE method to learn CPTs
- `inspect_cpts()` - View the learned conditional probability tables
- `diagnose_parameter_quality()` - Check for problems (zero probabilities, low entropy)
- `compare_learning_methods()` - Compare Bayes vs MLE approaches

**What it does**: Analyzes MLB data to learn "if you see outcome X, how likely is biomechanics state Y?" for every variable.

---

### 4. **bn_inference_engine.R** 🔮
Performs backward inference to predict missing biomechanics

**Key Functions**:
- `infer_biomechanics_single_pitch()` - Query network for one pitch
- `infer_biomechanics_batch()` - Run inference on many pitches at once
- `format_inference_results_long/wide()` - Format output for analysis
- `assess_inference_confidence()` - Identify low-confidence predictions

**What it does**: Given observed pitch outcomes + context, works backward through the network to estimate probability distributions over hidden biomechanics variables.

---

### 5. **bn_milb_application.R** 🎯
Applies the learned network to MiLB data

**Key Functions**:
- `load_milb_statcast_files()` - Loads MiLB CSVs (different field names)
- `normalize_milb_field_names()` - Maps MiLB columns to network nodes
- `prepare_milb_for_inference()` - Preprocesses MiLB same way as training
- `apply_network_to_milb()` - Runs inference on all MiLB pitches
- `create_audit_trail()` - Saves all predictions for future validation

**What it does**: Processes all your MiLB pitch data and generates predicted biomechanics for every pitch missing them.

---

### 6. **bn_validation_framework.R** ✅
Validates predictions and guides refinement

**Key Functions**:
- `validate_predictions()` - Compare imputed values to actual biomechanics (when available)
- `analyze_error_patterns()` - Identify which pitch types/zones have accuracy problems
- `generate_refinement_recommendations()` - Suggests network improvements
- `log_network_version()` - Track which versions you've tested
- `compute_evpi()` - Shows which variables have most improvement potential

**What it does**: When real MiLB biomechanics data arrives, this validates your predictions and tells you exactly what to fix to improve the network.

---

### 7. **bn_orchestrate.R** 🎼
Master script that coordinates everything

**Key Functions**:
- `run_full_pipeline()` - Runs all 6 steps end-to-end
- Individual section functions for step-by-step execution
- Configuration list to customize behavior

**What it does**: One command to go from "raw data" → "network trained" → "MiLB pitches imputed". Or run sections individually for debugging.

---

### 8. **bn_integration_template.R** 🔗
Shows how to integrate imputed biomechanics into your existing analysis

**Key Functions**:
- `load_imputed_biomechanics()` - Load the results
- `merge_imputed_with_original()` - Add to your MiLB data
- `example_metric_calculation()` - Use imputed values in computations
- `create_imputation_qc_report()` - Track coverage and quality

**What it does**: Templates for plugging imputed biomechanics into your existing process_statcast.R pipeline and metric calculations.

---

### 9. **README.md** 📖
Complete documentation of the system

Covers:
- Network architecture and causal relationships
- File structure and outputs
- Configuration options
- Workflow for initial imputation, validation, refinement
- Discretization scheme
- Common tasks and troubleshooting

---

## Quick Start

### To impute biomechanics for MiLB data:

```r
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_orchestrate.R")
result <- run_full_pipeline()
```

This will:
1. Define network with domain knowledge
2. Load & preprocess MLB training data
3. Learn conditional probabilities
4. Apply to MiLB data
5. Save predictions with confidence scores

Output: `/data/processed/bayesian_imputation/`

### To validate when real data arrives:

```r
actual_biomechanics <- fread("your_new_milb_biomech_data.csv")
validation <- validate_network(result$imputation_results, actual_biomechanics)
```

### To improve the network:

```r
# Make changes to bn_network_definition.R
# Then re-run pipeline with improved structure
refine_network(fitted_bn, validation$validation, "Added new edge: contact_depth→swing_tilt")
```

---

## Key Concepts

### Backward Inference
You provide: `stand=L, zone=3, pitch_type=Fastball, launch_angle=fly, launch_speed=hard, spray_angle=pull`

Network returns: P(attack_angle=high | evidence above), P(swing_tilt=positive), P(bat_speed=high), etc.

### Domain Knowledge Encoding
All relationships in the DAG come from your documented research:
- Pitch location influences swing mechanics
- Swing mechanics influence launch angle
- Launch angle + spray angle = outcome
- Network learns "how much" from MLB data

### Stand Normalization
Since pull/oppo are opposite for LHB vs RHB, the network handles this automatically. Same network works for both.

### Iterative Refinement
Initial network is baseline. When actual MiLB biomechanics data arrives:
1. Compare predictions to reality
2. Identify systematic errors (e.g., "poor at predicting swing tilt for left-handed hitters")
3. Modify network structure to fix it
4. Re-learn and validate
5. Repeat until satisfied

---

## File Organization

```
scripts/bayesian_network/
├── bn_network_definition.R      [Define DAG + discretization]
├── bn_data_preparation.R        [Load & preprocess MLB data]
├── bn_parameter_learning.R      [Learn CPTs from MLB]
├── bn_inference_engine.R        [Backward inference queries]
├── bn_milb_application.R        [Apply to MiLB data]
├── bn_validation_framework.R    [Validate & guide refinement]
├── bn_orchestrate.R             [Master script]
├── bn_integration_template.R    [Integrate results into pipeline]
└── README.md                    [Full documentation]

Output:
data/processed/bayesian_imputation/
├── biomech_predictions_wide.csv      [Top predictions + confidence]
├── biomech_predictions_long.csv      [All probabilities per level]
├── inference_confidence.csv          [Confidence assessment]
├── audit_trail.csv                   [Original + predictions]
├── fitted_network.rds                [Serialized network]
├── validation_report.csv             [When real data available]
└── network_evolution_log.csv         [Track versions]
```

---

## Configuration

Edit the `CONFIG` list in `bn_orchestrate.R` to change:
- Learning method (Bayesian or MLE)
- Smoothing parameter (higher = smoother, less overfitting)
- Inference method (exact or likelihood sampling)
- Confidence threshold for flagging low-confidence predictions

---

## Next Steps

1. **Review network structure** in `bn_network_definition.R`
   - Does the DAG match your domain knowledge?
   - Are there relationships you want to add?

2. **Check discretization scheme** in `create_discretization_scheme()`
   - Are bin sizes appropriate for each variable?
   - Do you want different granularity?

3. **Run full pipeline** on your data
   - Takes 5-10 minutes depending on data size
   - Generates all imputation outputs

4. **Review confidence scores**
   - Are any variables consistently low-confidence?
   - These need network refinement

5. **Wait for real MiLB biomechanics data**
   - Validate predictions against actual values
   - Use results to improve network
   - Iterate as domain knowledge improves

---

## Support for Future Additions

The system is designed for iterative improvement:

- Add new variables? Update `create_biomech_network()` and `create_discretization_scheme()`
- Add new relationships? Modify the adjacency matrix in network definition
- Change discretization? Edit `create_discretization_scheme()`
- Adjust learning? Modify `CONFIG` in orchestrate script
- Try different inference? Change `method` parameter in inference calls

Everything is modular and well-documented for easy iteration.
