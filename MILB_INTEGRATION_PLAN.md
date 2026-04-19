# MiLB Integration Strategy: Methodology & Approach

## Part 1: How I Reverse-Engineered Your MLB Dataset

### 1. **Exploratory Analysis Phase**
I examined your existing codebase to understand:
- **Data structure**: Where raw data comes from (Statcast) and how it's formatted
- **Field naming conventions**: Column names in your data (e.g., `pitcher`, `batter`, `game_date`, `plate_z`, `launch_speed`)
- **Aggregation logic**: How you calculate metrics (e.g., swing% = (non-balls/non-called-strikes) / total pitches)
- **Output format**: What tracking logs and reports look like

### 2. **Tracing the Workflow**
I mapped the pipeline:
```
Raw Data (Statcast) 
  ↓
Metric Calculations (calculate_pitcher_overall_perf, etc.)
  ↓
Tracking System (pitcher_tracking_log.csv, hitter_tracking_log.csv)
  ↓
Report Generation (generate_pitcher_performance_report, etc.)
  ↓
Output (Markdown reports)
```

### 3. **Field Name Mapping**
For MLB data, I identified:
```r
# Pitcher ID fields
pitcher = pitcher ID (numeric)
pitcher_name = pitcher name (only available in data, not guaranteed)

# Batter ID fields  
batter = batter ID (numeric)
player_name = batter name (only in arsenal/performance reports, not in raw data)

# Game/Date fields
game_date = date of game (ISO format)

# Pitch details
pitch_type = pitch classification (FF, SL, etc.)
release_speed = pitch velocity
plate_x, plate_z = location at plate
launch_speed = exit velo
launch_angle = attack angle

# Strike zone definition
sz_top, sz_bot = individual batter strike zone bounds
```

### 4. **Metric Calculation Extraction**
I extracted the formula for each metric from your calculations:
- **Swing%**: `(pitches - balls - called strikes - etc.) / total pitches`
- **Zone%**: `pitches in zone / total pitches`
- **Chase%**: `swings outside zone / pitches outside zone`
- **Whiff%**: `swing and misses / swings`
- **IZ/OZ Whiff**: Whiff separated by zone (in/out)
- **GB%**: `ground balls / balls in play`
- **HH%**: `exit velo >= 95 / balls in play`

### 5. **Generalization for New Data Sources**
Key insight: **The calculations themselves don't change—only the field names change.**

I created a pattern:
1. **Rename MiLB fields to MLB field names** → Makes downstream code reusable
2. **Calculate same metrics using renamed fields** → Same aggregation logic
3. **Feed into same pipeline** → Reports generate identically

---

## Part 2: MiLB Field Mapping & Integration Strategy

### Data Source Differences

| Concept | MLB (Statcast) | MiLB (mnl_sc_25) | Action |
|---------|----------------|------------------|--------|
| **Pitcher ID** | `pitcher` | `matchup.pitcher.fullName` | Extract ID or use name directly |
| **Batter ID** | `batter` | `matchup.batter.fullName` | Extract ID or use name directly |
| **Pitcher Handedness** | `pitcher_hand` | `matchup.pitcher.pitchHand.code` | Keep as is (R/L) |
| **Batter Handedness** | `stand` | `matchup.batSide.code` | Keep as is (R/L) |
| **Game Date** | `game_date` | Need to extract from `game` object | Extract/create date field |
| **Level** | N/A (always MLB) | `home_level_name` | Add to tracking logs |
| **Pitch Type** | `pitch_type` | `details.type.description` | Rename to pitch_type |
| **Pitch Location X** | `plate_x` | `pitchData.coordinates.pX` | Rename to plate_x |
| **Pitch Location Z** | `plate_z` | `pitchData.coordinates.pZ` | Rename to plate_z |
| **Strike Zone Top** | `sz_top` | `pitchData.strikeZoneTop` | Rename to sz_top |
| **Strike Zone Bot** | `sz_bot` | `pitchData.strikeZoneBottom` | Rename to sz_bot |
| **Pitch Outcome** | `description` | `details.call.description` | Rename to description |
| **Pitch Type (S/X/B)** | `type` | `details.type.code` | Rename to type |
| **Exit Velocity** | `launch_speed` | `hitData.launchSpeed` | Rename to launch_speed |
| **Launch Angle** | `launch_angle` | `hitData.launchAngle` | Rename to launch_angle |
| **Batted Ball Type** | `bb_type` | `hitData.trajectory` | Values differ; create mapping |
| **Ball in Play** | `is_bip` (derived from events) | `details.isInPlay` | Rename to is_bip |
| **Result Event Type** | `result` | `result.eventType` | Keep both or map equivalents |

### Implementation Strategy

#### **Step 1: Data Normalization**
Create a function to standardize MiLB data to MLB field names:

```r
normalize_milb_data <- function(mnl_data) {
  mnl_data %>%
    mutate(
      # ID fields (use full names as IDs for now)
      pitcher = matchup.pitcher.fullName,
      batter = matchup.batter.fullName,
      pitcher_hand = matchup.pitcher.pitchHand.code,
      stand = matchup.batSide.code,
      
      # Location fields
      plate_x = pitchData.coordinates.pX,
      plate_z = pitchData.coordinates.pZ,
      sz_top = pitchData.strikeZoneTop,
      sz_bot = pitchData.strikeZoneBottom,
      
      # Pitch details
      pitch_type = details.type.description,
      type = details.type.code,  # S/X/B equivalent
      description = details.call.description,
      
      # Outcome fields
      is_bip = details.isInPlay,
      launch_speed = hitData.launchSpeed,
      launch_angle = hitData.launchAngle,
      bb_type = case_when(
        hitData.trajectory == "ground_ball" ~ "GB",
        hitData.trajectory == "fly_ball" ~ "FB",
        hitData.trajectory == "line_drive" ~ "LD",
        hitData.trajectory == "popup" ~ "PU",
        TRUE ~ NA_character_
      ),
      
      # Metadata
      game_date = extract_date_from_game(game),
      level = home_level_name,
      data_source = "MiLB"
    ) %>%
    select(pitcher, batter, pitcher_hand, stand, game_date, pitch_type, type, 
           description, plate_x, plate_z, sz_top, sz_bot, is_bip, launch_speed, 
           launch_angle, bb_type, level, data_source, everything())
}
```

#### **Step 2: Reuse Metric Calculations**
The existing functions in `calculate_metrics.R` can work with normalized MiLB data because they operate on standardized field names:

```r
# Same function works for both MLB and MiLB once data is normalized
mlb_overall_perf <- calculate_pitcher_overall_perf(mlb_data)
milb_overall_perf <- calculate_pitcher_overall_perf(normalized_milb_data)
```

#### **Step 3: Tracking Log Augmentation**
Add `level` column to existing tracking logs to distinguish MLB vs MiLB:

**pitcher_tracking_log.csv:**
```
pitcher_name, level, report_date, bip_count, pitch_count, status, notes
Max Scherzer, MLB, 2026-03-30, 150, 450, performance_reported, ""
John Doe, A+, 2026-03-30, 105, 320, performance_reported, ""
```

**hitter_tracking_log.csv:**
```
batter, level, report_date, bip_count, pa_count, status, notes
123456, MLB, 2026-03-30, 102, 250, reported, ""
654321, AA, 2026-03-30, 105, 180, reported, ""
```

#### **Step 4: Percentile Calculation with Mixed Leagues**
When calculating percentiles for MiLB players, rbind them with MLB supporting data:

```r
# For MiLB pitcher
calculate_pitcher_overall_percentiles <- function(pitcher_metrics, pitcher_id, level = NULL) {
  # Load supporting data (generated from MLB historical data)
  supporting_data <- read_csv("data/supporting/pitcher_overall_overall.csv", show_col_types = FALSE)
  
  # Create current player row (works for both MLB and MiLB)
  current_pitcher <- tibble(
    player_name = pitcher_id,
    level = level %||% "MLB",  # Add level field
    pitch_name = "Overall",
    Pitches = pitcher_metrics$pitches,
    # ... rest of metrics
  )
  
  # Combine (MiLB player ranked against MLB historical distribution)
  combined <- rbind(supporting_data, current_pitcher)
  
  # Calculate percentiles as normal
  percentiles <- combined %>%
    arrange(desc(`Swing%`)) %>%
    mutate(swing_rank = round(percent_rank(`Swing%`) * 100, 1)) %>%
    # ... etc
}
```

#### **Step 5: Report Generation Updates**
Update report generation to specify league:

```r
generate_pitcher_performance_report <- function(pitcher_data, pitcher_name, pitcher_id = NULL, level = "MLB") {
  # ... existing code ...
  
  # Pass level to percentile functions
  percentiles_overall <- calculate_pitcher_overall_percentiles(overall_perf, pitcher_id, level)
  
  # Add level context to report
  report_content <- paste0(
    "# Pitcher Performance Report (", level, "): ", pitcher_name, "\n\n",
    # ... rest of report
  )
}
```

---

## Part 3: Implementation Checklist

### Phase 1: Data Normalization
- [ ] Create `normalize_milb_data()` function in a new file or top of process_statcast.R
- [ ] Map all MiLB field names to MLB equivalents
- [ ] Handle date extraction from game object
- [ ] Test normalization with sample MiLB data

### Phase 2: Metric Calculation Compatibility
- [ ] Verify existing metric functions work with normalized MiLB data
- [ ] Test `calculate_pitcher_overall_perf()` with MiLB data
- [ ] Test `calculate_batter_overall_perf()` with MiLB data
- [ ] Validate output format matches expectations

### Phase 3: Tracking System Updates
- [ ] Add `level` column to pitcher_tracking_log.csv
- [ ] Add `level` column to hitter_tracking_log.csv
- [ ] Update read/write logic to handle level field
- [ ] Update eligibility checks to work with MiLB levels

### Phase 4: Report Generation
- [ ] Update `generate_pitcher_performance_report()` signature
- [ ] Update `generate_pitcher_arsenal_report()` signature
- [ ] Update `generate_hitter_report()` signature
- [ ] Pass level parameter through all report functions
- [ ] Add league context to markdown output

### Phase 5: Percentile Integration
- [ ] Add `level` parameter to all percentile functions
- [ ] Test MiLB player percentile calculation vs MLB supporting data
- [ ] Verify percentiles make sense (e.g., is a high-A pitcher's swing% compared fairly to MLB?)
- [ ] Document interpretation (e.g., "x percentile among MLB hitters")

### Phase 6: Pipeline Integration
- [ ] Update `process_weekly_data()` to accept both MLB and MiLB data
- [ ] Create separate data loading section for MiLB
- [ ] Normalize MiLB data before passing to metric calculations
- [ ] Test full pipeline with sample MiLB data

---

## Key Design Principles

1. **Field Name Standardization**: Convert all unique field names to a common set early → All downstream code is reusable
2. **Level Tracking**: Always carry league/level context through pipeline → Reports always know their source
3. **Shared Supporting Data**: MiLB players ranked against MLB distribution → Context for amateur player evaluation
4. **Backwards Compatible**: Changes to tracking logs and functions should still work with existing MLB pipeline
5. **Graceful Degradation**: If MiLB data has issues, MLB pipeline continues unaffected

---

## Questions to Clarify Before Implementation

1. **MiLB Player IDs**: Do you have numeric player IDs for MiLB players, or use full names as IDs?
2. **Game Dates**: How are game dates stored in the `game` object? Can you provide an example?
3. **Batted Ball Type**: What are the `hitData.trajectory` values? (ground_ball, fly_ball, line_drive, popup, etc.)
4. **Pitch Type Values**: What pitch types exist in MiLB data? (FF, SL, etc. — same as MLB?)
5. **Percentile Philosophy**: Should MiLB players be ranked 0-100 against MLB distribution, or would you prefer separate supporting data?
6. **Report Output**: Should MiLB reports indicate they're MiLB in the filename/header? (e.g., "A+ Pitcher Report" vs "MLB Pitcher Report")

