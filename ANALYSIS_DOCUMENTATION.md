# Year-to-Year KPI Improvement Analysis: Documentation

**Project:** Year-to-Year KPI Improvement & Performance Analysis  
**Date Completed:** April 2026  
**Primary Script:** `scripts/kpi_yearover_analysis.R`

---

## Table of Contents

1. [Coding Style & Preferences](#coding-style--preferences)
2. [Critical Concepts](#critical-concepts)
3. [Data Structure & Naming Conventions](#data-structure--naming-conventions)
4. [Technical Approaches](#technical-approaches)
5. [Analysis Methodology](#analysis-methodology)
6. [Key Findings & Interpretation](#key-findings--interpretation)
7. [Best Practices for Future Work](#best-practices-for-future-work)
8. [Limitations & Assumptions](#limitations--assumptions)
9. [Future Work](#future-work)

---

## Coding Style & Preferences

### Language & Structure
- **Primary language:** R (strong preference over Python)
- **Script-based execution:** Prefers inline code with functions commented out rather than heavy modularization
- **Core packages:** dplyr, tidyr, readr, stringr, ggplot2
- **Pipe-friendly:** Uses `%>%` chains extensively for readability
- **Result storage:** Nested lists with explicit field names for interpretability

### File Organization
```
scripts/
├── kpi_yearover_analysis.R          # Main analysis script
data/
├── processed/                        # Output CSVs and processed data
├── raw/                             # Raw Statcast data
reports/                             # Generated markdown reports
```

### Naming Conventions

**Field Names:**
- Directional prefixes: `prior_`, `current_`, `gb_`, `mid_`, `ovr_`
- Metric suffixes: `_rate`, `_change`, `_improvement`, `_pct`, `_coef`, `_score`
- Zone references: `"mid (v)"`, `"mid (h)"`, `"overall"` as Location categorical values
- Player identifier: `last_first_name` (string, format: "Last, First")
- Temporal grouping: `prior_year`, `current_year`, `season` (numeric, e.g., 2023)

**Example data structure:**
```
transitions_df columns:
  - last_first_name (char): "Altuve, Jose"
  - prior_year (num): 2023
  - current_year (num): 2024
  - Location (char): "mid (v)", "mid (h)", or "overall"
  - gb_improvement_pct (num): -10.5 (negative = improvement)
  - gb_change (num): -3.2 (percentage points)
  - hard_hit_change (num): +1.5
  - sweet_spot_change (num): +2.1
  - slg_change (num): +0.015
```

---

## Critical Concepts

### ⚠️ CRITICAL: Percentage-Point vs Percent Change

This distinction is **fundamental to the analysis validity**.

```r
gb_improvement_pct = ((prior_gb_rate - current_gb_rate) / prior_gb_rate) * 100
  → Relative percentage improvement
  → Example: prior=60%, current=54% → improvement_pct = +10%
  → Meaning: GB rate decreased by 10% OF ITS ORIGINAL VALUE

gb_change = current_gb_rate - prior_gb_rate
  → Absolute percentage-point change
  → Example: prior=60%, current=54% → change = -6pp
  → Meaning: GB rate dropped 6 percentage points
```

**Why Both Are Tracked:**
- `gb_improvement_pct`: Used in binning analysis (shows relative magnitude)
- `gb_change`: Used in regression models (outcome variables are also in pp, ensuring commensurable units)

**In Regression Coefficients:**
```r
# Interpretation (using gb_change):
# "A 1 percentage-point improvement in GB% is associated with 
#  X percentage-point change in [outcome metric]"

# Example: sweet_spot model coefficient = 0.469
# → 1pp GB% reduction associates with +0.469pp sweet spot improvement
```

**Key Insight:** If you use `gb_improvement_pct` in regression against pp outcome variables, coefficient interpretation becomes awkward and non-intuitive.

---

## Data Structure & Naming Conventions

### Primary DataFrames

| DataFrame | Purpose | Key Columns | Grouping |
|-----------|---------|------------|----------|
| `metrics_df` | Player-season metrics aggregated | last_first_name, season, Location, `GB%`, `Chase%`, barrel_rate, hard_hit_rate | By player-season-zone |
| `cohort_df` | Players meeting both KPI thresholds | last_first_name, season, meets_gb_threshold, meets_chase_threshold | By player-season |
| `transitions_df` | Year-to-year changes | last_first_name, prior_year, current_year, Location, *_improvement_pct, *_change | By player-transition-zone |
| `df_combo` | Aggregated by player-transition (both zones) | last_first_name, prior_year, current_year, gb_improvement, chase_improvement, mid_*, ovr_* | By player-transition |

### Field Naming Rules

- **Rate/percentage metrics:** `gb_rate`, `chase_rate`, `barrel_rate`, `hard_hit_rate`, `sweet_spot_rate`, `whiff_rate`
- **Change metrics:** `gb_change`, `chase_change`, `hard_hit_change`, `sweet_spot_change`, `slg_change`, `whiff_change` (always absolute, in pp or points)
- **Improvement metrics:** `gb_improvement_pct`, `chase_improvement_pct` (always relative percentage)
- **Zone-specific:** `mid_slg_change`, `mid_hh_change`, `mid_swspot_change`, `ovr_slg_change`
- **Quality composites:** `impact_quality_score` = (mid_slg_change + mid_hh_change + mid_swspot_change) / 3

---

## Technical Approaches

### Data Processing Workflow

1. **Load & parse:** Raw Statcast CSV → date parsing → level filtering (if applicable)
2. **Zone filtering:** All pitches → middle zone only (`is_middle_zone()`)
3. **Metric aggregation:** By (player, season, location) with min 50 pitch threshold
4. **Cohort identification:** Find players ≥80th percentile GB%, ≤20th percentile Chase%
5. **Year-to-year matching:** Match same player across seasons, calculate improvements
6. **Analytical separation:** Create df (mid-zone), df_chase (overall), df_combo (both)
7. **Modeling:** Fit OLS models for each analytical lens

### Distinctive Processing Patterns

**Location separation is critical:**
```r
gb_transitions <- transitions_from_cohort %>%
  filter(Location == "mid (v)") %>%
  select(last_first_name, prior_year, current_year, gb_improvement_pct, hard_hit_change, ...)

chase_transitions <- transitions_from_cohort %>%
  filter(Location == "overall") %>%
  select(last_first_name, prior_year, current_year, chase_improvement_pct)

both_kpi_transitions <- gb_transitions %>%
  left_join(chase_transitions, by = c("last_first_name", "prior_year", "current_year"))
```

**Distinct counting for longitudinal data:**
```r
# NOT: nrow(transitions_df) — would count duplicate zones
# YES: nrow(transitions_df %>% distinct(last_first_name, prior_year, current_year))
```

**NA handling with explicit filters:**
```r
# NOT: na.omit(df) — loses control of which variables caused NAs
# YES: filter(!is.na(gb_improvement_pct), !is.na(chase_improvement_pct), ...)
```

---

## Analysis Methodology

### Three Regression Model Families

The analysis builds **three separate models** to avoid confounding:

#### Family 1: GB% Effects (mid-zone pitches)
```r
Models: whiff_change, hard_hit_change, slg_change, sweet_spot_change ~ gb_improvement_pct
Data: df (filtered to Location == "mid (v)")
Purpose: Show GB% improvement's isolated effect on mid-zone outcomes
```

#### Family 2: Chase Rate Effects (overall)
```r
Models: whiff_change, hard_hit_change, slg_change, sweet_spot_change ~ chase_improvement_pct
Data: df_chase (filtered to Location == "overall")
Purpose: Show Chase% improvement's isolated effect on overall outcomes
```

#### Family 3: Combined Effects (both KPIs together)
```r
Models: mid_*_change ~ gb_improvement + chase_improvement
Data: df_combo (aggregated player-transitions with both zones)
Purpose: Show how GB% and Chase% improvements interact/combine
```

### Frequency Analysis

Answers the "how often" question:

```r
analyze_improvement_frequency(transitions_df, cohort_df)
```

Returns:
- `cohort_size`: Total player-seasons in elevated KPI cohort
- `total_transitions`: Year-to-year transitions available
- `both_kpi_improvements`: Transitions where BOTH GB% AND Chase% improved
- `both_kpi_with_perf_gain`: Of those, how many showed 2+ performance metrics improving
- `pct_both_improved`: Percentage achieving dual KPI improvements
- `pct_both_with_benefit`: Percentage of dual improvers gaining performance

---

## Key Findings & Interpretation

### Finding 1: No Meaningful Tradeoff
**Regression R² values:**
- GB% → Hard-Hit Rate: R² ≈ 0.00
- GB% → SLG: R² ≈ 0.01
- GB% → Sweet Spot: R² ≈ 0.23

**Interpretation:**
- Weak R² (near zero) for hard-hit and SLG indicates **no detectable relationship**
- If GB% improvement *caused* loss in impact quality, we'd see strong negative correlation
- **Absence of correlation suggests independence:** impact quality changes are driven by other factors, not by GB% adjustments
- The sweet spot relationship (R² = 0.23) is the strongest finding: improving GB% correlates with more sweet spot contact

### Finding 2: GB% ↔ Sweet Spot Relationship
**R² = 0.23** is meaningful in baseball context (data is typically noisy)
- Represents moderate positive relationship
- Mechanically sensible: strikeout reduction → improved contact consistency
- Exemplified by Pattern 5 exemplars (GB% improvement paired with sweet spot improvement)

### Finding 3: Frequency of Dual Improvements
[Populate with actual percentages from your data]
- Of elevated KPI cohort, X% achieve both GB% AND Chase% improvement
- Of those dual improvers, Y% show performance gains (2+ metrics improve)
- Suggests improvement in both KPIs is possible but not automatic

---

## Exemplar Patterns

Five key player-season archetypes identified:

| Pattern | Definition | Business Meaning |
|---------|-----------|-----------------|
| 1 | GB% improved + impact quality improved | Win-win scenario; blueprint case |
| 2 | GB% improved but impact quality degraded | Approach change with cost; trade-off validation |
| 3 | Largest overall KPI improvement | Maximum improvement case; rare achievement |
| 4 | Significant GB% improvement + stable impact | Pure approach improvement; no spillover effects |
| 5 | GB% improvement + sweet spot improvement | R²=0.23 exemplar; shows correlation mechanism |

---

## Best Practices for Future Work

### Iteration Strategy
1. **Start with research questions, not methods**
   - Define: "How often does X happen?" vs "What's the relationship?"
   - These are different questions requiring different approaches
2. **Iterate based on gaps discovered**
   - Initial analysis answered "what's the relationship" but not "how often"
   - Frequency analysis was added mid-project to close this gap
   - This is normal and valuable, not a sign of poor planning
3. **Separate models by analytical lens**
   - Don't combine GB and Chase in one model initially
   - Build separate models, then combine to understand interaction effects
   - Prevents confounding and makes interpretation clearer

### Interpretation Best Practices
1. **Weak R² ≠ no finding** — it can be evidence AGAINST a hypothesized negative relationship
2. **Use exemplars to ground statistics** — translate coefficients into player stories
3. **Report both direction AND magnitude** — "R² = 0.23" means little without "coefficient = +0.469pp"
4. **Always map back to original question** — "Does this answer what you asked?"

### Documentation at Analysis Time
- Record threshold decisions and rationale as you make them
- Document which metric (pp vs %) is used in each analysis and why
- Note any assumptions or filters applied
- Keep comments explaining non-obvious code choices

---

## Limitations & Assumptions

### Data Limitations
1. **Sample size:** Elevated KPI cohort may be small; limits generalizability
2. **Time period:** 2021-2024 data; findings may not apply to earlier/later seasons
3. **Selection bias:** Only players meeting thresholds; doesn't represent all player types
4. **Uncontrolled confounders:**
   - Pitcher quality faced year-to-year
   - Ballpark effects and dimensional changes
   - Mechanical coaching changes not tracked in data
   - Age/experience progression

### Methodological Assumptions
1. **Linear relationships:** OLS regression assumes linear effects; actual relationships might be nonlinear
2. **Independence:** Assumes each transition is independent (may not be true for same player across years)
3. **Normality:** Assumes residuals are normally distributed
4. **Stable thresholds:** 80th/20th percentiles held constant; didn't test sensitivity to threshold changes

### Zone Assumptions
- "Middle zone" defined as specific plate_x and plate_z ranges; boundaries are somewhat arbitrary
- Assumption that contact approach on middle pitches generalizes to overall performance
- Aggregation across horizontal and vertical middle zones; might mask zone-specific patterns

---

## Future Work

### High-Priority Analyses
1. **Sensitivity Analysis**
   - Test whether findings hold at different percentile thresholds (e.g., 75th, 85th)
   - Vary minimum pitch requirements (50 → 40, 60)
   - Binning cutoff sensitivity

2. **Minor League Validation**
   - Replicate analysis on AAA/AA/A Statcast data
   - Do patterns strengthen/weaken at different levels?
   - Helps validate that findings aren't MLB-specific quirks

3. **Confounding Analysis**
   - Control for pitcher quality (velocity, movement profiles of pitchers faced)
   - Adjust for ballpark effects
   - Age/experience controls

### Exploratory Questions
1. **Interaction effects:** Do certain pairs of KPI improvements reinforce each other more than others?
2. **Lagged effects:** Does GB% improvement in year N affect performance in year N+2 (beyond N+1)?
3. **Durability:** Are improvements sustained in year N+2? Is this a one-year blip?
4. **Subgroup analysis:** Do findings differ by handedness, position, age?
5. **Mechanical validation:** Do video/tracking data support the contact improvement hypothesis?

### Holdout Testing
- Hold out 2024 data from model fitting (fit on 2021-2023)
- Test if 2024 transitions align with model predictions
- Would validate predictive utility, not just historical relationships

---

## Reference: Configuration Parameters

Located at top of `kpi_yearover_analysis.R`:

```r
# Thresholds
GB_PERCENTILE_THRESHOLD <- 0.80        # 80th percentile or higher
CHASE_PERCENTILE_THRESHOLD <- 0.80     # 20th percentile or lower (≤20th = best)
MIN_PITCHES_ZONE <- 50                 # Minimum pitches per player-season

# Binning
IMPROVEMENT_BINS <- data.frame(
  bin_min = c(0, 5, 10, 25),
  bin_max = c(5, 10, 25, 100),
  bin_label = c("0-5%", "5-10%", "10-25%", "25%+")
)

# Data
INCLUDE_MINOR_LEAGUE <- FALSE
MINOR_LEAGUE_LEVEL <- NA
```

**These are calibration points.** If findings need adjustment or exploration, these are first places to modify.

---

## Key Files Reference

| File | Purpose | Key Outputs |
|------|---------|------------|
| `kpi_yearover_analysis.R` | Main analysis pipeline | Report markdown + CSVs |
| `reports/kpi_analysis_report.md` | Generated report | Human-readable findings |
| `data/processed/year_transitions.csv` | Detailed transition data | Raw data for drilling down |
| `data/processed/elevated_kpi_cohort.csv` | Cohort characteristics | Baseline metrics |

---

## For Next Sessions

When returning to this work, remember:

✓ Percentage-point (pp) vs percent (%) distinction is critical  
✓ Weak R² can mean "no confounding" not "no relationship"  
✓ Always separate GB and Chase models initially, then combine  
✓ Frequency analysis answers different question than regression  
✓ Use exemplars to validate and interpret statistical findings  
✓ Map all findings back to original research question  
✓ Inline code preferred over heavy modularization  
✓ Explicit field names trump brevity  

---

# Temporal Evolution Analysis: Additional Patterns
**Added:** July 2026 (Hitter Profile Evolution Project)

This section documents additional best practices learned from multi-year temporal analysis projects (e.g., tracking hitter profile evolution across bi-weekly periods).

## Multi-Year Data Handling

### Year-Independent Period Assignment
When working with data spanning multiple years, avoid hardcoding absolute dates. Instead, use month-day string comparison:

```r
# ❌ AVOID: Breaks on multi-year data
period_num = case_when(
  game_date <= as.Date("2026-04-11") ~ 1,
  game_date <= as.Date("2026-04-17") ~ 2
)

# ✓ DO: Works across all years
month_day = paste0(sprintf("%02d", month(game_date)), "-", sprintf("%02d", day(game_date)))
period_num = case_when(
  month_day < "04-11" ~ 1,
  month_day < "04-17" ~ 2,
  TRUE ~ 10
)
```

**Benefit:** Single script handles 2021-2026 data without modification. Seasons recur predictably.

### Validation for Multi-Year Processing
Always verify:
```r
cat("Date range:", min(all_statcast$game_date), "to", max(all_statcast$game_date), "\n")
cat("Years included:", unique(all_statcast$season_year), "\n")
cat("Sample distribution:\n")
print(table(all_statcast$season_year))
```

This catches data loading issues early (e.g., if only 2026 loaded instead of 2021-2026).

## Cumulative Metric Calculation Pattern

### Two-Stage Aggregation (Sums First, Then Calculations)

When calculating cumulative metrics across time periods, aggregate raw sums first, then derive metrics:

```r
# ✓ DO: Calculate cumulative sums, then convert to rates/averages
hitter_periods <- all_statcast %>%
  group_by(batter, season_year, period_num) %>%
  summarise(
    BBE = sum(is_bbe, na.rm = TRUE),
    Sum_LA = sum(launch_angle[is_bbe], na.rm = TRUE),
    Sum_Launch_Speed = sum(launch_speed[is_bbe], na.rm = TRUE),
    Count_Sweet_Spot = sum(is_sweet_spot, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(
    Cumul_BBE = cumsum(BBE),
    Cumul_Sum_LA = cumsum(Sum_LA),
    Cumul_Avg_LA = round(Cumul_Sum_LA / Cumul_BBE, 1),
    Cumul_Sweet_Spot_Pct = round(100 * cumsum(Count_Sweet_Spot) / Cumul_BBE, 1)
  )

# ❌ AVOID: Taking cumsum of already-averaged values
# This creates mathematically invalid "average of averages"
```

**Why:** Cumulative sums of raw counts are mathematically sound. Then convert to rates using cumulative totals.

### Merging Classifications After Calculation
Classify profiles AFTER aggregating, then merge back:

```r
# ✓ DO: Classify separately, merge later
hitter_full_season <- hitter_periods %>%
  group_by(batter, season_year) %>%
  summarise(...) %>%
  mutate(profile_type = case_when(
    condition_1 ~ "Caissie",
    condition_2 ~ "Raleigh",
    TRUE ~ "Other"
  ))

hitter_periods_profiled <- hitter_periods %>%
  left_join(
    hitter_full_season %>% select(batter, season_year, profile_type),
    by = c("batter", "season_year")
  )
```

**Benefit:** Avoids recalculating profile classification for every period. Single full-season classification, then propagated to period-level data.

## Type Handling in dplyr Context

### Vector Recycling in `case_when()`
When using external data (e.g., percentile thresholds) within `mutate()` + `case_when()`, coerce to list:

```r
# Data from supporting file
percentiles <- supporting_data %>%
  summarise(avg_la_70 = quantile(Avg_LA, 0.70), ...)

# ❌ AVOID: Tibble causes vector recycling error
profile_type = case_when(
  Avg_LA >= percentiles$avg_la_70 ~ "High"
)
# Error: Can't recycle `..1` (size 0) to match `..3` (size 297)

# ✓ DO: Convert to list for scalar access
percentiles <- supporting_data %>%
  summarise(...) %>%
  as.list()

profile_type = case_when(
  Avg_LA >= percentiles$avg_la_70 ~ "High"
)
```

**Key insight:** Lists return scalars; tibbles return vectors. In `case_when()` context, always use lists for threshold/cutoff data.

## Delta Calculation for Trend Analysis

### Period-to-Period Change (Identifying Improvement/Decline Patterns)
When analyzing within-season trajectories:

```r
# Calculate deltas AFTER arranging by time
df <- df %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(
    Delta_Metric = Cumul_Metric - lag(Cumul_Metric),
    .groups = "drop"
  )

# Then aggregate by profile type and period
delta_summary <- df %>%
  group_by(profile_type, period_num) %>%
  summarise(Avg_Delta = mean(Delta_Metric, na.rm = TRUE), .groups = "drop")
```

**Pattern:** This isolates improvement within each player's trajectory, then averages across profiles. Controls for baseline differences between players.

### First-to-Last Comparison (Overall Arc)
For comparing season start to finish:

```r
improvement_table <- df %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, last_first_name, season_year) %>%
  summarise(
    Start_Metric = first(Cumul_Metric),
    End_Metric = last(Cumul_Metric),
    Delta = End_Metric - Start_Metric,
    Pct_Change = (Delta / Start_Metric) * 100,
    .groups = "drop"
  )
```

**Use case:** Summary table showing each player's overall improvement trajectory.

## Visualization Evolution Best Practice

### Iterate from Detail to Insight

**Phase 1: Individual Lines** (exploratory, understand variability)
```r
ggplot(df) +
  geom_line(aes(x = period, y = metric, group = interaction(batter, year), 
                color = profile_type), alpha = 0.3)
```
→ Shows full variation; helps spot outliers and patterns across individual trajectories.

**Phase 2: Aggregated Lines** (identify profile-level trends)
```r
ggplot(df %>% group_by(profile_type, period) %>% summarise(avg_metric = mean(metric))) +
  geom_line(aes(x = period, y = avg_metric, color = profile_type))
```
→ Cleaner; shows whether profiles diverge/converge.

**Phase 3: Delta/Trend Lines** (isolate improvement mechanism)
```r
ggplot(df %>% group_by(profile_type, period) %>% summarise(avg_delta = mean(delta))) +
  geom_line(aes(x = period, y = avg_delta, color = profile_type)) +
  geom_hline(yintercept = 0, linetype = "dashed")
```
→ Shows period-to-period change rates; reveals acceleration/deceleration patterns.

**Progression:** Each visualization answers a different question. Use all three iteratively, not as final outputs.

## Configuration & Flexibility

### Calibration Points for Temporal Analysis
Document these at script head:

```r
# Temporal boundaries
SEASON_START <- "03-01"         # Month-day format for year-independence
SEASON_END <- "09-30"
ANALYSIS_PERIODS <- 10          # Number of time windows

# Data filters
MIN_PLATE_APPEARANCES <- 100    # Per-player threshold
MIN_BBE_PER_PERIOD <- 10        # Per-period threshold

# Threshold percentiles
LA_PERCENTILE <- 0.70           # 70th for launch angle profiles
SLOGAN_PERCENTILE <- 0.80       # 80th for production
```

**Why:** Makes it easy to test sensitivity without code changes. Single place to adjust all thresholds.

### Always Check File State Before Editing

Before making edits to an existing analysis script:
```r
# Terminal: Check git status to see if file was modified
git diff scripts/analyze_hitter_profile_evolution.R | head -50
```

Document any formatter changes or manual edits by others before proceeding. This prevents overwriting important modifications.

---

**Last Updated:** July 2026  
**Status:** Analysis Complete; Documentation Enhanced
