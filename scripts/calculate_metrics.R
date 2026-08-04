# Helper Functions for Baseball Analysis
# Calculates percentiles, aggregations, and zone-based metrics

library(dplyr)
library(tidyr)
library(readr)
library(purrr)
library(lubridate)

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
# Percentile Rank Functions for Reports
# =============================================================================

calculate_pitcher_overall_percentiles <- function(pitcher_metrics, pitcher_id, level) {
  # Calculates percentile ranks for pitcher overall performance
  # pitcher_metrics: list returned from calculate_pitcher_overall_perf (includes swing_pct, strike_pct, etc.)
  # pitcher_id: ID to identify current pitcher in combined dataset
  # level: league level ("MLB", "AAA", "AA", etc.) for context in calculations
  
  # Load supporting data
  supporting_data <- read_csv("data/supporting/pitcher_overall_overall.csv", show_col_types = FALSE) %>%
  select(-(1))
  
  # Create current pitcher row with renamed metrics
  current_pitcher <- tibble(
    player_name = pitcher_id,
    # level = level,
    pitch_name = "Overall",
    Pitches = pitcher_metrics$pitches,
    BIP = pitcher_metrics$bip,
    `Swing%` = pitcher_metrics$swing_pct,
    `Strike%` = pitcher_metrics$strike_pct,
    `Zone%` = pitcher_metrics$zone_pct,
    `Chase%` = pitcher_metrics$chase_pct,
    `CS%` = pitcher_metrics$cs_pct,
    `Foul%` = pitcher_metrics$foul_pct,
    `Whiff%` = pitcher_metrics$whiff_pct,
    `IZ Whiff` = pitcher_metrics$iz_whiff,
    `OZ Whiff` = pitcher_metrics$oz_whiff,
    `GB%` = pitcher_metrics$gb_pct,
    `HH%` = pitcher_metrics$hh_pct
  )
  
  # Combine with supporting data
  combined <- rbind(supporting_data, current_pitcher)
  
  # Calculate percentile ranks for each metric
  percentiles <- combined %>%
    arrange(desc(`Swing%`)) %>%
    mutate(swing_rank = round(percent_rank(`Swing%`) * 100, 1)) %>%
    arrange(desc(`Strike%`)) %>%
    mutate(strike_rank = round(percent_rank(`Strike%`) * 100, 1)) %>%
    arrange(desc(`Zone%`)) %>%
    mutate(zone_rank = round(percent_rank(`Zone%`) * 100, 1)) %>%
    arrange(desc(`Chase%`)) %>%
    mutate(chase_rank = round(percent_rank(`Chase%`) * 100, 1)) %>%
    arrange(desc(`CS%`)) %>%
    mutate(cs_rank = round(percent_rank(`CS%`) * 100, 1)) %>%
    arrange(desc(`Foul%`)) %>%
    mutate(foul_rank = round(percent_rank(`Foul%`) * 100, 1)) %>%
    arrange(desc(`Whiff%`)) %>%
    mutate(whiff_rank = round(percent_rank(`Whiff%`) * 100, 1)) %>%
    arrange(desc(`IZ Whiff`)) %>%
    mutate(iz_whiff_rank = round(percent_rank(`IZ Whiff`) * 100, 1)) %>%
    arrange(desc(`OZ Whiff`)) %>%
    mutate(oz_whiff_rank = round(percent_rank(`OZ Whiff`) * 100, 1)) %>%
    arrange(desc(`GB%`)) %>%
    mutate(gb_rank = round(percent_rank(`GB%`) * 100, 1)) %>%
    arrange(desc(`HH%`)) %>%
    mutate(hh_rank = round(percent_rank(desc(`HH%`)) * 100, 1)) %>%
    filter(player_name == pitcher_id) %>%
    select(swing_rank, strike_rank, zone_rank, chase_rank, cs_rank, foul_rank, 
           whiff_rank, iz_whiff_rank, oz_whiff_rank, gb_rank, hh_rank)
  
  return(as.list(percentiles))
}

calculate_pitcher_pitch_percentiles <- function(pitch_perf, pitcher_id, level) {
  # Calculates percentile ranks for pitcher pitch-level performance
  # pitch_perf: tibble returned from calculate_pitcher_pitch_perf
  # pitcher_id: ID to identify current pitcher
  # level: league level ("MLB", "AAA", "AA", etc.) for context
  
  # Load supporting data
  supporting_data <- read_csv("data/supporting/pitcher_pitch_overall.csv", show_col_types = FALSE) %>%
  select(-(1))
  
  # Rename pitch_perf columns to match supporting data format
  if (level == "MLB") {
    pitch_perf_renamed <- pitch_perf %>%
    mutate(player_name = pitcher_id) %>%
    rename(
      pitch_name = pitch_name,
      Pitches = pitches,
      BIP = bip,
      `Swing%` = swing_pct,
      `Strike%` = strike_pct,
      `Zone%` = zone_pct,
      `CS%` = cs_pct,
      `Foul%` = foul_pct,
      `Chase%` = chase_pct,
      `Whiff%` = whiff_pct,
      `IZ Whiff` = iz_whiff,
      `OZ Whiff` = oz_whiff,
      `GB%` = gb_pct,
      `HH%` = hh_pct
    ) 
  } else {
    pitch_perf_renamed <- pitch_perf %>%
    mutate(player_name = pitcher_id) %>%
    rename(
      pitch_name = details.type.description,
      Pitches = Pitches,
      BIP = BIP,
      `Swing%` = `Swing%`,
      `Strike%` = `Strike%`,
      `Zone%` = `Zone%`,
      `Chase%` = `Chase%`,
      `CS%` = `CS%`,
      `Foul%` = `Foul%`,
      `Whiff%` = `Whiff%`,
      `IZ Whiff` = `IZ Whiff`,
      `OZ Whiff` = `OZ Whiff`,
      `GB%` = `GB%`,
      `HH%` = `HH%`
    ) 
  }
  
  
  # Combine with supporting data
  combined <- rbind(supporting_data, pitch_perf_renamed)
  
  # Calculate percentile ranks by pitch type
  percentiles <- combined %>%
    group_by(pitch_name) %>%
    arrange(desc(`Swing%`), .by_group = TRUE) %>%
    mutate(swing_rank = round(percent_rank(`Swing%`) * 100, 1)) %>%
    arrange(desc(`Strike%`), .by_group = TRUE) %>%
    mutate(strike_rank = round(percent_rank(`Strike%`) * 100, 1)) %>%
    arrange(desc(`Zone%`), .by_group = TRUE) %>%
    mutate(zone_rank = round(percent_rank(`Zone%`) * 100, 1)) %>%
    arrange(desc(`Chase%`), .by_group = TRUE) %>%
    mutate(chase_rank = round(percent_rank(`Chase%`) * 100, 1)) %>%
    arrange(desc(`Whiff%`), .by_group = TRUE) %>%
    mutate(whiff_rank = round(percent_rank(`Whiff%`) * 100, 1)) %>%
    arrange(desc(`IZ Whiff`), .by_group = TRUE) %>%
    mutate(iz_whiff_rank = round(percent_rank(`IZ Whiff`) * 100, 1)) %>%
    arrange(desc(`OZ Whiff`), .by_group = TRUE) %>%
    mutate(oz_whiff_rank = round(percent_rank(`OZ Whiff`) * 100, 1)) %>%
    arrange(desc(`GB%`), .by_group = TRUE) %>%
    mutate(gb_rank = round(percent_rank(`GB%`) * 100, 1)) %>%
    arrange(desc(`HH%`), .by_group = TRUE) %>%
    mutate(hh_rank = round(percent_rank(desc(`HH%`)) * 100, 1)) %>%
    ungroup() %>%
    filter(player_name == pitcher_id) %>%
    select(pitch_name, Pitches, BIP, swing_rank, strike_rank, zone_rank, chase_rank, whiff_rank,
           iz_whiff_rank, oz_whiff_rank, gb_rank, hh_rank) %>%
    arrange(desc(Pitches))
  
  return(percentiles)
}
# calculate_batter_overall_percentiles(overall_perf, batter_id, level)
calculate_batter_overall_percentiles <- function(batter_metrics, batter_id, level = "MLB") {
  # Calculates percentile ranks for batter overall performance
  # batter_metrics: list returned from calculate_batter_overall_perf
  # batter_id: ID to identify current batter
  # level: league level ("MLB", "AAA", "AA", etc.) for context
  
  # Load supporting data
  supporting_data <- read_csv("data/supporting/batter_overall_overall.csv", show_col_types = FALSE) %>%
  select(2:12,`Sweet Spot%`)
  
  # Create current batter row with renamed metrics
  current_batter <- tibble(
    last_first_name = batter_id,
    # level = level,
    # last_first_name = NA_character_,
    `BIP.x` = batter_metrics$bip,
    `Swing%` = batter_metrics$swing_pct,
    `Chase%` = batter_metrics$chase_pct,
    `Foul%` = batter_metrics$foul_pct,
    `Whiff%` = batter_metrics$whiff_pct,
    `IZ Whiff` = batter_metrics$iz_whiff,
    `OZ Whiff` = batter_metrics$oz_whiff,
    `GB%` = batter_metrics$gb_pct,
    `HH%` = batter_metrics$hh_pct,
    `SLGcon` = batter_metrics$slg,
    `Sweet Spot%` = batter_metrics$swspt_pct
  )
  
  # Combine with supporting data
  combined <- rbind(supporting_data, current_batter)
  
  # Calculate percentile ranks for each metric
  percentiles <- combined %>%
    arrange(desc(`Swing%`)) %>%
    mutate(swing_rank = round(percent_rank(`Swing%`) * 100, 1)) %>%
    arrange(desc(`Chase%`)) %>%
    mutate(chase_rank = round(percent_rank(desc(`Chase%`)) * 100, 1)) %>%
    arrange(desc(`Foul%`)) %>%
    mutate(foul_rank = round(percent_rank(`Foul%`) * 100, 1)) %>%
    arrange(desc(`Whiff%`)) %>%
    mutate(whiff_rank = round(percent_rank(desc(`Whiff%`)) * 100, 1)) %>%
    arrange(desc(`IZ Whiff`)) %>%
    mutate(iz_whiff_rank = round(percent_rank(desc(`IZ Whiff`)) * 100, 1)) %>%
    arrange(desc(`OZ Whiff`)) %>%
    mutate(oz_whiff_rank = round(percent_rank(desc(`OZ Whiff`)) * 100, 1)) %>%
    arrange(desc(`GB%`)) %>%
    mutate(gb_rank = round(percent_rank(`GB%`) * 100, 1)) %>%
    arrange(desc(`HH%`)) %>%
    mutate(hh_rank = round(percent_rank(`HH%`) * 100, 1)) %>%
    arrange(desc(`SLGcon`)) %>%
    mutate(slg_rank = round(percent_rank(`SLGcon`) * 100, 1)) %>%
    arrange(desc(`Sweet Spot%`)) %>%
    mutate(swspt_rank = round(percent_rank(`Sweet Spot%`) * 100, 1)) %>%
    filter(last_first_name == batter_id) %>%
    select(swing_rank, chase_rank, foul_rank, whiff_rank, iz_whiff_rank, oz_whiff_rank,
           gb_rank, hh_rank, slg_rank, swspt_rank)
  
  return(as.list(percentiles))
}

calculate_batter_zone_percentiles <- function(zone_perf, batter_id, level) {
  # Calculates percentile ranks for batter zone performance
  # zone_perf: tibble returned from calculate_batter_zone_perf
  # batter_id: ID to identify current batter
  
  # Load supporting data
  supporting_data <- read_csv("data/supporting/batter_zone_overall.csv", show_col_types = FALSE) %>%
  select(-(1))
  
  # Rename zone_perf columns to match supporting data format
  zone_perf_renamed <- zone_perf %>%
    mutate(
      last_first_name = batter_id
    )
  
  # Combine with supporting data
  combined <- rbind(supporting_data, zone_perf_renamed)
  
  # Calculate percentile ranks by zone location
  percentiles <- combined %>%
    group_by(Location) %>%
    arrange(desc(`Swing%`), .by_group = TRUE) %>%
    mutate(swing_rank = round(percent_rank(`Swing%`) * 100, 1)) %>%
    arrange(desc(`Chase%`), .by_group = TRUE) %>%
    mutate(chase_rank = round(percent_rank(desc(`Chase%`)) * 100, 1)) %>%
    arrange(desc(`Foul%`), .by_group = TRUE) %>%
    mutate(foul_rank = round(percent_rank(`Foul%`) * 100, 1)) %>%
    arrange(desc(`Whiff%`), .by_group = TRUE) %>%
    mutate(whiff_rank = round(percent_rank(desc(`Whiff%`)) * 100, 1)) %>%
    arrange(desc(`IZ Whiff`), .by_group = TRUE) %>%
    mutate(iz_whiff_rank = round(percent_rank(desc(`IZ Whiff`)) * 100, 1)) %>%
    arrange(desc(`OZ Whiff`), .by_group = TRUE) %>%
    mutate(oz_whiff_rank = round(percent_rank(desc(`OZ Whiff`)) * 100, 1)) %>%
    arrange(desc(`GB%`), .by_group = TRUE) %>%
    mutate(gb_rank = round(percent_rank(`GB%`) * 100, 1)) %>%
    arrange(desc(`HH%`), .by_group = TRUE) %>%
    mutate(hh_rank = round(percent_rank(`HH%`) * 100, 1)) %>%
    arrange(desc(`SLGcon`), .by_group = TRUE) %>%
    mutate(slg_rank = round(percent_rank(`SLGcon`) * 100, 1)) %>%
    arrange(desc(`Sweet Spot%`), .by_group = TRUE) %>%
    mutate(swspt_rank = round(percent_rank(`Sweet Spot%`) * 100, 1)) %>%
    ungroup() %>%
    filter(last_first_name == batter_id) %>%
    select(Location, BIP, swing_rank, chase_rank, foul_rank, whiff_rank, iz_whiff_rank, 
           oz_whiff_rank, gb_rank, hh_rank, slg_rank, swspt_rank) %>%
    arrange(desc(BIP))
  
  return(percentiles)
}

calculate_batter_profile_percentiles <- function(profile_metrics, batter_id, level) {
  # Calculates percentile ranks for batter profile/swing quality metrics
  # profile_metrics: list returned from calculate_batter_profile
  # batter_id: ID to identify current batter
  
  # Load supporting data (using overall for now)
  supporting_data <- read_csv("data/supporting/batter_overall_overall.csv", show_col_types = FALSE) %>%
    select(last_first_name, `Avg LA`, `LA Std Dev`, `Sweet Spot%`, `HH LA`, `Oppo FB%`, `Oppo FB EV`, `High AA%`)
  
  # Create current batter row with profile metrics
  current_batter <- tibble(
    last_first_name = batter_id,
    `Avg LA` = profile_metrics$avg_la,
    `LA Std Dev` = profile_metrics$la_std_dev,
    `Sweet Spot%` = profile_metrics$sweet_spot_pct,
    `HH LA` = profile_metrics$hh_la,
    `Oppo FB%` = profile_metrics$oppo_fb_pct,
    `Oppo FB EV` = profile_metrics$oppo_fb_ev,
    `High AA%` = profile_metrics$high_aa_pct
  )
  
  # Combine with supporting data
  combined <- rbind(supporting_data, current_batter)
  
  # Calculate percentile ranks for each metric
  percentiles <- combined %>%
    arrange(desc(`Avg LA`)) %>%
    mutate(avg_la_rank = round(percent_rank(`Avg LA`) * 100, 1)) %>%
    arrange(desc(`LA Std Dev`)) %>%
    mutate(la_std_rank = round(percent_rank(`LA Std Dev`) * 100, 1)) %>%
    arrange(desc(`Sweet Spot%`)) %>%
    mutate(swspt_rank = round(percent_rank(`Sweet Spot%`) * 100, 1)) %>%
    arrange(desc(`HH LA`)) %>%
    mutate(hh_la_rank = round(percent_rank(`HH LA`) * 100, 1)) %>%
    arrange(desc(`Oppo FB%`)) %>%
    mutate(oppo_fb_pct_rank = round(percent_rank(`Oppo FB%`) * 100, 1)) %>%
    arrange(desc(`Oppo FB EV`)) %>%
    mutate(oppo_fb_ev_rank = round(percent_rank(`Oppo FB EV`) * 100, 1)) %>%
    arrange(desc(`High AA%`)) %>%
    mutate(high_aa_rank = round(percent_rank(`High AA%`) * 100, 1)) %>%
    filter(last_first_name == batter_id) %>%
    select(avg_la_rank, la_std_rank, swspt_rank, hh_la_rank, oppo_fb_pct_rank, 
           oppo_fb_ev_rank, high_aa_rank)
  
  return(as.list(percentiles))
}

# =============================================================================
# Pitch Metrics
# =============================================================================

calculate_pitch_metrics <- function(data, pitch_type, batter_hand = NULL) {
  # Returns aggregated metrics for a specific pitch type
  # If batter_hand is specified (R or L), filters to that handedness
  pitch_data <- data %>% filter(pitch_type == !!pitch_type)
  
  if (!is.null(batter_hand)) {
    total_data <- data %>% filter(stand == batter_hand)
    pitch_data <- pitch_data %>% filter(stand == batter_hand)
  } else {
    total_data <- data
  }
  
  # Guard velocities: check for non-missing values before min/max
  velo_valid <- pitch_data$release_speed[!is.na(pitch_data$release_speed)]
  velo_min_val <- if (length(velo_valid) > 0) round(min(velo_valid), 1) else NA
  velo_max_val <- if (length(velo_valid) > 0) round(max(velo_valid), 1) else NA
  
  # Safe column access with fallback to NA if column doesn't exist
  rel_side_val <- if ("release_pos_x" %in% colnames(pitch_data)) {
    round(mean(pitch_data$release_pos_x, na.rm = TRUE), 2)
  } else {
    NA
  }
  
  rel_height_val <- if ("release_pos_z" %in% colnames(pitch_data)) {
    round(mean(pitch_data$release_pos_z, na.rm = TRUE), 2)
  } else {
    NA
  }
  
  hb_val <- if ("pfx_x" %in% colnames(pitch_data)) {
    round(mean(pitch_data$pfx_x, na.rm = TRUE) * 12, 1)
  } else {
    NA
  }
  
  vb_val <- if ("pfx_z" %in% colnames(pitch_data)) {
    round(mean(pitch_data$pfx_z, na.rm = TRUE) * 12, 1)
  } else {
    NA
  }
  
  spin_val <- if ("release_spin_rate" %in% colnames(pitch_data)) {
    round(mean(pitch_data$release_spin_rate, na.rm = TRUE), 0)
  } else {
    NA
  }
  
  metrics <- list(
    usage_pct = (nrow(pitch_data) / nrow(total_data)) * 100,
    avg_velocity = round(mean(pitch_data$release_speed, na.rm = TRUE), 1),
    velo_min = velo_min_val,
    velo_max = velo_max_val,
    rel_side = rel_side_val,
    rel_height = rel_height_val,
    hb = hb_val,
    vb = vb_val,
    spin = spin_val,
    whiff_pct = (sum(pitch_data$description == "swinging_strike", na.rm = TRUE) / nrow(pitch_data)) * 100,
    swstr_pct = (sum(pitch_data$description == "swinging_strike", na.rm = TRUE) / sum(pitch_data$type == "X", na.rm = TRUE)) * 100,
    contact_pct = (sum(pitch_data$type != "B" & pitch_data$type != "X", na.rm = TRUE) / nrow(pitch_data)) * 100,
    slug_pct = mean(pitch_data$launch_speed, na.rm = TRUE)  # placeholder - would need actual slugging calc
  )
  
  return(metrics)
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

# =============================================================================
# Pitcher-Level Aggregates
# =============================================================================

calculate_pitcher_bip <- function(pitcher_data) {
  # Returns total Balls In Play for a pitcher
  bip_count <- sum(pitcher_data$description == "hit_into_play", na.rm = TRUE)
  return(bip_count)
}

calculate_hitter_bip <- function(hitter_data) {
  # Returns total Balls In Play for a hitter
  bip_count <- sum(hitter_data$description == "hit_into_play", na.rm = TRUE)
  return(bip_count)
}

calculate_pitcher_bip_mnl <- function(pitcher_data) {
  # Returns total Balls In Play for a pitcher
  bip_count <- sum(pitcher_data$details.isInPlay == TRUE, na.rm = T)
  return(bip_count)
}

calculate_hitter_bip_mnl <- function(hitter_data) {
  # Returns total Balls In Play for a hitter
  bip_count <- sum(hitter_data$details.isInPlay == TRUE, na.rm = T)
  return(bip_count)
}

# =============================================================================
# Pitcher Overall & Pitch-Level Performance Metrics
# ============================================================================

calculate_pitcher_overall_perf <- function(pitcher_data) {
  # Returns overall pitcher performance metrics
  # Based on shiny_aggs.R PITCHER OVERALL PERF section
  
  pitcher_data <- pitcher_data %>%
    mutate(isZone = ifelse(plate_z >= sz_bot & 
                            plate_z <= sz_top & 
                            plate_x >= -0.708 & plate_x <= 0.708, TRUE, FALSE))
  
  metrics <- list(
    pitches = nrow(pitcher_data),
    bip = sum(pitcher_data$description == "hit_into_play", na.rm = TRUE),
    swing_pct = round(100 * sum(pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                                  "swinging_strike_blocked", "foul_tip", "foul_bunt"), na.rm = TRUE) / nrow(pitcher_data), 1),
    strike_pct = round(100 * sum(pitcher_data$description %in% c("called_strike", "foul", "hit_into_play", "swinging_strike",
                                                                   "swinging_strike_blocked", "foul_bunt"), na.rm = TRUE) / nrow(pitcher_data), 1),
    zone_pct = round(100 * sum(pitcher_data$isZone == TRUE, na.rm = TRUE) / nrow(pitcher_data), 1),
    chase_pct = round(100 * sum(pitcher_data$isZone == FALSE & pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                                                                 "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt"), na.rm = TRUE) / 
                        sum(pitcher_data$isZone == FALSE, na.rm = TRUE), 1),
    cs_pct = round(100 * sum(pitcher_data$description == "called_strike", na.rm = TRUE) / nrow(pitcher_data), 1),
    foul_pct = round(100 * sum(pitcher_data$description == "foul", na.rm = TRUE) / 
                      sum(pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                           "swinging_strike_blocked", "foul_tip", "foul_bunt"), na.rm = TRUE), 1),
    whiff_pct = round(100 * sum(pitcher_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip"), na.rm = TRUE) / 
                       sum(pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                            "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt"), na.rm = TRUE), 1),
    iz_whiff = round(100 * sum(pitcher_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip") & pitcher_data$isZone == TRUE, na.rm = TRUE) / 
                      sum(pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                           "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt") & pitcher_data$isZone == TRUE, na.rm = TRUE), 1),
    oz_whiff = round(100 * sum(pitcher_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip") & pitcher_data$isZone == FALSE, na.rm = TRUE) / 
                      sum(pitcher_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                           "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt") & pitcher_data$isZone == FALSE, na.rm = TRUE), 1),
    gb_pct = round(100 * sum(pitcher_data$bb_type == "ground_ball" & pitcher_data$description == "hit_into_play", na.rm = TRUE) / 
                    sum(pitcher_data$description == "hit_into_play", na.rm = TRUE), 1),
    hh_pct = round(100 * sum(pitcher_data$launch_speed >= 95 & pitcher_data$description == "hit_into_play", na.rm = TRUE) / 
                    sum(pitcher_data$description == "hit_into_play", na.rm = TRUE), 1)
  )
  
  return(metrics)
}

calculate_pitcher_pitch_perf <- function(pitcher_data) {
  # Returns pitch-level performance metrics (one row per pitch type)
  # Based on shiny_aggs.R PITCHER PITCH LEVEL PERF section
  
  pitcher_data <- pitcher_data %>%
    mutate(isZone = ifelse(plate_z >= sz_bot & 
                            plate_z <= sz_top & 
                            plate_x >= -0.708 & plate_x <= 0.708, TRUE, FALSE))
  
  pitch_types <- unique(pitcher_data$pitch_name)
  
  pitch_perf <- map_df(pitch_types, function(pt) {
    pt_data <- pitcher_data %>% filter(pitch_name == pt)
    
    tibble(
      pitch_name = pt,
      pitches = nrow(pt_data),
      bip = sum(pt_data$description == "hit_into_play", na.rm = TRUE),
      swing_pct = round(100 * sum(pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                               "swinging_strike_blocked", "foul_tip", "foul_bunt"), na.rm = TRUE) / nrow(pt_data), 1),
      strike_pct = round(100 * sum(pt_data$description %in% c("called_strike", "foul", "hit_into_play", "swinging_strike",
                                                                "swinging_strike_blocked", "foul_bunt"), na.rm = TRUE) / nrow(pt_data), 1),
      zone_pct = round(100 * sum(pt_data$isZone == TRUE, na.rm = TRUE) / nrow(pt_data), 1),
      chase_pct = round(100 * sum(pt_data$isZone == FALSE & pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                                                          "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt"), na.rm = TRUE) / 
                         sum(pt_data$isZone == FALSE, na.rm = TRUE), 1),
      cs_pct = round(100 * sum(pt_data$description == "called_strike", na.rm = TRUE) / nrow(pt_data), 1),
      foul_pct = round(100 * sum(pt_data$description == "foul", na.rm = TRUE) / 
                        sum(pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                         "swinging_strike_blocked", "foul_tip", "foul_bunt"), na.rm = TRUE), 1),
      whiff_pct = round(100 * sum(pt_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip"), na.rm = TRUE) / 
                         sum(pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                          "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt"), na.rm = TRUE), 1),
      iz_whiff = round(100 * sum(pt_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip") & pt_data$isZone == TRUE, na.rm = TRUE) / 
                        sum(pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                         "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt") & pt_data$isZone == TRUE, na.rm = TRUE), 1),
      oz_whiff = round(100 * sum(pt_data$description %in% c("swinging_strike", "swinging_strike_blocked", "foul_tip") & pt_data$isZone == FALSE, na.rm = TRUE) / 
                        sum(pt_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                         "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt") & pt_data$isZone == FALSE, na.rm = TRUE), 1),
      gb_pct = round(100 * sum(pt_data$bb_type == "ground_ball" & pt_data$description == "hit_into_play", na.rm = TRUE) / 
                      sum(pt_data$description == "hit_into_play", na.rm = TRUE), 1),
      hh_pct = round(100 * sum(pt_data$launch_speed >= 95 & pt_data$description == "hit_into_play", na.rm = TRUE) / 
                      sum(pt_data$description == "hit_into_play", na.rm = TRUE), 1)
    )
  }) %>%
    arrange(desc(pitches))
  
  return(pitch_perf)
}

# =============================================================================
# Batter Overall, Zone, & Profile Performance Metrics
# =============================================================================

calculate_batter_overall_perf <- function(batter_data) {
  # Returns overall batter performance metrics
  # Based on shiny_aggs.R BATTER PERF OVR section
  
  batter_data <- batter_data %>%
    mutate(isZone = ifelse(plate_z >= sz_bot & 
                            plate_z <= sz_top & 
                            plate_x >= -0.708 & plate_x <= 0.708, TRUE, FALSE),
           sweet_spot = ifelse(launch_angle >= 8 & launch_angle <= 32, 1, 0))
  
  metrics <- list(
    swing_pct = round(100 * sum(batter_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                                 "swinging_strike_blocked", "foul_tip", "foul_bunt"), na.rm = TRUE) / nrow(batter_data), 1),
    chase_pct = round(100 * sum(batter_data$isZone == FALSE & batter_data$description %in% c("foul", "hit_into_play", "swinging_strike",
                                                                                               "swinging_strike_blocked", "foul_tip", "bunt_foul_tip", "missed_bunt", "foul_bunt"), na.rm = TRUE) / 
                       sum(batter_data$isZone == FALSE, na.rm = TRUE), 1),
    foul_pct = round(100*(sum(batter_data$description == "foul",na.rm = T)/sum(batter_data$description %in% c("foul","hit_into_play",
                                                                                                   "swinging_strike",
                                                                                                   "swinging_strike_blocked",
                                                                                                   "foul_tip","foul_bunt"),na.rm=T)),1),
    whiff_pct = round(100*(sum(batter_data$description %in% c("swinging_strike","swinging_strike_blocked",
                                                               "foul_tip"),na.rm = T)/
                                          sum(batter_data$description %in% c("foul","hit_into_play","swinging_strike",
                                                                 "swinging_strike_blocked","foul_tip",
                                                                 "bunt_foul_tip","missed_bunt","foul_bunt"),
                                              na.rm = T)),1),
    iz_whiff = round(100*(sum(batter_data$description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip") & batter_data$isZone == TRUE,na.rm = T)/
                                            sum(batter_data$description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt")
                                                & batter_data$isZone == TRUE,na.rm = T)),1),
    oz_whiff = round(100*(sum(batter_data$description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip")& batter_data$isZone == FALSE,na.rm = T)/
                                            sum(batter_data$description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt") &
                                                  batter_data$isZone == FALSE,na.rm = T)),1),
    bip = sum(batter_data$description == "hit_into_play", na.rm = TRUE),
    gb_pct = round(100 * sum(batter_data$bb_type == "ground_ball" & batter_data$description == "hit_into_play", na.rm = TRUE) / 
                    sum(batter_data$description == "hit_into_play", na.rm = TRUE), 1),
    barrel_pct = round(100 * sum(batter_data$launch_speed >= 92 & batter_data$launch_angle >= 26 & batter_data$launch_angle <= 30 & batter_data$description == "hit_into_play", na.rm = TRUE) / 
                        sum(batter_data$description == "hit_into_play", na.rm = TRUE), 1),
    hh_pct = round(100 * sum(batter_data$launch_speed >= 95 & batter_data$description == "hit_into_play", na.rm = TRUE) / 
                    sum(batter_data$description == "hit_into_play", na.rm = TRUE), 1),
    slg = round(((1*sum(batter_data$events == "single" & batter_data$description == "hit_into_play",na.rm = T))+(2*sum(batter_data$events == "double" & batter_data$description == "hit_into_play",na.rm = T))+
                                      (3*sum(batter_data$events == "triple" & batter_data$description == "hit_into_play",na.rm = T))+
                                      (4*sum(batter_data$events == "home_run" & batter_data$description == "hit_into_play",na.rm = T)))/sum(batter_data$description == "hit_into_play", na.rm = T),3),
    swspt_pct = round(100*(sum(batter_data$sweet_spot & batter_data$description == "hit_into_play", na.rm = T)/sum(batter_data$description == "hit_into_play")),1)
  )
  
  return(metrics)
}

calculate_batter_zone_perf <- function(batter_data) {
  # Returns zone-level batter performance (vertical and horizontal zones)
  # Based on shiny_aggs.R BATTER PERF ZONE sections
  
  batter_data_v <- batter_data %>%
    mutate(isZone = ifelse(plate_z >= sz_bot & 
                            plate_z <= sz_top & 
                            plate_x >= -0.708 & plate_x <= 0.708, TRUE, FALSE),
          third_loc = ifelse(zone %in% c(1,2,3),"high",
                                  ifelse(zone %in% c(4,5,6),"mid (v)",
                                         ifelse(zone %in% c(7,8,9),"low","else"))),
           sweet_spot = ifelse(launch_angle >= 8 & launch_angle <= 32, 1, 0)) %>%
           group_by(third_loc) %>%
        summarise(`BIP` = sum(description == "hit_into_play",na.rm=T),
                  `Swing%` = round(100*(sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                               "swinging_strike_blocked","foul_tip","foul_bunt"),na.rm=T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & 
                                              (description %in% c("foul","hit_into_play","swinging_strike",
                                                                  "swinging_strike_blocked","foul_tip",
                                                                  "bunt_foul_tip","missed_bunt","foul_bunt")), na.rm = T)/
                                          sum(isZone == FALSE, na.rm = T)),1),
                  `Foul%` = round(100*(sum(description == "foul",na.rm = T)/sum(description %in% c("foul","hit_into_play",
                                                                                                   "swinging_strike",
                                                                                                   "swinging_strike_blocked",
                                                                                                   "foul_tip","foul_bunt"),na.rm=T)),1),
                  `Whiff%` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                               "foul_tip"),na.rm = T)/
                                          sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                 "swinging_strike_blocked","foul_tip",
                                                                 "bunt_foul_tip","missed_bunt","foul_bunt"),
                                              na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip") & isZone == TRUE,na.rm = T)/
                                            sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt")
                                                & isZone == TRUE,na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip")& isZone == FALSE,na.rm = T)/
                                            sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt") &
                                                  isZone == FALSE,na.rm = T)),1),
                  `GB%` = round(100*(sum(bb_type == "ground_ball" & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play",na.rm = T)),1),
                  `HH%` = round(100*(sum(launch_speed >= 95 & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play", na.rm = T)),1),
                  `SLGcon` = round(((1*sum(events == "single" & description == "hit_into_play",na.rm = T))+(2*sum(events == "double" & description == "hit_into_play",na.rm = T))+
                                      (3*sum(events == "triple" & description == "hit_into_play",na.rm = T))+
                                      (4*sum(events == "home_run" & description == "hit_into_play",na.rm = T)))/sum(description == "hit_into_play", na.rm = T),3),
                  `Sweet Spot%` = round(100*(sum(sweet_spot & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play")),1)) %>%
        rename(`Location` = third_loc)

        batter_data_h <- batter_data %>%
    mutate(isZone = ifelse(plate_z >= sz_bot & 
                            plate_z <= sz_top & 
                            plate_x >= -0.708 & plate_x <= 0.708, TRUE, FALSE),
          third_loc = ifelse(zone %in% c(3,6,9) & stand == "R","out",
                                  ifelse(zone %in% c(3,6,9) & stand == "L","in",
                                         ifelse(zone %in% c(2,5,8),"mid (h)",
                                                ifelse(zone %in% c(1,4,7) & stand == "R","in",
                                                       ifelse(zone %in% c(1,4,7) & stand == "L","out","else"))))),
           sweet_spot = ifelse(launch_angle >= 8 & launch_angle <= 32, 1, 0)) %>%
           group_by(third_loc) %>%
        summarise(`BIP` = sum(description == "hit_into_play",na.rm=T),
                  `Swing%` = round(100*(sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                               "swinging_strike_blocked","foul_tip","foul_bunt"),na.rm=T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & 
                                              (description %in% c("foul","hit_into_play","swinging_strike",
                                                                  "swinging_strike_blocked","foul_tip",
                                                                  "bunt_foul_tip","missed_bunt","foul_bunt")), na.rm = T)/
                                          sum(isZone == FALSE, na.rm = T)),1),
                  `Foul%` = round(100*(sum(description == "foul",na.rm = T)/sum(description %in% c("foul","hit_into_play",
                                                                                                   "swinging_strike",
                                                                                                   "swinging_strike_blocked",
                                                                                                   "foul_tip","foul_bunt"),na.rm=T)),1),
                  `Whiff%` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                               "foul_tip"),na.rm = T)/
                                          sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                 "swinging_strike_blocked","foul_tip",
                                                                 "bunt_foul_tip","missed_bunt","foul_bunt"),
                                              na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip") & isZone == TRUE,na.rm = T)/
                                            sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt")
                                                & isZone == TRUE,na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(description %in% c("swinging_strike","swinging_strike_blocked",
                                                                 "foul_tip")& isZone == FALSE,na.rm = T)/
                                            sum(description %in% c("foul","hit_into_play","swinging_strike",
                                                                   "swinging_strike_blocked","foul_tip",
                                                                   "bunt_foul_tip","missed_bunt","foul_bunt") &
                                                  isZone == FALSE,na.rm = T)),1),
                  `GB%` = round(100*(sum(bb_type == "ground_ball" & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play",na.rm = T)),1),
                  `HH%` = round(100*(sum(launch_speed >= 95 & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play", na.rm = T)),1),
                  `SLGcon` = round(((1*sum(events == "single" & description == "hit_into_play",na.rm = T))+(2*sum(events == "double" & description == "hit_into_play",na.rm = T))+
                                      (3*sum(events == "triple" & description == "hit_into_play",na.rm = T))+
                                      (4*sum(events == "home_run" & description == "hit_into_play",na.rm = T)))/sum(description == "hit_into_play", na.rm = T),3),
                  `Sweet Spot%` = round(100*(sum(sweet_spot & description == "hit_into_play", na.rm = T)/sum(description == "hit_into_play")),1)) %>%
        rename(`Location` = third_loc) %>%
        filter(`Location` != "else")

        zone_perf <- rbind(batter_data_v,batter_data_h)
  
  
  return(zone_perf)
}

calculate_batter_profile <- function(batter_data) {
  # Returns batter profile metrics (swing quality and mechanics)
  # Based on shiny_aggs.R BATTER PROFILE section
  
  batter_data <- batter_data %>%
    filter(description == "hit_into_play", !str_detect(des, "bunt")) %>%
    mutate(sweet_spot = ifelse(launch_angle >= 8 & launch_angle <= 32, 1, 0),
    spray_angle = round(
           (atan(
             (hc_x-125.42)/(198.27-hc_y)
           )*180/pi*.75)
           ,1)
    ) %>%
    mutate(
      bip_dir = ifelse(spray_angle > 15 & stand == "R", "oppo",
                                 ifelse(spray_angle < -15 & stand == "R", "pull",
                                        ifelse(spray_angle > 15 & stand == "L", "pull",
                                               ifelse(spray_angle < -15 & stand == "L", "oppo",
                                                      ifelse(spray_angle >= -15 & spray_angle <= 15, "middle",NA)))))
    )
  
  if (nrow(batter_data) == 0) {
    return(NULL)
  }
  
  metrics <- list(
    bbe = nrow(batter_data),
    avg_la = round(mean(batter_data$launch_angle, na.rm = TRUE), 1),
    la_std_dev = round(sd(batter_data$launch_angle, na.rm = TRUE), 1),
    sweet_spot_pct = round(100 * sum(batter_data$sweet_spot, na.rm = TRUE) / nrow(batter_data), 1),
    hh_la = round(mean(batter_data$launch_angle[batter_data$launch_speed >= 95], na.rm = TRUE), 1),
    oppo_fb_pct = round(100*(sum(batter_data$bb_type == "fly_ball" & batter_data$bip_dir == "oppo",na.rm = T)/sum(batter_data$bb_type == "fly_ball",na.rm = T)),1),
    oppo_fb_ev = round(mean(batter_data$launch_speed[batter_data$bb_type == "fly_ball" & batter_data$bip_dir == "oppo"],na.rm = T),1),
    high_aa_pct = round(100 * sum(batter_data$attack_angle >= 14 & !month(batter_data$game_date) %in% c(6,7), na.rm = TRUE) / 
                         sum(!is.na(batter_data$attack_angle) & !month(batter_data$game_date) %in% c(6,7)), 1)
  )
  
  return(metrics)
}

# =============================================================================
# MiLB Metric Calculations (Minor League Data)
# =============================================================================

calculate_pitcher_overall_perf_milb <- function(pitcher_data) {
  # Calculates pitcher overall performance from MiLB data
  # Using field names from normalized MiLB data (details.call.description, etc.)
  
  if (nrow(pitcher_data) == 0) {
    return(NULL)
  }
  
  # Calculate zone
  pitcher_data <- pitcher_data %>%
    mutate(isZone = ifelse(pitchData.coordinates.pZ >= pitchData.strikeZoneBottom & 
                                 pitchData.coordinates.pZ <= pitchData.strikeZoneTop & 
                                 pitchData.coordinates.pX >= -0.708 & pitchData.coordinates.pX <= 0.708,TRUE,FALSE)) %>%
        summarise(details.type.description = "Overall",
                  `Pitches`= n(),
                  `BIP` = sum(details.isInPlay == TRUE, na.rm = T),
                  `Swing%` = round(100*(sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                              "Missed Bunt","Foul Bunt"), na.rm = T)/n()),1),
                  `Strike%` = round(100*(sum( details.call.description %in% c("In play, out(s)","Foul Tip","In play, run(s)",
                                                                              "Foul Bunt","Called Strike","In play, no out",
                                                                              "Missed Bunt","Swinging Strike","Swinging Strike (Blocked)",
                                                                              "Foul"),na.rm=T)/n()),1),
                  `Zone%` = round(100*(sum(isZone == TRUE, na.rm = T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & (! details.call.description %in% c("Ball","Called Strike",
                                                                                                 "Ball In Dirt","Hit By Pitch",
                                                                                                 "Missed Bunt","Foul Bunt")), na.rm = T)/
                                          sum(isZone == FALSE, na.rm = T)),1),
                  `CS%` = round(100*(sum(details.description == "Called Strike", na.rm = T)/n()),1),
                  `Foul%` = round(100*(sum(details.call.description == "Foul",na.rm = T)/sum(! details.call.description %in% c("Ball",
                                                                                                                               "Called Strike","Ball In Dirt",
                                                                                                                               "Hit By Pitch",
                                                                                                                               "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `Whiff%` = round(100*(sum(details.call.description %in% c("Swinging Strike"), na.rm = T)/
                                          sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == TRUE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == TRUE, na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == FALSE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == FALSE, na.rm = T)),1),
                  `GB%` = round(100*(sum(hitData.trajectory == "ground_ball", na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `HH%` = round(100*(sum(hitData.launchSpeed >= 95, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1)) 
  
  metrics <- list(
    pitches = pitcher_data$`Pitches`,
    bip = pitcher_data$`BIP`,
    swing_pct = pitcher_data$`Swing%`,
    strike_pct = pitcher_data$`Strike%`,
    zone_pct = pitcher_data$`Zone%`,
    chase_pct = pitcher_data$`Chase%`,
    cs_pct = pitcher_data$`CS%`,
    foul_pct = pitcher_data$`Foul%`,
    whiff_pct = pitcher_data$`Whiff%`,
    iz_whiff = pitcher_data$`IZ Whiff`,
    oz_whiff = pitcher_data$`OZ Whiff`,
    gb_pct = pitcher_data$`GB%`,
    hh_pct = pitcher_data$`HH%`
  )
  
  return(metrics)
}

calculate_pitcher_pitch_perf_milb <- function(pitcher_data) {
  # Calculates pitcher pitch-level performance from MiLB data
  
  if (nrow(pitcher_data) == 0) {
    return(tibble())
  }
  
  pitch_perf <- pitcher_data %>%
    mutate(isZone = ifelse(pitchData.coordinates.pZ >= pitchData.strikeZoneBottom & 
                                 pitchData.coordinates.pZ <= pitchData.strikeZoneTop & 
                                 pitchData.coordinates.pX >= -0.708 & pitchData.coordinates.pX <= 0.708,TRUE,FALSE),
          details.type.description = ifelse(details.type.description == "Four-Seam Fastball","4-Seam Fastball",
          ifelse(details.type.description == "Splitter","Split-Finger",details.type.description))) %>%
        group_by(details.type.description) %>%
        summarise(`Pitches`= n(),
                  `BIP` = sum(details.isInPlay == TRUE, na.rm = T),
                  `Swing%` = round(100*(sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                   "Missed Bunt","Foul Bunt"), na.rm = T)/n()),1),
                  `Strike%` = round(100*(sum( details.call.description %in% c("In play, out(s)","Foul Tip","In play, run(s)",
                                                                              "Foul Bunt","Called Strike","In play, no out",
                                                                              "Missed Bunt","Swinging Strike","Swinging Strike (Blocked)",
                                                                              "Foul"),na.rm=T)/n()),1),
                  `Zone%` = round(100*(sum(isZone == TRUE, na.rm = T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & (! details.call.description %in% c("Ball","Called Strike",
                                                                                      "Ball In Dirt","Hit By Pitch",
                                                                                      "Missed Bunt","Foul Bunt")), na.rm = T)/
                    sum(isZone == FALSE, na.rm = T)),1),
                  `CS%` = round(100*(sum(details.description == "Called Strike", na.rm = T)/n()),1),
                  `Foul%` = round(100*(sum(details.call.description == "Foul",na.rm = T)/sum(! details.call.description %in% c("Ball",
                                                                                                                               "Called Strike","Ball In Dirt",
                                                                                                                               "Hit By Pitch",
                                                                                                                               "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `Whiff%` = round(100*(sum(details.call.description %in% c("Swinging Strike"), na.rm = T)/
                    sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                          "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == TRUE, na.rm = T)/
                    sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                           "Missed Bunt","Foul Bunt")) & isZone == TRUE, na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == FALSE, na.rm = T)/
                    sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                           "Missed Bunt","Foul Bunt")) & isZone == FALSE, na.rm = T)),1),
                  `GB%` = round(100*(sum(hitData.trajectory == "ground_ball", na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `HH%` = round(100*(sum(hitData.launchSpeed >= 95, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1))
  
  return(pitch_perf)
}

calculate_batter_overall_perf_milb <- function(batter_data) {
  # Calculates batter overall performance from MiLB data
  
  if (nrow(batter_data) == 0) {
    return(NULL)
  }
  
  batter_data <- batter_data %>%
    mutate(isZone = ifelse(pitchData.coordinates.pZ >= pitchData.strikeZoneBottom & 
                               pitchData.coordinates.pZ <= pitchData.strikeZoneTop & 
                               pitchData.coordinates.pX >= -0.708 & pitchData.coordinates.pX <= 0.708,TRUE,FALSE),
             sweet_spot = ifelse(hitData.launchAngle >= 8 & hitData.launchAngle <= 32,1,0)) %>%
      summarise(`BIP` = sum(details.isInPlay == TRUE, na.rm = T),
                `Swing%` = round(100*(sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                 "Missed Bunt","Foul Bunt"), na.rm = T)/n()),1),
                `Chase%` = round(100*(sum(isZone == FALSE & (! details.call.description %in% c("Ball","Called Strike",
                                                                                    "Ball In Dirt","Hit By Pitch",
                                                                                    "Missed Bunt","Foul Bunt")), na.rm = T)/
                  sum(isZone == FALSE, na.rm = T)),1),
                `Foul%` = round(100*(sum(details.call.description == "Foul",na.rm = T)/sum(! details.call.description %in% c("Ball",
                                                                                                                             "Called Strike","Ball In Dirt",
                                                                                                                             "Hit By Pitch",
                                                                                                                             "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                `Whiff%` = round(100*(sum(details.call.description %in% c("Swinging Strike"), na.rm = T)/
                  sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                        "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                `IZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == TRUE, na.rm = T)/
                  sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                         "Missed Bunt","Foul Bunt")) & isZone == TRUE, na.rm = T)),1),
                `OZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == FALSE, na.rm = T)/
                  sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                         "Missed Bunt","Foul Bunt")) & isZone == FALSE, na.rm = T)),1),
                `GB%` = round(100*(sum(hitData.trajectory == "ground_ball", na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                `HH%` = round(100*(sum(hitData.launchSpeed >= 95, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                `SLGcon` = round(((1*sum(result.eventType == "single" & details.isInPlay == TRUE,na.rm = T))+(2*sum(result.eventType == "double" & details.isInPlay == TRUE,na.rm = T))+
                                    (3*sum(result.eventType == "triple" & details.isInPlay == TRUE,na.rm = T))+(4*sum(result.eventType == "home_run" & details.isInPlay == TRUE,na.rm = T)))/
                                   sum(details.isInPlay == TRUE, na.rm = T),3),
                `Sweet Spot%` = round(100*(sum(sweet_spot & details.isInPlay == TRUE, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1)) 
  
  metrics <- list(
    bip = batter_data$`BIP`,
    swing_pct = batter_data$`Swing%`,
    chase_pct = batter_data$`Chase%`,
    foul_pct = batter_data$`Foul%`,
    whiff_pct = batter_data$`Whiff%`,
    iz_whiff = batter_data$`IZ Whiff`,
    oz_whiff = batter_data$`OZ Whiff`,
    gb_pct = batter_data$`GB%`,
    hh_pct = batter_data$`HH%`,
    slg = batter_data$`SLGcon`,
    swspt_pct = batter_data$`Sweet Spot%`
  )
  
  return(metrics)
}

calculate_batter_zone_perf_milb <- function(batter_data) {
  # Calculates batter zone-level performance from MiLB data
  
  if (nrow(batter_data) == 0) {
    return(tibble())
  }
  
  batter_data_v <- batter_data %>%
    mutate(isZone = ifelse(pitchData.coordinates.pZ >= pitchData.strikeZoneBottom & 
                                 pitchData.coordinates.pZ <= pitchData.strikeZoneTop & 
                                 pitchData.coordinates.pX >= -0.708 & pitchData.coordinates.pX <= 0.708,TRUE,FALSE),
               third_loc = ifelse(pitchData.zone %in% c(1,2,3),"high",
                              ifelse(pitchData.zone %in% c(4,5,6),"mid (v)",
                                     ifelse(pitchData.zone %in% c(7,8,9),"low","else"))),
               sweet_spot = ifelse(hitData.launchAngle >= 8 & hitData.launchAngle <= 32,1,0)) %>%
        group_by(third_loc) %>%
        summarise(`BIP` = sum(details.isInPlay == TRUE, na.rm = T),
                  `Swing%` = round(100*(sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                              "Missed Bunt","Foul Bunt"), na.rm = T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & (! details.call.description %in% c("Ball","Called Strike",
                                                                                                 "Ball In Dirt","Hit By Pitch",
                                                                                                 "Missed Bunt","Foul Bunt")), na.rm = T)/
                                          sum(isZone == FALSE, na.rm = T)),1),
                  `Foul%` = round(100*(sum(details.call.description == "Foul",na.rm = T)/sum(! details.call.description %in% c("Ball",
                                                                                                                               "Called Strike","Ball In Dirt",
                                                                                                                               "Hit By Pitch",
                                                                                                                               "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `Whiff%` = round(100*(sum(details.call.description %in% c("Swinging Strike"), na.rm = T)/
                                          sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == TRUE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == TRUE, na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == FALSE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == FALSE, na.rm = T)),1),
                  `GB%` = round(100*(sum(hitData.trajectory == "ground_ball", na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `HH%` = round(100*(sum(hitData.launchSpeed >= 95, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `SLGcon` = round(((1*sum(result.eventType == "single" & details.isInPlay == TRUE,na.rm = T))+(2*sum(result.eventType == "double" & details.isInPlay == TRUE,na.rm = T))+
                                      (3*sum(result.eventType == "triple" & details.isInPlay == TRUE,na.rm = T))+(4*sum(result.eventType == "home_run" & details.isInPlay == TRUE,na.rm = T)))/
                                     sum(details.isInPlay == TRUE, na.rm = T),3),
                  `Sweet Spot%` = round(100*(sum(sweet_spot & details.isInPlay == TRUE, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1))%>%
        rename(`Location` = third_loc)

        batter_data_h <- batter_data %>%
    mutate(isZone = ifelse(pitchData.coordinates.pZ >= pitchData.strikeZoneBottom & 
                                 pitchData.coordinates.pZ <= pitchData.strikeZoneTop & 
                                 pitchData.coordinates.pX >= -0.708 & pitchData.coordinates.pX <= 0.708,TRUE,FALSE),
               third_loc = ifelse(pitchData.zone %in% c(3,6,9) & matchup.batSide.code == "R","out",
                                  ifelse(pitchData.zone %in% c(3,6,9) & matchup.batSide.code == "L","in",
                                         ifelse(pitchData.zone %in% c(2,5,8),"mid (h)",
                                                ifelse(pitchData.zone %in% c(1,4,7) & matchup.batSide.code == "R","in",
                                                       ifelse(pitchData.zone %in% c(1,4,7) & matchup.batSide.code == "L","out","else"))))),
               sweet_spot = ifelse(hitData.launchAngle >= 8 & hitData.launchAngle <= 32,1,0)) %>%
        group_by(third_loc) %>%
        summarise(`BIP` = sum(details.isInPlay == TRUE, na.rm = T),
                  `Swing%` = round(100*(sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                              "Missed Bunt","Foul Bunt"), na.rm = T)/n()),1),
                  `Chase%` = round(100*(sum(isZone == FALSE & (! details.call.description %in% c("Ball","Called Strike",
                                                                                                 "Ball In Dirt","Hit By Pitch",
                                                                                                 "Missed Bunt","Foul Bunt")), na.rm = T)/
                                          sum(isZone == FALSE, na.rm = T)),1),
                  `Foul%` = round(100*(sum(details.call.description == "Foul",na.rm = T)/sum(! details.call.description %in% c("Ball",
                                                                                                                               "Called Strike","Ball In Dirt",
                                                                                                                               "Hit By Pitch",
                                                                                                                               "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `Whiff%` = round(100*(sum(details.call.description %in% c("Swinging Strike"), na.rm = T)/
                                          sum(! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                "Missed Bunt","Foul Bunt"), na.rm = T)),1),
                  `IZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == TRUE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == TRUE, na.rm = T)),1),
                  `OZ Whiff` = round(100*(sum(details.call.description %in% c("Swinging Strike") & isZone == FALSE, na.rm = T)/
                                            sum((! details.call.description %in% c("Ball","Called Strike","Ball In Dirt","Hit By Pitch",
                                                                                   "Missed Bunt","Foul Bunt")) & isZone == FALSE, na.rm = T)),1),
                  `GB%` = round(100*(sum(hitData.trajectory == "ground_ball", na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `HH%` = round(100*(sum(hitData.launchSpeed >= 95, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1),
                  `SLGcon` = round(((1*sum(result.eventType == "single" & details.isInPlay == TRUE,na.rm = T))+(2*sum(result.eventType == "double" & details.isInPlay == TRUE,na.rm = T))+
                                      (3*sum(result.eventType == "triple" & details.isInPlay == TRUE,na.rm = T))+(4*sum(result.eventType == "home_run" & details.isInPlay == TRUE,na.rm = T)))/
                                     sum(details.isInPlay == TRUE, na.rm = T),3),
                  `Sweet Spot%` = round(100*(sum(sweet_spot & details.isInPlay == TRUE, na.rm = T)/sum(details.isInPlay == TRUE, na.rm = T)),1)) %>%
        rename(`Location` = third_loc) %>%
        filter(`Location` != "else")

        zone_perf <- rbind(batter_data_v,batter_data_h)
  
  return(zone_perf)
}

calculate_batter_profile_milb <- function(batter_data) {
  # Calculates batter profile/swing quality metrics from MiLB data
  
  if (nrow(batter_data) == 0) {
    return(NULL)
  }

  words_to_remove <- c("bunt")
  
  # Remove bunts and filter to balls in play with trajectory
  batter_data <- batter_data %>%
    filter(!is.na(hitData.trajectory),details.isInPlay == TRUE, !str_detect(result.description, paste(words_to_remove, collapse = "|"))) %>%
      mutate(spray_angle = round(
        (atan(
          (hitData.coordinates.coordX-125.42)/(198.27-hitData.coordinates.coordY)
        )*180/pi*.75)
        ,1)) %>%
      mutate(sweet_spot = ifelse(hitData.launchAngle >= 8 & hitData.launchAngle <= 32,1,0),
             bip_dir = ifelse(spray_angle > 15 & matchup.batSide.code == "R", "oppo",
                              ifelse(spray_angle < -15 & matchup.batSide.code == "R", "pull",
                                     ifelse(spray_angle > 15 & matchup.batSide.code == "L", "pull",
                                            ifelse(spray_angle < -15 & matchup.batSide.code == "L", "oppo",
                                                   ifelse(spray_angle >= -15 & spray_angle <= 15, "middle",NA)))))) %>%
      group_by(matchup.batter.fullName,home_level_name) %>%
      summarise(`BBE` = n(),
                `Avg LA` = round(mean(hitData.launchAngle, na.rm = T),1),
                `LA Std Dev` = round(sd(hitData.launchAngle, na.rm = T),1),
                `Sweet Spot%` = round(100*(sum(sweet_spot, na.rm = T)/n()),1),
                `HH LA` = round(mean(hitData.launchAngle[hitData.launchSpeed >= 95], na.rm = T),1),
                `Oppo FB%` = round(100*(sum(hitData.trajectory == "fly_ball" & bip_dir == "oppo",na.rm = T)/sum(hitData.trajectory == "fly_ball",na.rm = T)),1),
                `Oppo FB EV` = round(mean(hitData.launchSpeed[hitData.trajectory == "fly_ball" & bip_dir == "oppo"],na.rm = T),1),
                `High AA%` = 0)
  
  metrics <- list(
    bbe = batter_data$`BBE`,
    avg_la = batter_data$`Avg LA`,
    la_std_dev = batter_data$`LA Std Dev`,
    sweet_spot_pct = batter_data$`Sweet Spot%`,
    hh_la = batter_data$`HH LA`,
    oppo_fb_pct = batter_data$`Oppo FB%`,
    oppo_fb_ev = batter_data$`Oppo FB EV`,
    high_aa_pct = 0  # Placeholder - MiLB data may not have attack angle
  )
  
  return(metrics)
}

# =============================================================================
# calculate_pitcher_arsenal_milb: Arsenal metrics by pitch type (MiLB)
# =============================================================================

calculate_pitcher_arsenal_milb <- function(pitcher_data) {
  # Calculates pitcher arsenal metrics (by pitch type) from MiLB data
  # Returns data frame with pitch type breakdown and metrics
  
  if (nrow(pitcher_data) == 0) {
    return(tibble())
  }
  
  arsenal <- pitcher_data %>%
    group_by(details.type.description) %>%
    summarise(
      Pitch = first(details.type.description),
      Usage = n(),
      `Avg Velo` = round(mean(pitchData.startSpeed, na.rm = TRUE), 1),
      `Velo Min` = round(min(pitchData.startSpeed, na.rm = TRUE), 1),
      `Velo Max` = round(max(pitchData.startSpeed, na.rm = TRUE), 1),
      `H-Break` = round(mean(pitchData.breaks.breakHorizontal, na.rm = TRUE), 1),
      `V-Break` = round(mean(pitchData.breaks.breakVerticalInduced, na.rm = TRUE), 1),
      `Spin Rate` = round(mean(pitchData.breaks.spinRate, na.rm = TRUE), 0),
      `Rel Side` = 0,  # Placeholder - MiLB data may not have release position
      `Rel Height` = 0,  # Placeholder - MiLB data may not have release position
      .groups = "drop"
    ) %>%
    arrange(desc(Usage)) %>%
    select(Pitch, Usage, `Avg Velo`, `Velo Min`, `Velo Max`, `H-Break`, `V-Break`, `Spin Rate`, `Rel Side`, `Rel Height`)
  
  return(arsenal)
}
