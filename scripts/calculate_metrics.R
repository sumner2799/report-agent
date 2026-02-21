# Helper Functions for Baseball Analysis
# Calculates percentiles, aggregations, and zone-based metrics

library(dplyr)
library(tidyr)

# =============================================================================
# Percentile Rank Calculation
# =============================================================================

calculate_percentile <- function(value, comparison_vector) {
  # Returns percentile rank of value within comparison_vector
  if (is.na(value)) return(NA)
  rank <- sum(comparison_vector <= value, na.rm = TRUE) / length(na.omit(comparison_vector))
  return(round(rank * 100, 1))
}

# =============================================================================
# Pitch Metrics
# =============================================================================

calculate_pitch_metrics <- function(data, pitch_type) {
  # Returns aggregated metrics for a specific pitch type
  
  pitch_data <- data %>% filter(pitch_type == !!pitch_type)
  
  metrics <- list(
    usage_pct = (nrow(pitch_data) / nrow(data)) * 100,
    avg_velocity = mean(pitch_data$release_speed, na.rm = TRUE),
    velo_min = min(pitch_data$release_speed, na.rm = TRUE),
    velo_max = max(pitch_data$release_speed, na.rm = TRUE),
    whiff_pct = (sum(pitch_data$description == "swinging_strike", na.rm = TRUE) / nrow(pitch_data)) * 100,
    swstr_pct = (sum(pitch_data$description == "swinging_strike", na.rm = TRUE) / sum(pitch_data$type == "X", na.rm = TRUE)) * 100,
    contact_pct = (sum(pitch_data$type != "B" & pitch_data$type != "X", na.rm = TRUE) / nrow(pitch_data)) * 100,
    slug_pct = mean(pitch_data$launch_speed, na.rm = TRUE)  # placeholder - would need actual slugging calc
  )
  
  return(metrics)
}

# =============================================================================
# Zone-by-Zone Analysis
# =============================================================================

categorize_zone <- function(px, pz) {
  # Categorizes pitch location into 9-zone grid
  # Zones: 1-3 (top), 4-6 (middle), 7-9 (bottom)
  # Left to right: 1,4,7 (left), 2,5,8 (center), 3,6,9 (right)
  
  if (is.na(px) || is.na(pz)) return(NA)
  
  zone <- case_when(
    px < -0.83 & pz >= 2.5 ~ 1,
    px >= -0.83 & px < 0.83 & pz >= 2.5 ~ 2,
    px >= 0.83 & pz >= 2.5 ~ 3,
    px < -0.83 & pz >= 1.5 & pz < 2.5 ~ 4,
    px >= -0.83 & px < 0.83 & pz >= 1.5 & pz < 2.5 ~ 5,
    px >= 0.83 & pz >= 1.5 & pz < 2.5 ~ 6,
    px < -0.83 & pz < 1.5 ~ 7,
    px >= -0.83 & px < 0.83 & pz < 1.5 ~ 8,
    px >= 0.83 & pz < 1.5 ~ 9,
    TRUE ~ NA
  )
  
  return(zone)
}

calculate_zone_metrics <- function(data) {
  # Returns performance metrics by zone
  
  zone_data <- data %>%
    mutate(zone = categorize_zone(plate_x, plate_z)) %>%
    filter(!is.na(zone)) %>%
    group_by(zone) %>%
    summarise(
      pitch_count = n(),
      avg_exit_velo = mean(launch_speed, na.rm = TRUE),
      sweet_spot_pct = (sum(launch_angle >= 8 & launch_angle <= 32, na.rm = TRUE) / n()) * 100,
      slug_pct = mean(launch_speed, na.rm = TRUE),
      .groups = "drop"
    )
  
  return(zone_data)
}

# =============================================================================
# Hitter Evaluation Patterns
# =============================================================================

evaluate_swing_loft <- function(data) {
  # Returns assessment of swing loft based on opposite field fly balls
  
  opp_field_fb <- data %>%
    filter(hit_distance_sc > 0, launch_angle >= 15, launch_angle <= 35) %>%
    filter(hc_x > 150 | hc_x < 90)  # approximate opposite field
  
  avg_exit_velo <- mean(opp_field_fb$launch_speed, na.rm = TRUE)
  count <- nrow(opp_field_fb)
  
  assessment <- list(
    opposite_field_fb_count = count,
    avg_exit_velo_off = avg_exit_velo,
    concern_flag = if_else(avg_exit_velo < 85 & count > 20, TRUE, FALSE)
  )
  
  return(assessment)
}

evaluate_bat_angle <- function(data) {
  # Returns assessment of bat angle based on whiff and contact patterns
  
  whiff_rate <- (sum(data$description == "swinging_strike", na.rm = TRUE) / nrow(data)) * 100
  
  # High pitches
  high_pitches <- data %>% filter(plate_z >= 2.5)
  whiff_high <- (sum(high_pitches$description == "swinging_strike", na.rm = TRUE) / nrow(high_pitches)) * 100
  
  # Low/inside pitches
  low_in <- data %>% filter(plate_z < 1.5 & plate_x < 0)
  sweet_spot_low_in <- (sum(low_in$launch_angle >= 8 & low_in$launch_angle <= 32, na.rm = TRUE) / nrow(low_in)) * 100
  foul_low_in <- (sum(low_in$description == "foul", na.rm = TRUE) / nrow(low_in)) * 100
  
  assessment <- list(
    overall_whiff_pct = whiff_rate,
    whiff_high_pct = whiff_high,
    sweet_spot_low_in = sweet_spot_low_in,
    foul_low_in = foul_low_in,
    steep_bat_angle_flag = if_else(whiff_high > whiff_rate + 5 & sweet_spot_low_in > 40, TRUE, FALSE)
  )
  
  return(assessment)
}

# =============================================================================
# Trend Comparison
# =============================================================================

compare_periods <- function(current_data, previous_data, metrics_list) {
  # Compares key metrics between two time periods
  
  comparison <- tibble(
    metric = metrics_list,
    current = NA_real_,
    previous = NA_real_,
    delta = NA_real_
  )
  
  # This is a template - would be populated based on specific metrics
  return(comparison)
}
