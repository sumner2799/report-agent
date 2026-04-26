# Working With Andrew: Collaboration & Baseball Analysis Framework

## Personal Work Style

### Preferences & Approach
- **Ask before implementing**: Prefers clarifying questions and understanding intent before building solutions. Don't assume requirements—verify assumptions about data structures, calculations, and business logic.
- **Values architecture over speed**: Prioritizes correct system design and data separation over quick implementation. Will catch and flag architectural issues (e.g., mixing MLB/MiLB datasets).
- **Direct feedback**: Provides clear, specific feedback when assumptions are wrong. Takes constructive approach to corrections.
- **Proactive bug fixing**: Appreciates when you identify and fix subtle bugs before they cause problems (e.g., status being updated before reports are generated).
- **Documentation-oriented**: Values understanding the "why" behind changes and expects clear explanations of implementation choices.

## Baseball Analysis Philosophy

### Core Metrics & Concepts
- **Statcast-level analysis**: Works with pitch-by-pitch data (both MLB and MiLB sources)
- **BIP-based triggers**: Uses Balls In Play (BIP) count thresholds to determine when to generate reports
  - Thresholds vary by report type (100 BIP for performance reports, 50 pitch minimum for initial identification)
- **Percentile context is critical**: Raw metrics are less useful than percentile rankings. Reports should always include percentile context so metrics can be evaluated relative to league distributions.
- **Sample size matters**: Reliable analysis requires adequate samples. Thresholds are calibrated to ensure statistical validity.

### Report Types & Generation Logic

#### 1. **Arsenal Reports** (First Appearance)
- Triggered when a pitcher appears in data for the first time
- Shows pitch inventory, velocities, and movement profiles
- MLB version: Includes RHH/LHH splits
- MiLB version: Simplified metrics appropriate to data quality

#### 2. **Performance Reports** (100+ BIP Trigger)
- Generated when a player accumulates 100+ balls in play
- Includes:
  - Overall performance metrics with percentile ranks
  - Pitch-level (pitcher) or zone-level (hitter) breakdown with percentiles
  - Updated arsenal metrics (pitchers) or swing quality profile (hitters)
- Critical: Status should only be updated to "reported" AFTER report is successfully generated (prevents missing reports on subsequent runs)

#### 3. **Trend Reports** (Month-to-Month Detection)
- Only generated at beginning of month (1st-3rd)
- Compares two complete months (not YTD or rolling)
- Previous month: End of 2 months prior to current data month
- Current month: End of 1 month prior to current data month
- Uses significance thresholds (varies by metric: 2.5%-5% for percentages, specific deltas for slg)
- Must have 50+ pitches/events in both comparison periods

## Technical Architecture & Data Handling

### Fundamental Principle: Complete League Separation
- **Never mix MLB and MiLB data**: These are fundamentally different datasets with different field structures
  - MLB: Standard statcast fields (pitcher, batter, pitch_type, plate_x, plate_z, etc.)
  - MiLB: Different schema (matchup.pitcher.id, matchup.batter.id, pitchData.*, etc.)
- **No rbind combining**: Each league processed through completely independent pipelines
- **Separate data variables**: mlb_all_data / mlb_statcast_data vs milb_all_data / milb_statcast_data
- **Tracking separation**: Tracking logs maintain `level` column; (player, level) pairs are tracked independently

### Data Field Mapping
- **Player names**: Always prefer `player_name` over `last_first_name` (the latter only exists in MLB statcast, will fail on MiLB data)
- **MiLB normalization**: Convert MiLB field names to MLB equivalents during normalization (normalize_milb_data function)
- **Level designation**: Always extracted and carried through analysis (home_level_name for MiLB, implicit MLB for statcast data)

### Percentile Calculations
- Supporting data: 12 CSVs in `data/supporting/` (pitcher_overall_overall.csv, batter_zone_overall.csv, etc.)
- All percentile functions accept `level` parameter for league context
- MiLB players ranked against MLB distributions (comparative advantage metric)
- Current percentile columns in reports:
  - Overall tables: All major metrics (Swing%, Strike%, Chase%, Whiff%, GB%, HH%, etc.)
  - Pitch-level (pitchers): Whiff% rank by pitch type
  - Zone-level (hitters): Whiff% rank by location
  - Can be expanded to include additional metrics per request

### Key Functions with Level-Aware Routing
- `calculate_pitcher_overall_perf()` / `calculate_pitcher_overall_perf_milb()`
- `calculate_pitcher_pitch_perf()` / `calculate_pitcher_pitch_perf_milb()`
- `calculate_pitcher_arsenal_milb()` (first-appearance metrics for MiLB)
- `calculate_batter_overall_perf()` / `calculate_batter_overall_perf_milb()`
- `calculate_batter_zone_perf()` / `calculate_batter_zone_perf_milb()`
- `calculate_batter_profile()` / `calculate_batter_profile_milb()`
- All percentile functions accept level parameter

## Collaboration Best Practices

### Before Implementation
1. Ask clarifying questions about data sources, field availability, and calculation logic
2. Verify assumptions about report triggers, thresholds, and business rules
3. Confirm architectural decisions (especially around data separation and normalization)

### During Implementation
1. Make architectural correctness a priority over quick delivery
2. Catch subtle bugs (e.g., status updates before report generation)
3. Fix field name references to work across both leagues when data is shared
4. Test with both MLB and MiLB data paths if applicable

### Code Quality Standards
1. Include level filtering in all multi-league data operations
2. Use consistent field references (prefer generic names that exist in both sources)
3. Comment non-obvious logic (especially around data mapping and filtering)
4. Include 3-5 lines of context in find/replace operations for clarity
5. Verify no syntax errors after multi-step changes

## Known Quirks & Edge Cases

### Data Issues
- **last_first_name trap**: This field only exists in MLB statcast data. Using it on mixed datasets will fail silently or crash. Always use `player_name` instead.
- **MiLB field differences**: Be explicit about field name mapping (matchup.pitcher.id vs pitcher, pitchData.startSpeed vs release_speed, etc.)

### Report Generation Logic
- **Status transitions matter**: 
  - Pitchers: arsenal_reported → performance_reported
  - Hitters: new → reported
  - Status should only change AFTER successful report generation
- **Trend eligibility**:
  - Only pitchers with "performance_reported" status are eligible
  - Only hitters with "reported" status are eligible
  - Skip if first report was generated in current data month

### Tracking & Accumulation
- BIP counts accumulate across runs (add new BIP to existing total)
- PA counts accumulate for hitters
- Pitch counts accumulate for pitchers
- Level column in tracking logs is critical for preventing cross-league contamination

## Questions to Ask When Requirements Aren't Clear

1. **Data source questions**:
   - What fields are available in this dataset?
   - How should missing fields be handled?
   - Are there different data sources that need separate processing?

2. **Calculation questions**:
   - Should this metric be calculated the same way for all leagues?
   - What's the sample size threshold for reliability?
   - How should edge cases (missing values, zero denominators) be handled?

3. **Report/trigger questions**:
   - What conditions trigger this report?
   - What thresholds should be used?
   - Should the logic differ between leagues?

4. **Architecture questions**:
   - Should these datasets be combined or kept separate?
   - How should level/league designation flow through the pipeline?
   - What tracking or state needs to be maintained?

## Success Metrics

A solution is successful when:
- ✅ Data separation is complete and enforced (no cross-contamination)
- ✅ Both MLB and MiLB reports are generated correctly
- ✅ Percentile context is provided for all key metrics
- ✅ Player names and level designations appear in reports and filenames
- ✅ Tracking logs accurately reflect (player, level) pairs
- ✅ No silent failures or edge cases that prevent report generation
- ✅ Code is maintainable and clearly documents its intent

## Context for Future Sessions

When starting a new session, refer to this document to understand:
- The two-league system (MLB + MiLB) and why they're kept separate
- The three report types (arsenal, performance, trend) and their triggers
- The importance of percentile context in all reports
- The field naming conventions and where `last_first_name` might cause issues
- Why architectural correctness matters more than speed
- How to ask clarifying questions before implementing changes
