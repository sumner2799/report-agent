# Data Format Specification

## Overview
This document specifies the format and structure of data files for the report generation pipeline.

---

## Input File Format

### File Name Convention
```
statcast_[START_DATE]_[END_DATE].csv
```

Example: `statcast_2026-02-14_2026-02-20.csv`

### Location
All data files should be placed in `/data/raw/`

### Required Columns (Statcast Data)

| Column | Type | Description | Example |
|---|---|---|---|
| `pitcher` | string/int | Pitcher ID or name | "Gerrit Cole" |
| `batter` | string/int | Batter ID or name | "Aaron Judge" |
| `pitch_type` | string | Pitch classification | "FF", "SL", "CH", "CU" |
| `release_speed` | numeric | Fastball velocity (mph) | 95.2 |
| `plate_x` | numeric | Horizontal location (ft) | -0.45 |
| `plate_z` | numeric | Vertical location (ft) | 2.15 |
| `launch_angle` | numeric | Ball exit angle (degrees) | 25.5 |
| `launch_speed` | numeric | Exit velocity (mph) | 92.1 |
| `description` | string | Pitch outcome | "called_strike", "swinging_strike", "ball", "foul", "single", etc. |
| `hc_x` | numeric | Hit coordinate X (optional for plotting) | 125.3 |
| `hc_y` | numeric | Hit coordinate Y (optional for plotting) | 98.7 |
| `hit_distance_sc` | numeric | Carry distance (optional) | 385 |

### Recommended Additional Columns
- `game_date` — Date of game
- `pitcher_hand` — R or L
- `batter_side` — R or L
- `inning` — Inning number
- `outs_when_up` — Outs at time of pitch
- `balls` / `strikes` — Count

---

## CSV Format Requirements
- **Delimiter:** Comma (`,`)
- **Encoding:** UTF-8
- **Header:** First row must contain column names
- **Missing Values:** Use empty cell or `NA`
- **Line Endings:** LF (Unix style)

### Example File Structure
```csv
pitcher,batter,pitch_type,release_speed,plate_x,plate_z,launch_angle,launch_speed,description
Gerrit Cole,Aaron Judge,FF,95.2,-0.45,2.15,25.5,92.1,single
Gerrit Cole,Juan Soto,SL,83.1,0.25,1.85,NA,NA,called_strike
```

---

## Processing Notes

- **Duplicates:** Pipeline removes duplicate rows automatically
- **Missing Data:** Rows missing critical fields (pitcher, batter, pitch_type) are filtered out
- **Data Validation:** Manual check recommended before processing

---

## Providing Data to the Pipeline

### Option A: Manual Upload (Current)
1. Export Statcast data as CSV
2. Place in `/data/raw/`
3. Run pipeline: `Rscript scripts/process_statcast.R` (or use VS Code task)

### Option B: Future Enhancement
Eventually we can set up automated data fetching from Baseball Savant API or other sources.

---

## Questions?
Document any questions about data format here, and we'll refine as needed.
