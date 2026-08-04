# ==============================================================================
# Bayesian Network Definition & Domain Knowledge Encoding
# ==============================================================================
# Purpose: Define the DAG structure for pitch-level biomechanics imputation
# with domain knowledge relationships encoded as hard constraints
#
# Network Structure:
#   Pitch Context (stand, zone, pitch_name) 
#     → Swing Mechanics (swing_path_tilt, contact_depth, attack_direction, attack_angle)
#     → Intermediate Outcomes (launch_angle, spray_angle, launch_speed, intercept positions)
#   Backward Inference: Given observed intermediate outcomes + pitch context,
#     infer posterior distributions over hidden swing mechanics

library(bnlearn)

# ==============================================================================
# DEFINE DAG STRUCTURE WITH DOMAIN KNOWLEDGE
# ==============================================================================

create_biomech_network <- function() {
  # Start with empty network
  bn <- empty.graph(nodes = c(
    # Observable pitch context
    "stand",              # L/R handed batter
    "zone",               # Pitch location zone (1-9 + out of zone)
    "pitch_name",         # Type of pitch
    
    # Hidden biomechanics (TARGET FOR IMPUTATION)
    "attack_angle",       # Angle of bat swing attack
    "swing_path_tilt",    # Tilt of swing plane
    "attack_direction",   # Direction of bat swing (horizontal plane)
    "bat_speed",          # Speed of bat at contact
    "intercept_x",        # X position of contact (inches from batter center)
    "intercept_y",        # Y position of contact (inches) - also known as contact_depth
    
    # Observable outcomes (EVIDENCE FOR BACKWARD INFERENCE)
    "launch_speed",       # Exit velo (mph)
    "launch_angle",       # Launch angle (degrees)
    "spray_angle",        # Direction ball goes relative to plate
    "outcome"             # Hit/out/strikeout (optional, for context)
  ))
  
  # Domain Knowledge Causal Relationships
  # =========================================
  
  # Pitch context influences swing mechanics
  amat <- matrix(0, nrow = length(nodes(bn)), ncol = length(nodes(bn)))
  rownames(amat) <- colnames(amat) <- nodes(bn)
  
  # Pitch location → swing mechanics (batter responds to where pitch is)
  amat["zone", "swing_path_tilt"] <- 1
  amat["zone", "intercept_x"] <- 1
  amat["zone", "intercept_y"] <- 1  # intercept_y is contact depth
  
  # Batter handedness influences how we interpret directions
  amat["stand", "attack_direction"] <- 1
  amat["stand", "spray_angle"] <- 1
  amat["stand", "intercept_x"] <- 1
  
  # Pitch type influences swing mechanics
  amat["pitch_name", "swing_path_tilt"] <- 1
  amat["pitch_name", "attack_angle"] <- 1
  
  # Swing mechanics → attack/contact characteristics
  # (Domain knowledge from your analysis)
  amat["swing_path_tilt", "attack_angle"] <- 1
  amat["swing_path_tilt", "launch_angle"] <- 1
  amat["intercept_y", "attack_angle"] <- 1  # intercept_y (contact depth) influences attack angle
  amat["intercept_y", "attack_direction"] <- 1
  amat["intercept_y", "launch_angle"] <- 1
  
  # Attack characteristics → outcomes
  amat["attack_angle", "launch_angle"] <- 1
  amat["attack_angle", "launch_speed"] <- 1
  amat["attack_direction", "spray_angle"] <- 1
  amat["bat_speed", "launch_speed"] <- 1
  
  # Outcome nodes (observed evidence for inference)
  amat["launch_angle", "outcome"] <- 1
  amat["launch_speed", "outcome"] <- 1
  amat["spray_angle", "outcome"] <- 1
  
  # Set adjacency matrix
  amat(bn) <- amat
  
  return(bn)
}

# ==============================================================================
# DISCRETIZATION SCHEME
# ==============================================================================
# Define how continuous variables will be binned for CPT learning
# Using 4 levels for most variables (Low, Medium, High, Very High)

create_discretization_scheme <- function() {
  scheme <- list(
    # Continuous variables → discretize to levels
    attack_angle = list(
      levels = c("low", "medium", "high", "very_high"),
      breaks = c(0, 4, 8, 14, 40),  # degrees, approximate typical ranges
      description = "Angle of bat at contact relative to horizontal"
    ),
    
    swing_path_tilt = list(
      levels = c("low", "medium", "high", "very_high"),
      breaks = c(28, 32, 36, 38, 40),  # degrees, plane tilt
      description = "Tilt of swing plane (negative = drop, positive = rise)"
    ),
    
    bat_speed = list(
      levels = c("low", "medium", "high", "very_high"),
      breaks = c(60, 65, 70, 75, 80),  # mph
      description = "Bat speed at contact"
    ),
    
    launch_speed = list(
      levels = c("weak", "medium", "hard", "very_hard"),
      breaks = c(0, 70, 85, 95, 120),  # mph
      description = "Exit velocity"
    ),
    
    launch_angle = list(
      levels = c("ground", "line", "fly", "popup"),
      breaks = c(-90, 10, 25, 50, 90),  # degrees
      description = "Launch angle of batted ball"
    ),
    
    attack_direction = list(
      levels = c("pull", "oppo", "center"),
      description = "Horizontal direction of swing (note: handedness-dependent)"
    ),
    
    spray_angle = list(
      levels = c("pull", "oppo", "center"),
      description = "Direction ball travels (will normalize by stand)"
    ),
    
    intercept_x = list(
      levels = c("extreme_pull", "pull", "center", "oppo", "extreme_oppo"),
      breaks = c(-30, -10, -2, 2, 10, 30),  # inches
      description = "X position of contact relative to batter center"
    ),
    
    intercept_y = list(
      levels = c("deep", "middle", "shallow"),
      breaks = c(0, 33, 37, 45),  # inches from back of plate
      description = "contact depth"
    )
  )
  
  return(scheme)
}

# ==============================================================================
# CATEGORICAL VARIABLE MAPPINGS
# ==============================================================================

create_categorical_mappings <- function() {
  mappings <- list(
    stand = list(
      L = "left",
      R = "right",
      description = "Batter handedness"
    ),
    
    zone = list(
      zones = 1:14,  # 1-9 strike zone, 10-14 balls/out of zone
      description = "Pitch location zone"
    ),
    
    pitch_name = list(
      examples = c("Four-Seam Fastball", "Slider", "Curveball", "Changeup", 
                   "Sinker", "Split-Finger", "Knuckleball"),
      description = "Pitch type - will normalize across MLB/MiLB naming"
    ),
    
    outcome = list(
      levels = c("single", "double", "triple", "home_run", "out", "strikeout", "walk"),
      description = "Result of plate appearance (optional node)"
    )
  )
  
  return(mappings)
}

# ==============================================================================
# VALIDATION & DIAGNOSTICS
# ==============================================================================

validate_network_structure <- function(bn) {
  # Checks for basic network validity
  
  cat("\n=== Network Validation ===\n")
  cat("Nodes:", length(nodes(bn)), "\n")
  cat("Arcs:", length(arcs(bn)), "\n")
  cat("Acyclic:", acyclic(bn), "\n")
  
  # Check for orphaned nodes
  orphaned <- which(sapply(nodes(bn), function(node) {
    length(parents(bn, node)) == 0 && length(children(bn, node)) == 0
  }))
  
  if (length(orphaned) > 0) {
    cat("WARNING: Orphaned nodes (no parents/children):", names(orphaned), "\n")
  }
  
  # Print adjacency for review
  cat("\nNetwork Adjacency (domain knowledge relationships):\n")
  print(amat(bn))
  
  invisible(bn)
}

# ==============================================================================
# EXPORT FUNCTIONS
# ==============================================================================

if (!exists("bayesian_network_config")) {
  bayesian_network_config <- list(
    create_biomech_network = create_biomech_network,
    create_discretization_scheme = create_discretization_scheme,
    create_categorical_mappings = create_categorical_mappings,
    validate_network_structure = validate_network_structure
  )
}
