# Execution Guide - Step-by-Step

This file shows exactly what happens when you run the Bayesian network pipeline.

---

## 🚀 Quick Start (3 Steps)

### Step 1: Copy & Paste This
```r
source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_orchestrate.R")
```

### Step 2: Run This
```r
results <- run_full_pipeline()
```

### Step 3: Wait
Takes 5-15 minutes. Check console for progress.

---

## 📍 What Happens Under the Hood

When you call `run_full_pipeline()`, here's the exact sequence:

### Phase 1: Load Modules (< 1 second)
```
bn_network_definition.R loaded
  └─ create_biomech_network()
  └─ create_discretization_scheme()
  └─ validate_network_structure()

bn_data_preparation.R loaded
  └─ load_mlb_statcast_files()
  └─ normalize_spray_angle()
  └─ discretize_variables()
  └─ prepare_training_data()

bn_parameter_learning.R loaded
  └─ learn_network_parameters()
  └─ inspect_cpts()
  └─ diagnose_parameter_quality()
  └─ export_network()

bn_inference_engine.R loaded
  └─ infer_biomechanics_single_pitch()
  └─ infer_biomechanics_batch()
  └─ format_inference_results_long/wide()
  └─ assess_inference_confidence()

bn_milb_application.R loaded
  └─ prepare_milb_for_inference()
  └─ apply_network_to_milb()
  └─ create_audit_trail()

bn_validation_framework.R loaded
  └─ validate_predictions()
  └─ analyze_error_patterns()
  └─ generate_refinement_recommendations()
```

### Phase 2: Define Network (< 1 second)
```
setup_network()
  ├─ create_biomech_network()
  │   └─ 16 nodes, ~15 causal edges
  │   └─ All domain knowledge encoded
  ├─ create_discretization_scheme()
  │   └─ 7 biomechanics variables binned to 3-5 levels
  │   └─ Observable variables prepared
  └─ validate_network_structure()
      └─ Checks DAG acyclicity
      └─ Prints adjacency matrix
```

### Phase 3: Prepare Training Data (30-60 seconds)
```
prepare_training()
  ├─ load_mlb_statcast_files()
  │   ├─ Scans /data/raw for MLB CSV files
  │   ├─ Loads all files with fread()
  │   └─ Prints total rows: "Total rows loaded: N"
  │
  ├─ [Within prepare_training_data()]:
  │   ├─ normalize_spray_angle()
  │   │   └─ Converts plate coordinates to pull/oppo/center (handedness-relative)
  │   ├─ compute_contact_depth()
  │   │   └─ Computes depth from back of plate
  │   ├─ discretize_variables()
  │   │   └─ Bins attack_angle, launch_speed, launch_angle, etc.
  │   └─ select & rename columns for network
  │
  └─ Output: training_data
      ├─ Rows: All complete cases (after dropping NAs)
      ├─ Cols: 10 (pitch context + biomechanics + outcomes)
      └─ All factors (for bnlearn compatibility)
```

### Phase 4: Learn Network Parameters (60-180 seconds)
```
learn_parameters()
  ├─ learn_network_parameters()
  │   ├─ Uses Bayesian method (bnlearn::bn.fit)
  │   ├─ Laplace smoothing (ISS = 1)
  │   └─ Learns CPT for each node from training data
  │
  ├─ inspect_cpts()
  │   └─ Prints sample CPT for launch_angle node
  │
  ├─ diagnose_parameter_quality()
  │   ├─ Checks for zero probabilities
  │   ├─ Computes entropy per node
  │   └─ Prints warnings if issues found
  │
  └─ export_network()
      └─ Saves fitted_bn to fitted_network.rds
```

### Phase 5: Apply to MiLB Data (120-300 seconds)
```
apply_to_milb()
  ├─ prepare_milb_for_inference()
  │   ├─ load_milb_statcast_files()
  │   │   └─ Scans /data/raw for MiLB files
  │   ├─ normalize_milb_field_names()
  │   │   └─ Maps pitchData.zone → zone, etc.
  │   ├─ normalize_milb_spray_angle()
  │   │   └─ Handedness-relative normalization
  │   ├─ discretize_milb_variables()
  │   │   └─ Uses same bins as training data
  │   └─ Returns MiLB data ready for inference
  │
  └─ apply_network_to_milb()
      ├─ infer_biomechanics_batch()
      │   ├─ For each MiLB pitch:
      │   │   ├─ Extracts evidence (stand, zone, outcomes)
      │   │   ├─ infer_biomechanics_single_pitch()
      │   │   │   ├─ For each query node (7 biomechanics):
      │   │   │   │   └─ cpdist() → backward inference
      │   │   │   └─ Returns posterior distributions
      │   │   └─ Stores results in list
      │   └─ Progress printed every 100 pitches
      │
      ├─ format_inference_results_long()
      │   └─ One row per pitch-variable (probability per level)
      │
      ├─ format_inference_results_wide()
      │   └─ One row per pitch (top prediction + confidence)
      │
      ├─ assess_inference_confidence()
      │   └─ Computes confidence statistics
      │
      └─ Save outputs to /data/processed/bayesian_imputation/
          ├─ biomech_predictions_long.csv (prob table)
          ├─ biomech_predictions_wide.csv (top preds)
          ├─ inference_confidence.csv (confidence)
          └─ audit_trail.csv (original + preds)
```

### Phase 6: Validation (Skipped - Requires Real Data)
```
validate_network() 
  └─ Skipped during initial run
  └─ When actual MiLB biomechanics data arrives:
      ├─ Load actual values
      ├─ Call: validate_network(imputation_results, actual_biomechanics)
      ├─ Compares predictions vs actual
      ├─ Breaks down accuracy by pitch type, zone, etc.
      └─ Outputs validation_report.csv
```

---

## 📊 Expected Console Output

When you run `run_full_pipeline()`, you'll see approximately:

```
╔═══════════════════════════════════════════════════════════════╗
║  Bayesian Network for Pitch-Level Biomechanics Imputation    ║
║  Baseball Minor League Data                                   ║
╚═══════════════════════════════════════════════════════════════╝

=== Sourcing Bayesian Network Modules ===
✓ Network definition loaded
✓ Data preparation loaded
✓ Parameter learning loaded
✓ Inference engine loaded
✓ MiLB application loaded
✓ Validation framework loaded

=== SECTION 1: Network Definition ===

=== Network Validation ===
Nodes: 16
Arcs: 15
Acyclic: TRUE

[Adjacency matrix printed]

✓ DAG created with 16 nodes

✓ Discretization scheme defined

=== SECTION 2: Data Preparation (MLB Training) ===

Loading 13 MLB Statcast files...
  Reading: statcast_mlb_week_1.csv
  Reading: statcast_mlb_week_2.csv
  ... (remaining files)
Total rows loaded: 150000

=== Step 1: Loading MLB Statcast Data ===

=== Step 2: Normalizing Spray Angle ===

=== Step 3: Computing Contact Depth ===

=== Step 4: Discretizing Variables ===

=== Step 5: Selecting Network Columns ===

=== Step 6: Handling Missing Data ===
Initial rows: 150000
Complete cases: 82000
Data retention: 54.7%

=== Step 7: Converting to Factors ===

=== Training Data Summary ===
Dimensions: 82000 rows × 10 columns

=== SECTION 3: Parameter Learning (from MLB) ===

Method: bayes
Training samples: 82000

Network fitted successfully.

--- Sample CPTs ---

=== CPT for Node: launch_angle ===
[CPT table printed]

=== Parameter Quality Diagnostics ===

Check 1: Zero Probability States
Near-zero probability states found: 45

Check 2: Node Entropy (Information Content)
  [Entropy values by node]

Check 3: Conditional Independence
  [Parent-child relationships]

Saving fitted network to: /data/processed/bayesian_imputation/fitted_network.rds

✓ Network exported successfully

=== SECTION 4: Apply Network to MiLB Data ===

=== Preparing MiLB Data for Inference ===

=== Step 1: Loading MiLB Statcast Data ===

Loading 26 MiLB Statcast files...
  Reading: statcast_aaa_week_1.csv
  Reading: statcast_aa_week_1.csv
  ... (remaining files)
Total rows loaded: 35000

=== Step 2: Normalizing field names ===

=== Step 3: Normalizing Spray Angle ===

=== Step 4: Discretizing Variables ===

=== Step 5: Selecting Network Columns ===

✓ Prepared 28500 pitches for inference

=== Applying Network to MiLB Data ===

=== Inferring Biomechanics for 28500 Pitches ===
  Progress: 100/28500 pitches
  Progress: 200/28500 pitches
  ... (continuing)
  Progress: 28500/28500 pitches

✓ Completed inference for 28500 pitches

Formatting results...

Assessing inference confidence...

=== Inference Confidence Assessment ===

Confidence Distribution:
  Mean confidence: 68.4%
  Median confidence: 72.1%
  Min confidence: 12.5%

Low confidence predictions (< 40%): 2834

Examples of low-confidence inferences:
  [Sample table]

Saving results...

✓ Results saved to: /data/processed/bayesian_imputation/
  - biomech_predictions_long.csv (probabilities for each level)
  - biomech_predictions_wide.csv (top predictions + confidence)
  - inference_confidence.csv (confidence assessment)

✓ Audit trail saved to: /data/processed/bayesian_imputation/audit_trail.csv
  Use this to validate predictions when actual biomechanics data becomes available

╔═══════════════════════════════════════════════════════════════╗
║  Pipeline Complete!                                          ║
║  Biomechanics imputed for MiLB data                          ║
║  Results saved to: /data/processed/bayesian_imputation/      ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## 🎯 Output Files Generated

After completion, you'll have:

```
/data/processed/bayesian_imputation/
├── biomech_predictions_wide.csv      [28500 rows × 15 cols]
│   └─ pitch_id, attack_angle_predicted, attack_angle_confidence, ...
│
├── biomech_predictions_long.csv      [199500 rows × 4 cols]
│   └─ pitch_id, variable, level, probability
│
├── inference_confidence.csv          [199500 rows × 4 cols]
│   └─ pitch_id, variable, top_prediction, confidence
│
├── audit_trail.csv                   [28500 rows × 30+ cols]
│   └─ All original data + all predictions + sources
│
└── fitted_network.rds                [~5MB]
    └─ Serialized learned network (for reuse)
```

---

## 🔄 After Initial Run

### To use the same network again:
```r
# Skip learning, go straight to inference
source("bn_orchestrate.R")

network_cfg <- setup_network()
fitted_bn <- load_network("data/processed/bayesian_imputation/fitted_network.rds")

milb_data <- prepare_milb_for_inference(discretization_scheme = network_cfg$discretization_scheme)
imputed <- apply_network_to_milb(fitted_bn, milb_data)
```

### To validate when real data arrives:
```r
actual_biomechanics <- fread("new_milb_biomech_data.csv")

validation <- validate_network(
  imputed$results,
  actual_biomechanics
)

# See recommendations
generate_refinement_recommendations(validation$validation)
```

### To improve the network:
```r
# Edit bn_network_definition.R to add/modify relationships
# Then re-run:
network_cfg <- setup_network()  # New structure
training <- prepare_training(network_cfg)
fitted <- learn_parameters(training, network_cfg)  # Learn new CPTs
imputed <- apply_network_to_milb(fitted, network_cfg)  # New predictions
```

---

## ⏱️ Time Estimates

| Phase | Time | Notes |
|-------|------|-------|
| Load modules | 1 sec | Fast |
| Define network | 1 sec | Fast |
| Prepare training | 30-60 sec | Read 100K+ pitches |
| Learn parameters | 60-180 sec | Depends on CPU |
| Apply to MiLB | 120-300 sec | Inference on 25K+ pitches |
| **Total** | **5-15 min** | Depends on data size |

---

## 🐛 Debugging

If something goes wrong, try these steps:

### Check 1: Are all modules loaded?
```r
# This should print "✓" messages
source("bn_orchestrate.R")
```

### Check 2: Do your data files exist?
```r
# Check MLB files
list.files("/Users/andrewsumner/Documents/Github/report-agent/data/raw/", 
           pattern = ".*MLB.*\\.csv$")

# Check MiLB files
list.files("/Users/andrewsumner/Documents/Github/report-agent/data/raw/", 
           pattern = ".*MiLB.*\\.csv$|.*AAA.*\\.csv$")
```

### Check 3: Run step by step
```r
source("QUICKSTART.R")
# Then run Option 2 (step by step) to see where it fails
```

### Check 4: See what's in results
```r
# After run_full_pipeline() completes
results <- run_full_pipeline()

# Explore results
str(results)
head(results$imputation_results$predictions_wide)
```

---

## ✅ You're All Set

Copy the first code snippet and run it. Everything else happens automatically.

If you want to understand what's happening, read through this file to see the exact execution order.

When done, check the output files to see your imputed biomechanics!
