# Operating Framework: Baseball Analysis Assistant

## Purpose
Build a system of routine reports to evaluate throughout the baseball season for personal knowledge. Reports will leverage data brought to this repo and provide actionable insights on player performance and trends.

---

## Report Categories

### 1. New Player Profiles
When a player is new to the dataset and sample size is large enough (threshold TBD):
- Provide a general synopsis of the player's profile
- Profile components differ by player type (pitcher vs. hitter)
- Goal: Establish baseline understanding of a new player

### 2. Significant Trend Analysis
For existing players in the dataset:
- Identify interesting trends (positive or negative) in key performance indicators (KPIs)
- Only report on *significant* trends—not everything (time constraints recognized)
- Significance thresholds TBD
- Goal: Highlight meaningful changes in player performance

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
**Location:** Place files in `data/raw/` with naming convention `statcast_[START_DATE]_[END_DATE].csv`  
**Processing:** Run pipeline with `Rscript scripts/process_statcast.R` (or VS Code task)

---

## System Implementation

✅ **Report Generation System** is now operational. Structure:
- **Templates** (3 report types) — in `/templates/`
- **Processing Pipeline** — automated metric calculation in `/scripts/`
- **Output** — reports generate to `/reports/`
- **Tracking** — [Report Index](.system/REPORT_INDEX.md) and [Data Format](.system/DATA_FORMAT.md)

**Start here:** [QUICKSTART.md](QUICKSTART.md)

