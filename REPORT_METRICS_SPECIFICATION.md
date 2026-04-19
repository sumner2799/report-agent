# Report Metrics Specification

This document specifies which sections from `shiny_aggs.R` should be used for generating pitcher and batter performance reports.

## PITCHER ARSENAL REPORT (Generated at First Appearance)
**Location in shiny_aggs.R**: Lines 156-164 (PITCHER ARSENAL METRICS)

Updated with current statcast data for all pitches thrown by the pitcher.

### Metrics Included:
- `tot` - Total pitches thrown (ordered descending)
- `velo` - Average release speed (mph)
- `rel_side` - Average release position X (side, feet)
- `rel_height` - Average release position Z (height, feet)
- `hb` - Average horizontal break (inches)
- `vb` - Average vertical break (inches)
- `spin` - Average spin rate (rpm)

### Arsenal Report Uses:
```
Velocity & Release Profile Table
Columns: Pitch Type | Usage%(RHH) | Usage%(LHH) | Avg Velo | Velo Range | H-Break | V-Break | Spin Rate | Release Side | Release Height
```

---

## PITCHER PERFORMANCE REPORT (Generated at 100+ BIP)
**Sections in shiny_aggs.R**:
1. **Overall Performance** (Lines 103-148): PITCHER OVERALL PERF
2. **Pitch-Level Performance** (Lines 47-101): PITCHER PITCH LEVEL PERF

### Use ONLY MLB Data (Lines 31-418), NOT MiLB (Lines 419+)

### Overall Performance Metrics:
- `Pitches` - Total pitches thrown
- `BIP` - Balls in play
- `Swing%` - Swing percentage
- `Strike%` - Strike percentage (called + foul + BIP + swinging strikes)
- `Zone%` - Percentage thrown in zone
- `Chase%` - Percentage of out-of-zone pitches that are swung at
- `CS%` - Called strike percentage
- `Foul%` - Foul percentage (of swings)
- `Whiff%` - Whiff percentage (of all swings)
- `IZ Whiff` - In-zone whiff percentage
- `OZ Whiff` - Out-of-zone whiff percentage
- `GB%` - Ground ball percentage (of BIP)
- `HH%` - Hard hit percentage (exit velo ≥ 95 mph)

### Pitch-Level Performance Metrics (Same as Overall, grouped by pitch type):
- All metrics from Overall Performance grouped by `pitch_name`
- Sorted by Pitches descending

### Updated Arsenal Metrics (Same as arsenal report, current period):
- Includes velocity and break data updated to current period
- Allows comparison of arsenal changes over time

---

## BATTER PERFORMANCE REPORT (Generated at 100+ BIP)
**Sections in shiny_aggs.R**:
1. **Overall Performance** (Lines 283-369): BATTER PERF OVR
2. **Zone Performance** (Lines 204-280): BATTER PERF ZONE (vertical & horizontal zones)
3. **Batter Profile** (Lines 370-420): BATTER PROFILE

### Use ONLY MLB Data (Lines 31-418), NOT MiLB (Lines 419+)

### Overall Performance Metrics:
- `PA` - Plate appearances
- `AB` - At-bats (outs recorded 0-1)
- `H` - Hits (single, double, triple, home run)
- `AVG` - Batting average
- `K%` - Strikeout percentage
- `BB%` - Walk percentage
- `HBP` - Hit by pitch count
- `HR` - Home runs
- `Swing%` - Swing percentage
- `Contact%` - Contact percentage (of swings)
- `Zone%` - Percentage of pitches in zone
- `Chase%` - Chase percentage (swing % on out-of-zone pitches)
- `BIP` - Balls in play count
- `LD%` - Line drive percentage (launch angle 10-25°, of BIP)
- `GB%` - Ground ball percentage (launch angle <10°, of BIP)
- `FB%` - Fly ball percentage (launch angle >25°, of BIP)
- `Exit Velo` - Average exit velocity (mph)
- `LA` - Average launch angle (degrees)
- `Barrel%` - Barrel percentage (exit velo ≥92 & launch angle 26-30°, of BIP)
- `Hard Hit%` - Hard hit percentage (exit velo ≥95, of BIP)
- `xwOBA` - Expected weighted on-base average

### Zone Performance Metrics (Split by vertical zones: high/mid/low AND horizontal zones: in/out/middle):
- `BIP` - Balls in play in zone
- `Swing%` - Swing percentage in zone
- `Chase%` - Chase percentage in zone
- `Foul%` - Foul percentage in zone
- `Whiff%` - Whiff percentage in zone
- `IZ Whiff` - In-zone whiff in zone
- `OZ Whiff` - Out-of-zone whiff in zone
- `GB%` - Ground ball percentage in zone
- `HH%` - Hard hit percentage in zone
- `SLGcon` - Slugging percentage on contact in zone
- `Sweet Spot%` - Sweet spot percentage in zone (launch angle 8-32°)

**Vertical Zones**:
- high (zones 1,2,3)
- mid (v) (zones 4,5,6)
- low (zones 7,8,9)

**Horizontal Zones**:
- in (RHH: zones 1,4,7 | LHH: zones 3,6,9)
- out (RHH: zones 3,6,9 | LHH: zones 1,4,7)
- mid (h) (zones 2,5,8)

### Batter Profile Metrics (Swing-specific/quality of contact metrics):
- `BBE` - Batted ball events (hit into play, no bunts)
- `Avg LA` - Average launch angle (degrees)
- `LA Std Dev` - Launch angle standard deviation
- `Sweet Spot%` - Sweet spot percentage (launch angle 8-32°, of BBE)
- `HH LA` - Average launch angle on hard hits (exit velo ≥95)
- `Oppo FB%` - Opposite field fly ball percentage
- `Oppo FB EV` - Average exit velocity on opposite field fly balls
- `High AA%` - High attack angle percentage (attack angle ≥14°)

---

## CRITICAL NOTES

### Do NOT Use MiLB Sections:
- Lines 419-770 contain MiLB (minor league) data sections
- These use different data sources (`mnl_sc_25` instead of `sc_2025`)
- These are for a future phase of the project
- ALWAYS use MLB sections (Lines 31-418)

### Data Filtering:
All metrics are filtered by:
- `game_type` - Should match current period (e.g., "R" for regular season)
- `stand` (batter handedness) for pitcher reports - to calculate RHH vs LHH splits
- `p_throws` (pitcher handedness) for batter reports

### Arsenal Metrics Refresh:
- Pitcher performance reports should include updated arsenal metrics for the current period
- This allows comparison of how arsenal has changed since initial arsenal report
- Use the same pitch arsenal calculation as the arsenal report (Lines 156-164)

### Calculation Context:
All statistics should be calculated from current period Statcast data (`sc_2025` in shiny_aggs.R), aggregated at the appropriate level:
- Pitcher overall: grouped by `player_name` only
- Pitcher pitch-level: grouped by `player_name` and `pitch_name`
- Batter overall: grouped by `last_first_name` (batter name)
- Batter zone: grouped by `last_first_name` and zone location
- Batter profile: grouped by `last_first_name`
