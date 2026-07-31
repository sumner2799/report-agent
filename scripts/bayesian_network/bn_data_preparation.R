# ==============================================================================
# Data Preparation for Bayesian Network Training
# ==============================================================================
# Purpose: Extract, clean, and discretize MLB Statcast data for learning
# conditional probability tables for pitch-level biomechanics network
#
# Key transformations:
#   - Normalize spray_angle by batter handedness (stand-relative)
#   - Discretize continuous variables per scheme
#   - Align MLB field names to network node names
#   - Create complete cases for network training

library(tidyverse)
library(data.table)
library(stringr)
library(RMySQL)

# ==============================================================================
# LOAD RAW MLB STATCAST DATA
# ==============================================================================

load_mlb_statcast_files <- function(raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw") {
  # Load all MLB Statcast CSV files (typically weekly files)
  # Assumes standard Statcast format from Baseball Savant
  
  conn <- dbConnect(
  MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

statcast_data <- dbGetQuery(conn,glue::glue(
  "select
*   
from
sc_mlb
where
game_year = 2026
  ",
  .con = conn
  )
)
  
  cat("Total rows loaded:", nrow(statcast_data), "\n")
  return(statcast_data)
}

# ==============================================================================
# FIELD NAME MAPPING: MLB Statcast → Network Nodes
# ==============================================================================

create_field_mapping <- function() {
  # Map MLB Statcast columns to network node names
  # Source: https://baseballsavant.mlb.com/csv-docs
  
  mapping <- list(
    # Pitch context
    stand = "stand",                          # L or R
    zone = "zone",                            # 1-14 pitch location zone
    pitch_type = "pitch_name",                # Pitch type abbreviation/name
    
    # Observable outcomes (evidence)
    launch_speed = "launch_speed",            # Exit velo (mph)
    launch_angle = "launch_angle",            # Launch angle (degrees)
    hc_x = "spray_x_raw",                     # Horizontal contact location (raw)
    hc_y = "spray_y_raw",                     # Vertical contact location (raw)
    
    # Hidden biomechanics to impute
    attack_angle = "attack_angle",            # Angle of attack (degrees)
    tilt = "swing_path_tilt",                 # Swing path tilt (degrees) 
    baxisx = "attack_direction",              # Bat direction X (horizontal)
    bavx = "bat_speed",                       # Bat speed (mph)
    
    # Position at contact
    px = "intercept_x",                       # Plate X (ball position at contact)
    pz = "intercept_y",                       # Plate Z (ball position at contact)
    
    # Derived/computed
    contact_distance = "contact_depth",       # Computed: distance from plate
    spray_angle = "spray_angle",              # Computed: direction of batted ball
    outcome = "outcome"                       # Hit type
  )
  
  return(mapping)
}

# ==============================================================================
# NORMALIZE SPRAY ANGLE BY BATTER HANDEDNESS
# ==============================================================================

normalize_spray_angle <- function(df) {
  # Convert spray_angle (plate coordinates) to handedness-relative direction
  # This ensures that "pull" means the same thing regardless of L/R batter
  # 
  # Approach: Use hc_x (horizontal contact location) relative to 1st/3rd baseline
  # For LHB: spray_angle > 15° typically means pull (toward 1B side)
  # For RHB: spray_angle < -15° typically means pull (toward 3B side)
  # We normalize so that all pulls are "pull" category, etc.
  
  df <- df %>%
    mutate(
      # Compute spray angle from home plate perspective with correct field geometry
      spray_angle_raw = case_when(
        is.na(hc_x) | is.na(hc_y) ~ NA_real_,
        TRUE ~ round(
          (atan(
            (hc_x - 125.42) / (198.27 - hc_y)
          ) * 180 / pi * 0.75),
          1
        )  # Correct spray angle formula with field-specific constants
      ),
      
      # Normalize by batter handedness
      spray_angle_normalized = case_when(
        # Left-handed hitter: positive angles are pull side (1B)
        stand == "L" & spray_angle_raw > 15 ~ "pull",
        stand == "L" & spray_angle_raw < -15 ~ "oppo",
        stand == "L" ~ "center",
        
        # Right-handed hitter: negative angles are pull side (3B)
        stand == "R" & spray_angle_raw < -15 ~ "pull",
        stand == "R" & spray_angle_raw > 15 ~ "oppo",
        stand == "R" ~ "center",
        
        TRUE ~ NA_character_
      )
    )
  
  return(df)
}

# ==============================================================================
# COMPUTE CONTACT DEPTH - No need for this
# ==============================================================================

# compute_contact_depth <- function(df) {
#   # Contact depth = distance from back of plate (in x-coordinate)
#   # px is typically measured from center of plate (-8.5 to 8.5 inches for zone)
#   # Convert to distance from back of plate (0 = back, 40+ = way in front)
  
#   df <- df %>%
#     mutate(
#       contact_depth = case_when(
#         is.na(px) ~ NA_real_,
#         TRUE ~ 8.5 - px  # Back of plate is ~8.5 inches from center when measured from pitcher
#       ),
#       contact_depth = pmax(0, contact_depth)  # Ensure non-negative
#     )
  
#   return(df)
# }

# ==============================================================================
# DISCRETIZE CONTINUOUS VARIABLES
# ==============================================================================

discretize_variables <- function(df, discretization_scheme) {
  # Apply binning scheme to continuous variables
  # discretization_scheme comes from bn_network_definition.R
  
  df <- df %>%
    mutate(
      # Attack angle
      attack_angle_binned = cut(
        attack_angle,
        breaks = discretization_scheme$attack_angle$breaks,
        labels = discretization_scheme$attack_angle$levels,
        include.lowest = TRUE
      ),
      
      # Swing tilt
      swing_path_tilt_binned = cut(
        tilt,
        breaks = discretization_scheme$swing_path_tilt$breaks,
        labels = discretization_scheme$swing_path_tilt$levels,
        include.lowest = TRUE
      ),
      
      # Bat speed
      bat_speed_binned = cut(
        bavx,
        breaks = discretization_scheme$bat_speed$breaks,
        labels = discretization_scheme$bat_speed$levels,
        include.lowest = TRUE
      ),
      
      # Launch speed
      launch_speed_binned = cut(
        launch_speed,
        breaks = discretization_scheme$launch_speed$breaks,
        labels = discretization_scheme$launch_speed$levels,
        include.lowest = TRUE
      ),
      
      # Launch angle
      launch_angle_binned = cut(
        launch_angle,
        breaks = discretization_scheme$launch_angle$breaks,
        labels = discretization_scheme$launch_angle$levels,
        include.lowest = TRUE
      ),
      
      # Intercept X (horizontal)
      intercept_x_binned = cut(
        px,
        breaks = discretization_scheme$intercept_x$breaks,
        labels = discretization_scheme$intercept_x$levels,
        include.lowest = TRUE
      ),
      
      # Intercept Y (vertical/height)
      intercept_y_binned = cut(
        pz,
        breaks = discretization_scheme$intercept_y$breaks,
        labels = discretization_scheme$intercept_y$levels,
        include.lowest = TRUE
      ),
      
      # Attack direction (convert from continuous to categorical)
      attack_direction_binned = cut(
        baxisx,
        breaks = c(-90, -30, 30, 90),
        labels = c("pull", "center", "oppo"),
        include.lowest = TRUE
      )
    )
  
  return(df)
}

# ==============================================================================
# PREPARE TRAINING DATASET
# ==============================================================================

prepare_training_data <- function(
#   raw_data_dir = "/Users/andrewsumner/Documents/Github/report-agent/data/raw",
  discretization_scheme = NULL,
  min_data_quality_threshold = 0.8
) {
  # Master function to load, clean, and prepare training data
  
  source("/Users/andrewsumner/Documents/Github/report-agent/scripts/bayesian_network/bn_network_definition.R")
  
  if (is.null(discretization_scheme)) {
    discretization_scheme <- create_discretization_scheme()
  }
  
  # 1. Load MLB Statcast
  cat("\n=== Step 1: Loading MLB Statcast Data ===\n")
  mlb_data <- load_mlb_statcast_files(raw_data_dir)
  
  # 2. Normalize spray angle by handedness
  cat("\n=== Step 2: Normalizing Spray Angle ===\n")
  mlb_data <- normalize_spray_angle(mlb_data)
  
  # 3. Compute contact depth
  cat("\n=== Step 3: Computing Contact Depth ===\n")
  mlb_data <- compute_contact_depth(mlb_data)
  
  # 4. Discretize continuous variables
  cat("\n=== Step 4: Discretizing Variables ===\n")
  mlb_data <- discretize_variables(mlb_data, discretization_scheme)
  
  # 5. Select only columns needed for network
  cat("\n=== Step 5: Selecting Network Columns ===\n")
  
  network_cols <- c(
    # Pitch context (observable)
    "stand",
    "zone",
    "pitch_type",
    
    # Hidden biomechanics (targets)
    "attack_angle_binned",
    "swing_path_tilt_binned",
    "attack_direction_binned",
    "bat_speed_binned",
    "intercept_x_binned",
    "intercept_y_binned",
    
    # Observable outcomes (evidence)
    "launch_speed_binned",
    "launch_angle_binned",
    "spray_angle_normalized"
  )
  
  training_data <- mlb_data %>%
    select(all_of(network_cols)) %>%
    rename(
      attack_angle = attack_angle_binned,
      swing_path_tilt = swing_path_tilt_binned,
      attack_direction = attack_direction_binned,
      bat_speed = bat_speed_binned,
      intercept_x = intercept_x_binned,
      intercept_y = intercept_y_binned,
      launch_speed = launch_speed_binned,
      launch_angle = launch_angle_binned,
      spray_angle = spray_angle_normalized
    )
  
  # 6. Remove incomplete cases
  cat("\n=== Step 6: Handling Missing Data ===\n")
  initial_rows <- nrow(training_data)
  training_data <- training_data %>% drop_na()
  final_rows <- nrow(training_data)
  data_retention <- final_rows / initial_rows * 100
  
  cat("Initial rows:", initial_rows, "\n")
  cat("Complete cases:", final_rows, "\n")
  cat("Data retention:", sprintf("%.1f%%", data_retention), "\n")
  
  if (data_retention < min_data_quality_threshold * 100) {
    warning(sprintf(
      "Low data retention (%.1f%%). Consider relaxing completeness requirement.",
      data_retention
    ))
  }
  
  # 7. Convert to factor for bnlearn compatibility
  cat("\n=== Step 7: Converting to Factors ===\n")
  training_data <- training_data %>%
    mutate(across(everything(), as.factor))
  
  # Summary statistics
  cat("\n=== Training Data Summary ===\n")
  cat("Dimensions:", nrow(training_data), "rows ×", ncol(training_data), "columns\n")
  cat("Variables:\n")
  print(str(training_data))
  
  return(training_data)
}

# ==============================================================================
# EXPORT
# ==============================================================================

if (!exists("data_preparation_config")) {
  data_preparation_config <- list(
    load_mlb_statcast_files = load_mlb_statcast_files,
    create_field_mapping = create_field_mapping,
    normalize_spray_angle = normalize_spray_angle,
    compute_contact_depth = compute_contact_depth,
    discretize_variables = discretize_variables,
    prepare_training_data = prepare_training_data
  )
}
