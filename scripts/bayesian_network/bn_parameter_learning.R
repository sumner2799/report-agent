# ==============================================================================
# Bayesian Network Parameter Learning
# ==============================================================================
# Purpose: Learn conditional probability tables (CPTs) from MLB training data
# using the domain knowledge DAG structure defined in bn_network_definition.R
#
# This creates the "learned" network that will be used for inference on MiLB data

library(bnlearn)
library(tidyverse)

# ==============================================================================
# LEARN NETWORK PARAMETERS FROM TRAINING DATA
# ==============================================================================

learn_network_parameters <- function(
  training_data,
  bn_structure,
  method = "bayes",  # "bayes" (Bayesian) or "mle" (Maximum Likelihood)
  smoothing = 1      # Laplace smoothing for Bayes, prevents zero probabilities
) {
  # Fit the network structure to training data to learn CPTs
  # 
  # Args:
  #   training_data: Discretized factor data from prepare_training_data()
  #   bn_structure: DAG structure from create_biomech_network()
  #   method: Parameter learning method
  #   smoothing: Regularization parameter (higher = smoother, less overfitting)
  #
  # Returns:
  #   bn.fit object with learned conditional probability tables
  
  cat("\n=== Learning Network Parameters ===\n")
  cat("Method:", method, "\n")
  cat("Training samples:", nrow(training_data), "\n")
  
  if (method == "bayes") {
    fitted_bn <- bn.fit(
      x = bn_structure,
      data = training_data,
      method = "bayes",
      iss = smoothing  # Imaginary Sample Size (Dirichlet prior)
    )
  } else if (method == "mle") {
    fitted_bn <- bn.fit(
      x = bn_structure,
      data = training_data,
      method = "mle"
    )
  } else {
    stop("Unknown method. Choose 'bayes' or 'mle'")
  }
  
  cat("\nNetwork fitted successfully.\n")
  
  return(fitted_bn)
}

# ==============================================================================
# INSPECT LEARNED PARAMETERS
# ==============================================================================

inspect_cpts <- function(fitted_bn, node = NULL) {
  # Print conditional probability tables for inspection
  # If node is NULL, prints summary of all nodes
  # If node is specified, prints detailed CPT for that node
  
  if (is.null(node)) {
    # Print summary of all nodes and their parents
    cat("\n=== Network CPT Summary ===\n")
    for (n in names(fitted_bn)) {
      parents <- fitted_bn[[n]]$parents
      if (length(parents) == 0) {
        cat(sprintf("%s (prior): %d categories\n", n, length(fitted_bn[[n]]$prob)))
      } else {
        cat(sprintf("%s (parents: %s): %d categories\n", 
                    n, paste(parents, collapse=", "), 
                    length(fitted_bn[[n]]$prob)))
      }
    }
  } else {
    # Print detailed CPT
    if (!(node %in% names(fitted_bn))) {
      stop("Node not found in network:", node)
    }
    
    cat(sprintf("\n=== CPT for Node: %s ===\n", node))
    cpt <- fitted_bn[[node]]
    print(cpt)
  }
  
  invisible(fitted_bn)
}

# ==============================================================================
# DIAGNOSE PARAMETER QUALITY
# ==============================================================================

diagnose_parameter_quality <- function(fitted_bn, training_data) {
  # Check for potential issues in learned parameters
  # Returns diagnostics and warnings if problems found
  
  cat("\n=== Parameter Quality Diagnostics ===\n")
  
  issues <- list()
  
  # Check 1: Zero probabilities (can cause inference issues)
  cat("\nCheck 1: Zero Probability States\n")
  zero_count <- 0
  for (node in names(fitted_bn)) {
    probs <- fitted_bn[[node]]$prob
    # Count near-zero probabilities (< 0.001)
    if (is.array(probs)) {
      near_zero <- sum(probs < 0.001 & probs > 0)
    } else {
      near_zero <- sum(probs < 0.001 & probs > 0)
    }
    if (near_zero > 0) {
      zero_count <- zero_count + near_zero
    }
  }
  cat("Near-zero probability states found:", zero_count, "\n")
  if (zero_count > 100) {
    warning("High number of near-zero probabilities. Consider higher smoothing parameter.")
    issues$low_prob_states <- zero_count
  }
  
  # Check 2: Entropy of each node (is it informative?)
  cat("\nCheck 2: Node Entropy (Information Content)\n")
  for (node in names(fitted_bn)) {
    probs <- fitted_bn[[node]]$prob
    if (is.array(probs)) {
      probs <- as.numeric(probs)
    }
    probs <- probs[probs > 0]
    entropy <- -sum(probs * log(probs))
    max_entropy <- log(length(probs))
    normalized_entropy <- entropy / max_entropy
    
    if (normalized_entropy < 0.1) {
      cat(sprintf("  %s: Very low entropy (%.3f) - may be uninformative\n", 
                  node, normalized_entropy))
      issues[[paste0("low_entropy_", node)]] <- normalized_entropy
    } else if (normalized_entropy > 0.9) {
      cat(sprintf("  %s: Very high entropy (%.3f) - nearly uniform\n", 
                  node, normalized_entropy))
    }
  }
  
  # Check 3: Parent-child relationship strength
  cat("\nCheck 3: Conditional Independence (Parent-Child Relationships)\n")
  for (node in names(fitted_bn)) {
    parents <- fitted_bn[[node]]$parents
    if (length(parents) > 0) {
      # For each parent, check if conditioning reduces entropy
      cat(sprintf("  %s has parents: %s\n", node, paste(parents, collapse=", ")))
    }
  }
  
  return(invisible(issues))
}

# ==============================================================================
# SENSITIVITY ANALYSIS
# ==============================================================================

parameter_sensitivity <- function(fitted_bn, node, variable_to_vary) {
  # Show how sensitive output probabilities are to changes in a parent node
  # Useful for understanding which parents most influence a child
  
  if (!(node %in% names(fitted_bn))) {
    stop("Node not found:", node)
  }
  
  cpt <- fitted_bn[[node]]$prob
  
  # This is a placeholder for more detailed sensitivity analysis
  # Would typically show how P(node|parents) changes as parent values vary
  
  cat(sprintf("\n=== Sensitivity Analysis: %s ===\n", node))
  cat("This node's probability distribution depends on:\n")
  cat("  Parents:", paste(fitted_bn[[node]]$parents, collapse=", "), "\n")
  
  invisible(NULL)
}

# ==============================================================================
# EXPORT NETWORK FOR INFERENCE
# ==============================================================================

export_network <- function(fitted_bn, output_path = NULL) {
  # Save the fitted network to disk for later inference
  # Can use in separate process to avoid re-learning parameters
  
  if (is.null(output_path)) {
    output_path <- "/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/fitted_network.rds"
  }
  
  cat("Saving fitted network to:", output_path, "\n")
  saveRDS(fitted_bn, file = output_path)
  
  cat("✓ Network exported successfully\n")
  return(output_path)
}

load_network <- function(network_path) {
  # Load a previously saved fitted network
  
  if (!file.exists(network_path)) {
    stop("Network file not found:", network_path)
  }
  
  fitted_bn <- readRDS(network_path)
  cat("✓ Network loaded from:", network_path, "\n")
  
  return(fitted_bn)
}

# ==============================================================================
# COMPARE PARAMETER LEARNING METHODS
# ==============================================================================

compare_learning_methods <- function(training_data, bn_structure) {
  # Learn parameters using both Bayes and MLE methods
  # Return comparison for model selection
  
  cat("\n=== Comparing Parameter Learning Methods ===\n")
  
  # Bayesian method
  cat("\n1. Bayesian (with Laplace smoothing)...\n")
  bn_bayes <- learn_network_parameters(
    training_data, bn_structure,
    method = "bayes", smoothing = 1
  )
  
  # MLE method
  cat("\n2. Maximum Likelihood Estimation...\n")
  bn_mle <- learn_network_parameters(
    training_data, bn_structure,
    method = "mle"
  )
  
  # Compare
  cat("\n=== Comparison ===\n")
  cat("Bayesian method: Uses priors (Laplace smoothing) - smooths sparse data\n")
  cat("MLE method: No priors - can produce zero probabilities\n")
  cat("\nRecommendation: Use Bayesian for pitch-level data with potentially sparse cells\n")
  
  return(list(bayes = bn_bayes, mle = bn_mle))
}

# ==============================================================================
# VALIDATION: Test on held-out MLB data
# ==============================================================================

validate_on_holdout <- function(fitted_bn, holdout_data, focal_node) {
  # Quick validation: sample held-out pitches and check if posterior
  # distributions over hidden nodes are reasonable
  #
  # This is a "sanity check" before applying to MiLB data
  
  cat("\n=== Validation on Holdout Data ===\n")
  
  if (nrow(holdout_data) == 0) {
    warning("No holdout data provided. Skipping validation.")
    return(NULL)
  }
  
  # This would require the inference engine (cpquery/cpdist functions)
  # So we'll just return placeholder
  
  cat("Note: Full validation requires inference engine from bn_inference_engine.R\n")
  cat("Placeholder - run after inference engine is loaded\n")
  
  return(NULL)
}

# ==============================================================================
# EXPORT
# ==============================================================================

if (!exists("parameter_learning_config")) {
  parameter_learning_config <- list(
    learn_network_parameters = learn_network_parameters,
    inspect_cpts = inspect_cpts,
    diagnose_parameter_quality = diagnose_parameter_quality,
    parameter_sensitivity = parameter_sensitivity,
    export_network = export_network,
    load_network = load_network,
    compare_learning_methods = compare_learning_methods,
    validate_on_holdout = validate_on_holdout
  )
}
