# MiLB Integration: Session Summary & Status Report
**Date:** March 31, 2026 | **Status:** 85% Complete

---

## What We Accomplished Today

### 1. ✅ MiLB Metric Calculation Functions (NEW)
**Location:** `/scripts/calculate_metrics.R` (lines 727-996)

Added 5 complete metric calculation functions that work directly with MiLB Statcast data, using your exact formulas from shiny_aggs.R:

- **`calculate_pitcher_overall_perf_milb(pitcher_data)`**
  - Calculates: Pitches, BIP, Swing%, Strike%, Zone%, Chase%, CS%, Foul%, Whiff%, IZ Whiff, OZ Whiff, GB%, HH%
  - Uses MiLB field names (details.call.description, hitData.trajectory, etc.)

- **`calculate_pitcher_pitch_perf_milb(pitcher_data)`**
  - Pitch-level breakdown of all above metrics
  - Groups by pitch_type

- **`calculate_batter_overall_perf_milb(batter_data)`**
  - Calculates: BIP, Swing%, Chase%, Foul%, Whiff%, IZ/OZ Whiff, GB%, Barrel%, HH%, SLG, Sweet Spot%

- **`calculate_batter_zone_perf_milb(batter_data)`**
  - Zone-level breakdown (high/mid/low vertically)
  - Same metrics as overall performance

- **`calculate_batter_profile_milb(batter_data)`**
  - Calculates: BBE, Avg LA, LA Std Dev, Sweet Spot%, HH LA, Oppo FB%, Oppo FB EV, High AA%

**Implementation Approach:** Direct formula transcription from your shiny_aggs.R script, adapted to MiLB field names. No generalization or abstraction—keeps formulas exactly as you wrote them for precision.

---

### 2. ✅ Tracking System Updated
**Location:** `.system/pitcher_tracking_log.csv` & `.system/hitter_tracking_log.csv`

Added `level` column (position 2) to both tracking logs:

**Before:**
```csv
pitcher_name,report_date,bip_count,pitch_count,status,notes
```

**After:**
```csv
pitcher_name,level,report_date,bip_count,pitch_count,status,notes
"Max Scherzer",MLB,2026-03-30,150,450,performance_reported,
```

**Benefit:** Single unified tracking system for both MLB and MiLB with league context preserved.

---

### 3. ✅ Percentile Functions Enhanced
**Location:** `/scripts/calculate_metrics.R` (all 5 percentile functions)

Updated function signatures to accept `level` parameter:

```r
calculate_pitcher_overall_percentiles(pitcher_metrics, pitcher_id, level = "MLB")
calculate_pitcher_pitch_percentiles(pitch_perf, pitcher_id, level = "MLB")
calculate_batter_overall_percentiles(batter_metrics, batter_id, level = "MLB")
calculate_batter_zone_percentiles(zone_perf, batter_id, level = "MLB")
calculate_batter_profile_percentiles(profile_metrics, batter_id, level = "MLB")
```

**Key Changes:**
- Level parameter added throughout
- Level field included in output tibbles
- MiLB players ranked against **same MLB supporting data** (not separate)
- Enables contextual comparison: "AAA pitcher's swing% is in 87th percentile of MLB distribution"

---

### 4. ✅ Report Generation Functions Updated
**Location:** `/scripts/process_statcast.R`

Updated report functions to accept and use level parameter:

- **`generate_pitcher_performance_report(pitcher_data, pitcher_name, pitcher_id = NULL, level = "MLB")`**
  - Added level to function signature
  - First row of table shows: `| **League** | AAA | — |`
  - Passes level to percentile calculations

- **`generate_hitter_report(batter_data, batter_id, level = "MLB")`**
  - Added level to function signature
  - Shows league context in report
  - Passes level to percentile functions

**Report Output Change:**
Reports now explicitly show league/level, enabling clear identification of data source.

---

### 5. ✅ Function Call Updated
**Location:** `/scripts/process_statcast.R`

Updated existing function calls to pass level parameter:

```r
# Pitcher performance report call
report <- generate_pitcher_performance_report(full_pitcher_data, pitcher_name, player_id, pitcher_level)

# Hitter report call
report <- generate_hitter_report(full_batter_data, player_id, "MLB")
```

---

### 6. ✅ Documentation Created

**MILB_INTEGRATION_PLAN.md** (5,000+ words)
- Reverse-engineering methodology explained
- Field mapping table (MLB vs MiLB)
- Implementation strategy with code templates
- Implementation checklist (6 phases)
- Design principles

**MILB_FINAL_STEPS.md**
- Completed work summary
- Remaining tasks (15%)
- Design notes for final integration
- Questions before implementation

**MILB_ARCHITECTURE.md** (this file)
- Executive summary
- Architecture layers (5 levels)
- Data flow diagram
- Implementation path forward
- Code organization reference
- Testing checklist

---

## What's Left to Do (15%)

### Task 1: Data Loading Function (NEW)
**Effort:** 30 minutes

Create a function to load and normalize MiLB data:

```r
load_minorleague_data <- function(mnl_data_source) {
  # Load mnl_sc_25 or equivalent
  # Map field names to internal format
  # Extract level from home_level_name
  # Return normalized data ready for metric functions
}
```

**Required Information from You:**
- Where is MiLB Statcast data stored? (variable name, file path, or data frame?)
- Do pitcher/batter IDs exist? (matchup.pitcher.id, matchup.batter.id?)
- What are possible values for home_level_name? (A, A+, AA, AAA?)

### Task 2: Pipeline Integration (NEW)
**Effort:** 1 hour

Create MiLB processing function and integrate into main pipeline:

```r
process_weekly_data_milb <- function(mnl_data) {
  # Load tracking logs (SHARED with MLB)
  # Identify eligible MiLB players
  # Generate reports using _milb functions
  # Update tracking logs with level column
  # Return reports
}

# Update main orchestration
process_weekly_data <- function() {
  # Process MLB (existing)
  mlb_reports <- process_weekly_data()  # existing MLB logic
  
  # Process MiLB (new)
  mnl_reports <- process_weekly_data_milb(mnl_sc_data)
  
  # Combine and return
  all_reports <- c(mlb_reports, mnl_reports)
  return(all_reports)
}
```

### Task 3: Testing & Validation (NEW)
**Effort:** 30 minutes

- Run with sample MiLB data
- Verify metrics make sense
- Confirm tracking logs update properly
- Validate percentile rankings
- Check report output format

---

## Current Code Status

### Files Modified
1. ✅ `/scripts/calculate_metrics.R` (999 lines)
   - Added 270 lines of MiLB metric functions
   - Updated 5 percentile functions with level parameter
   - No syntax errors

2. ✅ `/scripts/process_statcast.R` (1092 lines)
   - Updated 2 report functions with level parameter
   - Updated 2 function calls to pass level
   - No syntax errors

3. ✅ `.system/pitcher_tracking_log.csv`
   - Added level column
   - All 106 existing records tagged with "MLB"

4. ✅ `.system/hitter_tracking_log.csv`
   - Added level column
   - All existing records tagged with "MLB"

### Documentation Created
- `MILB_INTEGRATION_PLAN.md` - Comprehensive methodology guide
- `MILB_FINAL_STEPS.md` - Final integration steps
- `MILB_ARCHITECTURE.md` - Architecture overview

---

## Key Design Decisions

| Decision | Rationale | Benefit |
|----------|-----------|---------|
| **Separate _milb functions** | Direct formula mapping from shiny_aggs.R | Precision, maintainability, no transformation overhead |
| **Shared percentile supporting data** | Enables MLB context comparison | Can see how MiLB players rank vs MLB |
| **Single tracking log with level column** | Unified player tracking system | Single source of truth, easy filtering |
| **Level as function parameter** | Optional, defaults to "MLB" | Backward compatible, future-proof |
| **League indicator in reports** | Explicit league context | Clear identification of data source |

---

## Architecture Overview

```
Input Data (MLB or MiLB)
         ↓
   Metric Layer (league-specific functions)
         ↓
  Tracking System (unified with level column)
         ↓
 Percentile Ranking (both vs MLB supporting data)
         ↓
Report Generation (includes level context)
         ↓
Output (Markdown reports)
```

**Key:** MiLB players flow through same report pipeline as MLB; they're just tracked with level="AAA" or level="A+" instead of level="MLB".

---

## Next Steps (For You)

1. **Provide MiLB data details:**
   - How is MiLB Statcast data stored in your environment?
   - Variable name? File path? Data structure?
   - What pitcher/batter ID fields exist?

2. **Confirm level values:**
   - What are all possible home_level_name values in your data?
   - Example: "A+", "AA", "AAA" or different format?

3. **Request final implementation:**
   - Once above info provided, I'll implement the final 15%
   - ~2 hours to complete
   - Full end-to-end testing included

---

## Verification Checklist (Before Final Implementation)

- [x] MiLB metric functions implemented
- [x] Tracking logs updated with level column
- [x] Percentile functions accept level parameter
- [x] Report functions accept level parameter
- [x] All syntax checked (no errors)
- [x] Documentation comprehensive
- [ ] MiLB data loading function (pending your info)
- [ ] Pipeline integration (pending data loading)
- [ ] End-to-end testing (pending above)

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| New functions added | 5 (all _milb variants) |
| Functions updated | 7 (5 percentile + 2 report functions) |
| Files modified | 4 |
| Lines of code added | ~400 |
| Syntax errors | 0 |
| Tests passed | All static checks ✅ |
| Documentation files | 3 |
| Completion percentage | 85% |

---

## Questions Before We Proceed?

The implementation is ready to go. I just need clarity on 3 questions to complete the final integration:

1. **MiLB Data Location:** Where/how is your MiLB Statcast data stored?
2. **Level Values:** What are all possible values for `home_level_name`?
3. **Player IDs:** Do pitcher and batter IDs exist in MiLB data?

Once you provide these, I can finish the remaining 15% in approximately **2 hours** with full testing included.

---

**Session Date:** March 31, 2026
**Total Session Time:** ~4 hours
**Status:** Ready for final integration handoff
