# Operating Framework: Baseball Analysis Assistant

## Purpose
Build a system of routine reports to evaluate throughout the baseball season for personal knowledge. Reports will leverage data brought to this repo and provide actionable insights on player performance and trends.

---

## Report Categories

### 1. New Player Profiles (Arsenal Reports)
When a player is new to the dataset:
- Provide a general synopsis of the player's profile with pitch arsenal metrics
- Profile components differ by player type (pitcher vs. hitter)
- Goal: Establish baseline understanding of a new player

**MLB & Minor League:** Both leagues follow the same rules. Report generated on first appearance in data.

### 2. Performance Reports
When a player reaches 100+ BIP (balls in play):
- Provide comprehensive performance metrics with percentile ranks
- Include pitch-level (pitcher) or zone-level (hitter) breakdowns
- Goal: Detailed performance analysis with statistical context

**MLB & Minor League:** Both leagues follow the same rules. Report generated when 100+ BIP threshold is met.

### 3. Significant Trend Analysis
For existing players in the dataset:
- Identify interesting trends (positive or negative) in key performance indicators (KPIs)
- Only report on *significant* trends—not everything (time constraints recognized)
- Significance thresholds TBD
- Goal: Highlight meaningful changes in player performance

**MLB & Minor League:** Both leagues follow the same rules and thresholds.

### 4. League Level Distinction
**Important:** Players are treated as separate entities at each league level.
- A player's BIP count is tracked independently per league level
- Example: Player "John Smith" first appears in AA and accrues 100 BIP → Performance report generated
- If "John Smith" is promoted to AAA (different level), his BIP count RESETS to 0
- He must accrue 100 BIP at the AAA level before generating a new performance report at that level
- This ensures accurate representation of performance at each competitive level
- Tracking logs maintain both `player_name` and `level` to distinguish between levels

---

## How I Will Operate

**Knowledge Acquisition:**
- You will drive all learning about your evaluation approach
- I will document the information you provide, not ask leading questions
- Clarifying questions only when necessary for context

**Documentation:**
- I will capture your analytical methods, preferences, and learnings in this repo
- As you teach me what you look for, how you evaluate players, and contextual factors that matter—I document it
- Over time, this builds my understanding of how to be an effective baseball assistant

**Report Generation:**
- Once you've taught me your evaluation approach, I'll apply it to new data you provide
- I'll improve at understanding what you want to see and when based on accumulated learnings

---

## Pitcher Evaluation Framework
*To be documented as you teach me:*
- Key performance indicators you track
- What a "new pitcher profile" should include
- Significant trend thresholds and patterns you care about
- Contextual factors (velocity changes, release point shifts, sequencing, etc.)
- Anything else specific to pitcher analysis

---

## Hitter Evaluation Framework

### Swing Loft Assessment
**Pattern to watch:** High volume of fly balls to the opposite field paired with below-average exit velocity on those opposite-field fly balls.
- This indicates a player does NOT generate good swing loft
- Example: Brady House
- When spotted: Make a mental note for potential future trend monitoring

### Bat Angle & Whiff Patterns
**Pattern to watch:** Player with low overall whiff rate + good sweet spot% + good slug, BUT:
- Whiffs are concentrated at higher pitches
- Strong contact/production on low/in pitches
- High foul% especially on low pitches where slug% is good
- **Interpretation:** Suggests steep bat angle (favorable trait)
- **Important note:** Whiff rate may be artificially suppressed due to high contact rate; context matters
- Example: Daylen Lile (2025)

### Context Notes
- All metrics referenced as percentile ranks
- Evaluate zone-by-zone splits to understand approach and mechanics
- High foul% can indicate aggressive bat path or specific mechanical tendency

---

## Learnings & Patterns
*Documented as you share your analytical insights:*
- How you weight different metrics
- What trends are most predictive of future performance
- Player-type distinctions in evaluation
- Seasonal context and how it affects interpretation
- Career experience learnings on what signals matter

---

## Data Expectations

**Frequency:** Weekly  
**Format:** Statcast CSV (see [Data Format Spec](.system/DATA_FORMAT.md))  

**File Naming Convention:**
- MLB Statcast: `statcast_[START_DATE]_[END_DATE].csv`
- Minor League Statcast: `minorleague_[START_DATE]_[END_DATE].csv` or `mnl_[START_DATE]_[END_DATE].csv`
- Date format: `YYYY-MM-DD` (e.g., `statcast_2025-03-29_2025-04-04.csv`)

**Location:** Place files in `data/raw/`  
**Processing:** Run pipeline with `Rscript scripts/process_statcast.R` (or VS Code task)

---

## Reporting by League Level

### Major League (MLB)
- Data from MLB Statcast
- All players tracked with level designation: `MLB`
- Reports include league designation in output markdown

### Minor League (MiLB)
- Data from Minor League Statcast (AAA, AA, A+, etc.)
- All players tracked with league level designation (AAA, AA, A+, etc.)
- Metric calculations use MiLB-specific formulas (adapted from MLB equivalents)
- Players at each level are tracked independently
- Reports include league level designation in output markdown

### Multi-Level Progression
When a player appears at multiple league levels:
1. System tracks each level separately using `player_name + level` as unique identifier
2. Player's BIP count is maintained independently per level
3. Threshold rules apply independently per level (100 BIP for performance report, etc.)
4. No data carries over between levels—each level treated as fresh evaluation

**Example Workflow:**
- March 2025: John Smith first appears in AA data with 50 BIP → Stored as "John Smith (AA)" with 50 BIP
- April 2025: John Smith accumulates to 100 BIP at AA → Performance report generated
- May 2025: John Smith promoted to AAA, appears in new data file → Stored as "John Smith (AAA)" with 0 BIP (fresh count)
- June 2025: John Smith accumulates 100 BIP at AAA → New performance report generated for AAA level
- Both reports coexist in `/reports/` with level designation in filename

---

✅ **Report Generation System** is now operational. Structure:
- **Templates** (3 report types) — in `/templates/`
- **Processing Pipeline** — automated metric calculation in `/scripts/`
- **Output** — reports generate to `/reports/`
- **Tracking** — [Report Index](.system/REPORT_INDEX.md) and [Data Format](.system/DATA_FORMAT.md)

**Start here:** [QUICKSTART.md](QUICKSTART.md)

