# MiLB Integration: Final Steps

## Summary of Completed Work (Mar 31, 2026)

### ✅ Completed Phases

1. **MiLB Metric Functions Added** (`calculate_metrics.R`)
   - `calculate_pitcher_overall_perf_milb()` - Pitcher overall metrics from MiLB data
   - `calculate_pitcher_pitch_perf_milb()` - Pitcher pitch-level breakdown
   - `calculate_batter_overall_perf_milb()` - Batter overall metrics
   - `calculate_batter_zone_perf_milb()` - Batter zone performance
   - `calculate_batter_profile_milb()` - Batter swing quality metrics

2. **Tracking Logs Updated** (`.system/`)
   - Added `level` column to pitcher_tracking_log.csv
   - Added `level` column to hitter_tracking_log.csv
   - All MLB records tagged with "MLB"
   - Ready for MiLB records (A+, AAA, AA, etc.)

3. **Percentile Functions Enhanced** (`calculate_metrics.R`)
   - All 5 percentile functions now accept `level` parameter
   - Level included in percentile calculation records
   - MiLB players will be ranked against MLB supporting data
   - level = "MLB", "AAA", "AA", "A+", etc.

4. **Report Generation Updated** (`process_statcast.R`)
   - `generate_pitcher_performance_report()` accepts `level` parameter
   - `generate_hitter_report()` accepts `level` parameter
   - League/level shows in reports (first row: "**League** | AAA | —")
   - Percentile context preserved for MiLB players

---

## Remaining Work: Final Integration

### What Still Needs to Be Done

1. **MiLB Data Loading Function** (NEW)
   ```r
   load_minorleague_data <- function(path_to_mnl_sc_data) {
     # Load raw MiLB Statcast data (mnl_sc_25 or equivalent)
     # Fields available: matchup.pitcher.id, matchup.pitcher.fullName, 
     #                   matchup.batter.id, matchup.batter.fullName, 
     #                   game_date, home_level_name, etc.
     # Return: data frame ready for metric calculations
   }
   ```

2. **MiLB Pipeline Function** (NEW)
   ```r
   process_weekly_data_milb <- function(mnl_data) {
     # Similar to process_weekly_data() but for MiLB
     # Load both pitcher & hitter tracking logs (SHARED with MLB)
     # Identify players reaching thresholds (100 BIP for hitters, etc.)
     # Calculate metrics using _milb functions
     # Generate reports with level = home_level_name
     # Update tracking logs with level column
     # Return: list of new reports
   }
   ```

3. **Update Main Pipeline** (MODIFY)
   ```r
   process_weekly_data <- function() {
     # Load MLB data
     # Process MLB (existing logic)
     
     # Load MiLB data
     # Process MiLB (new logic)
     
     # Combine reports from both
     # Return all reports
   }
   ```

4. **Integrate into process_weekly_data()** (UPDATE)
   The main orchestration function needs to:
   - Load both MLB and MiLB data
   - Call both MLB and MiLB processing
   - Use SHARED tracking logs for both leagues
   - Combine all reports into single output

---

## Key Design Notes

### Field Mapping (MiLB → Internal)
When implementing `load_minorleague_data()`, map:
- `matchup.pitcher.id` → `pitcher` (pitcher ID)
- `matchup.pitcher.fullName` → `pitcher_name` (pitcher name)
- `matchup.batter.id` → `batter` (batter ID)  
- `matchup.batter.fullName` → `batter_name` (batter name)
- `game_date` → `game_date` (already correct)
- `home_level_name` → store separately for `level` parameter
- All other field mappings per the shiny_aggs.R exploration

### Sample Size Criteria (Same as MLB)
- Pitchers: 100 BIP for performance report
- Batters: 100 BIP for performance report
- Arsenal: First appearance when data available
- Trends: Only in first 3 days of month, comparing two complete previous months

### Shared Tracking System
Single tracking log files now serve both MLB and MiLB:
```
pitcher_name,level,report_date,bip_count,pitch_count,status,notes
Max Scherzer,MLB,2026-03-30,150,450,performance_reported,
John Doe,AAA,2026-03-29,105,320,arsenal_reported,
```

### Report Output
Indicate level clearly in markdown:
```markdown
# Pitcher Performance Report (AAA): John Doe

**Report Date:** March 29, 2026
**Level:** AAA
**Sample Size:** 320 pitches
...
```

---

## Next Actions

1. **Examine MiLB data structure** in your environment
   - Confirm field names match expectations
   - Identify date format
   - Confirm level values (A+, AA, AAA)

2. **Implement `load_minorleague_data()`**
   - Load raw MiLB Statcast data
   - Normalize field names
   - Add league context

3. **Implement `process_weekly_data_milb()`**
   - Mirror MLB logic but using _milb metric functions
   - Use shared tracking logs with level filtering
   - Pass level to report functions

4. **Integrate into `process_weekly_data()`**
   - Call both MLB and MiLB processing
   - Combine reports

5. **Test end-to-end**
   - Run with sample MiLB data
   - Verify reports generate correctly
   - Confirm tracking logs update with level
   - Verify percentiles work for MiLB players

---

## Questions Before Implementation

1. What is the exact structure/location of your MiLB Statcast data?
2. What are the possible values for `home_level_name`? (A+, AA, AAA, or different?)
3. Do you want separate tracking files for MLB vs MiLB, or continue with shared files?
4. Any special handling for MiLB pitcher/hitter IDs, or use them directly?
5. Should MiLB reports go to same output directory, or separate folder?
