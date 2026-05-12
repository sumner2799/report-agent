# Swing Loft & Angles Stability Analysis: Research Plan

**Project:** Understanding Relationship Between Swing Loft Deficiency and Angles Metric Volatility  
**Date Initiated:** May 3, 2026  
**Primary Question:** Do hitters lacking swing loft (high opposite-field flyball rates, low opposite-field exit velocities) but achieving good sweet spot rates face elevated regression risk compared to hitters with neutral/positive loft who maintain good angles?

---

## Table of Contents

1. [Research Questions & Hypotheses](#research-questions--hypotheses)
2. [Motivation & Context](#motivation--context)
3. [Analysis Plan: Five-Step Implementation](#analysis-plan-five-step-implementation)
4. [Data Requirements & Availability](#data-requirements--availability)
5. [Metrics & Definitions](#metrics--definitions)
6. [Study Design & Cohort Definition](#study-design--cohort-definition)
7. [Further Considerations](#further-considerations)
8. [Success Criteria & Deliverables](#success-criteria--deliverables)

---

## Research Questions & Hypotheses

### Primary Research Question
**Does swing loft deficiency predict future volatility in angle metrics, conditional on current strong angles?**

Null Hypothesis (H₀):
- Swing loft status has no relationship to angles metric stability

Alternative Hypothesis (H₁):
- Hitters with poor swing loft (high oppo FB%, low oppo FB EV, low attack angle) AND good current sweet spot rates experience greater year-over-year fluctuations in angles metrics than hitters with neutral/positive loft and comparable angles

### Secondary Research Questions
1. Can we identify a reliable "swing loft proxy" using Statcast kinematics that predicts mechanical durability?
2. What is the repeatability of sweet spot rate for each loft-profile cohort across 2-3 year windows?
3. Do low-loft players achieving high sweet spot rates do so via a compressed launch angle band (e.g., 8–16°) that's more vulnerable to pitcher adjustments?
4. What is the relationship between sweet spot consistency and hard-hit rate consistency by loft profile?

---

## Motivation & Context

### Observed Pattern
Three MLB hitters display a puzzling dichotomy:

| Player | 2024 Oppo FB% | 2024 Oppo FB EV | 2024 Sweet Spot% | 2025 Status |
|--------|---------------|-----------------|------------------|-------------|
| **David Hamilton** | 65th %ile | 7th %ile | 86th %ile | ⚠️ Regressed: SS% → 20th %ile |
| **Brendan Donovan** | 87th %ile | 35th %ile | 91st %ile | ✓ Stable (2025 YTD) |
| **Spencer Horwitz** | 79th %ile | 19th %ile | 84th %ile | ? TBD (2025 YTD) |

### Key Observation
All three hitters display **indicators of poor swing plane loft**:
- High opposite-field flyball rate (weak pull-side power setup)
- Low exit velocity on opposite-field fly balls (poor ability to leverage power)
- Implication: Mechanical limitation in creating steep swing plane

**Yet all achieved ≥84th percentile sweet spot rates**, seemingly contradicting the expectation that loft deficiency and contact quality should co-move strongly.

### Theoretical Framework
Traditional contact-mechanics model:
- **Swing loft** ↑ → **Sweet spot%** ↑ (steeper plane = better chance of finding optimal launch angles)
- **Swing loft** ↓ → **Sweet spot%** ↓ (shallow plane = prone to poor contact angles)

**Challenge to model:** If loft and sweet spot are mechanically linked, how do low-loft players sustain high sweet spot rates? And if they can, are they fragile to year-over-year regression?

### Hypothesis
- Low-loft players achieving high sweet spot rates may be employing **compensatory mechanics** (e.g., superior timing, feel, or approach sequencing) that are **less stable** than loft-based mechanics.
- In contrast, players with neutral/positive loft and good angles have a **structural advantage** in maintaining consistency—their mechanics provide a more repeatable platform.
- Prediction: Low-loft/high-SS players show higher year-over-year volatility in angles metrics than neutral/positive-loft/good-angles players.

---

## Analysis Plan: Five-Step Implementation

### Step 1: Build Historical Multi-Year Player Dataset (2023–2025+)

**Objective:** Construct comprehensive player-season profiles with angle and approach metrics across multiple years.

**Data Sources:**
- Raw Statcast CSVs (already available for 2026; need to acquire or access 2023–2025)
- Supporting percentile reference data (already available: `batter_profile_overall.csv`)
- MiLB Statcast (if tracking players pre-MLB)

**Deliverable: `angles_history_player_season.csv`**

Columns (aggregated by player-season):
- `last_first_name` (char): Player name, format "Last, First"
- `season` (num): Year (2023, 2024, 2025, etc.)
- `min_bbe` (num): Minimum BBE threshold (recommend ≥150 for season-level stability)
- **Opposite-field metrics:**
  - `oppo_fb_pct` (num): % of fly balls to opposite field
  - `oppo_fb_ev` (num): Avg exit velocity on oppo FB (mph)
  - `oppo_fb_ev_pct_rank` (num): Percentile rank vs. league (for comparison to David Hamilton's 7th %ile reference)
- **Attack-angle (proxy for swing loft):**
  - `attack_angle_avg` (num): Average attack angle (degrees)
  - `high_aa_pct` (num): % of pitches with attack angle ≥ 14° (proxy for steep plane)
- **Sweet spot & launch angle quality:**
  - `sweet_spot_pct` (num): % of BBE with LA 8–32°
  - `sweet_spot_pct_rank` (num): Percentile rank
  - `launch_angle_avg` (num): Average LA (degrees)
  - `launch_angle_std_dev` (num): Std dev of LA (contact consistency metric)
  - `la_8_16_pct` (num): % of BBE in lower sweet spot band (8–16°)
  - `la_17_32_pct` (num): % of BBE in upper sweet spot band (17–32°)
- **Contact quality (secondary outcomes):**
  - `hard_hit_pct` (num): % of BBE with EV ≥ 95 mph
  - `barrel_pct` (num): % of BBE meeting barrel criteria
  - `avg_exit_velocity` (num): Mean EV across all BBE

**Processing notes:**
- Filter to minimum 150 BBEs per player-season to avoid noise from low-volume players
- For 2026 (ongoing season), aggregate through May 1 cutoff to allow fair comparison
- Use `is_middle_zone()` logic from existing scripts *OR* use all pitches depending on scope (recommend all pitches for this analysis, but document choice)

---

### Step 2: Classify Players by Loft Profile

**Objective:** Create a reproducible classification system that segments players into loft-based cohorts, enabling comparison of stability across loft categories.

**Method: Composite Loft Proxy Score**

Create a **loft_deficiency_score** (range 0–1, higher = worse loft):

```
loft_deficiency_score = (
  (oppo_fb_pct_rank / 100) * 0.40 +
  ((100 - oppo_fb_ev_pct_rank) / 100) * 0.35 +
  ((100 - high_aa_pct_rank) / 100) * 0.25
)
```

**Rationale for weights:**
- `oppo_fb_pct` (40%): Strongest indicator of loft struggle—pull-side power setup
- `oppo_fb_ev` (35%): Quality of opposite-field contact when it happens
- `high_aa_pct` (25%): Attack angle (proxy for swing plane steepness)

**Cohort Definitions (applying to each player-season):**

| Cohort | Loft Score | Definition | Business Meaning |
|--------|-----------|-----------|------------------|
| **Good Loft** | < 0.35 | ≤35th %ile on composite | Structural advantage; steeper swing planes |
| **Neutral Loft** | 0.35–0.60 | 35th–60th %ile | Average loft mechanics |
| **Poor Loft** | > 0.60 | >60th %ile | Deficiency in swing plane loft |

**Angle Performance Classification (orthogonal to loft):**

| Angles Tier | Sweet Spot %ile | Definition |
|------------|-----------------|-----------|
| **Excellent** | ≥75th %ile | High-quality contact rate |
| **Good** | 60–74th %ile | Above-average contact |
| **Average** | 40–59th %ile | League-average contact |
| **Below Avg** | <40th %ile | Weak contact profile |

**Interaction Cohorts of Interest:**

| Cohort Name | Loft | Angles | Example Players | Hypothesis |
|-------------|------|--------|-----------------|-----------|
| **"Compensators"** | Poor | Excellent | Hamilton, Horwitz, Donovan | HIGH volatility expected; fragile mechanics |
| **"Structural"** | Neutral/Good | Excellent | (to be identified) | LOW volatility expected; durable mechanics |
| **"Rebuilders"** | Poor | Average | (to be identified) | Moderate volatility; room to improve |
| **"Underperformers"** | Neutral/Good | Average | (to be identified) | Should trend upward; untapped potential |

**Deliverable: `loft_profile_classification.csv`**
- Same granularity as Step 1 output
- Add columns: `loft_deficiency_score`, `loft_cohort`, `angles_tier`, `interaction_cohort`

---

### Step 3: Calculate Multi-Year Stability Metrics

**Objective:** Quantify year-over-year volatility and repeatability for each player-season transition, enabling cohort-level comparison of stability.

**Stability Metrics (calculated for each player's transitions: Year N → Year N+1):**

#### Metric 3.1: Year-Over-Year Change (Absolute)
```
ss_yoy_change = sweet_spot_pct_year(N+1) - sweet_spot_pct_year(N)  [pp]
la_avg_yoy_change = la_avg_year(N+1) - la_avg_year(N)  [degrees]
hh_yoy_change = hard_hit_pct_year(N+1) - hard_hit_pct_year(N)  [pp]
```

**Interpretation:** Direct year-over-year swing; negative = regression on that metric.

#### Metric 3.2: Volatility Index (Year N vs Year N+1 vs Year N+2, if available)
```
ss_volatility_3yr = std_dev(sweet_spot_pct[year N, N+1, N+2])  [pp]
la_consistency_3yr = std_dev(launch_angle_avg[year N, N+1, N+2])  [degrees]
hh_consistency_3yr = std_dev(hard_hit_pct[year N, N+1, N+2])  [pp]
```

**Interpretation:** Across multi-year window, how much do these metrics fluctuate? Lower volatility = more repeatable.

#### Metric 3.3: Regression Probability
```
regressed_ss = 1 if (ss_yoy_change < -5pp), else 0  [binary; -5pp = threshold for meaningful regression]
regressed_any = 1 if any(ss_yoy_change < -5pp OR la_yoy_change < -2deg OR hh_yoy_change < -3pp), else 0
```

**Interpretation:** Did player experience significant decline in Year N+1 relative to Year N?

#### Metric 3.4: Consistency Score (composite)
```
consistency_score = [
  (1 - ss_volatility_3yr / league_ss_volatility_avg) * 0.40 +
  (1 - la_consistency_3yr / league_la_consistency_avg) * 0.30 +
  (1 - hh_consistency_3yr / league_hh_consistency_avg) * 0.30
]  [range 0–1; 1 = most consistent]
```

**Rationale:**
- Sweet spot consistency weighted highest (your primary metric)
- Normalized to league average to account for year-to-year variability in league-wide metrics
- Composite score enables ranking players by overall angles stability

**Deliverable: `stability_transitions.csv`**

Columns (one row = one player-season transition):
- `last_first_name`, `prior_year`, `current_year`
- `loft_cohort_year_n`, `angles_tier_year_n` (from Year N classification)
- `ss_yoy_change`, `la_avg_yoy_change`, `hh_yoy_change`
- `ss_volatility_3yr`, `la_consistency_3yr`, `hh_consistency_3yr`
- `consistency_score`
- `regressed_ss`, `regressed_any`

---

### Step 4: Identify & Characterize Bucking Cases

**Objective:** Validate hypothesis by examining the three focal players (Hamilton, Donovan, Horwitz) and expanding to a broader cohort of similar players.

**Hamilton, Donovan, Horwitz Deep Dive:**

1. **Locate in dataset:** Extract multi-year records (2023–2025 minimum) and classify loft profiles
2. **Verify percentile ranks:** Confirm your provided 2024/2025 stats match Statcast-derived ranks
3. **Characterize volatility:**
   - Hamilton: Expected HIGH volatility (poor loft → regression from 86th to 20th SS%ile)
   - Donovan: Expected STABLE (poor loft but maintaining 91st SS%ile in 2025)
   - Horwitz: Expected EARLY signal (currently 84th SS%ile; monitor 2025→2026 trend)
4. **Mechanistic breakdown:**
   - For each, decompose SS% gains into **LA band shifts** (e.g., did they shift from 8–16° to 17–32°?)
   - Compare opponent pitcher adjustments year-over-year if available
   - Flag any external factors (injury, coaching changes, ballpark effects)

**Cohort Expansion to "Compensators":**

Define **Compensators cohort** as:
- Poor loft (`loft_deficiency_score` > 0.60) +
- Excellent angles (`sweet_spot_pct` ≥ 75th %ile) +
- Minimum 150 BBEs per season

**Analysis:**
1. How many player-seasons fit this profile (2023–2025)?
2. Among transitions (Year N → N+1), what % regressed in sweet spot >5pp?
3. Compare regression frequency to **Structural cohort** (neutral/good loft + excellent angles):
   - Hypothesis: Compensators regress at higher rate (e.g., 35% vs. 15%)

**Deliverable: `bucking_cases_validation.csv`**
- Player-specific deep dives + cohort-level comparison summary
- Includes: player, years, loft score, SS% trend, consistency score, regression event

---

### Step 5: Model Regression Drivers

**Objective:** Quantify whether loft deficiency predicts future angles volatility, controlling for current angles and other confounders.

**Regression Model Family 1: Do Loft Deficits Predict Regression Risk?**

**Outcome variable:** `regressed_ss_yoy` (binary: did sweet spot decline >5pp in Year N+1?)

```
logit(P(regressed_ss | year N)) = 
  β₀ + 
  β₁ * loft_deficiency_score_year_n +
  β₂ * sweet_spot_pct_rank_year_n +
  β₃ * consistency_score_year_n +
  β₄ * sample_size_year_n +
  ε
```

**Interpretation:**
- **β₁ > 0, significant:** Loft deficiency increases odds of regression (supports hypothesis)
- **β₁ ≈ 0:** Loft status irrelevant to future volatility (rejects hypothesis)

**Regression Model Family 2: Loft as Moderator of SS% Stability**

```
ss_volatility_year_n_to_n2 ~ 
  loft_deficiency_score_year_n +
  sweet_spot_pct_year_n +
  hard_hit_pct_year_n +
  launch_angle_std_dev_year_n +
  sample_size_year_n +
  error_term
```

**Outcome:** Continuous `ss_volatility` (std dev of SS% across years)
**Interpretation:** 
- Positive coefficient on loft deficiency = poor loft players show higher future volatility
- Allows ranking cohorts by expected stability

**Regression Model Family 3: Decompose SS% Gains by LA Band (Low-Loft Fragility Check)**

```
For players with loft_deficiency_score > 0.60 AND year_n ss_pct_rank >= 75th:
  ss_yoy_change ~ 
    la_8_16_pct_year_n +
    la_17_32_pct_year_n +
    oppo_fb_pct_year_n +
    sample_size_year_n +
    error_term
```

**Interpretation:**
- If coefficient on `la_8_16_pct` is strongly negative (fragile) vs. `la_17_32_pct` stable, suggests low-loft players relying on narrow band
- Tests whether compression into lower LA band makes them vulnerable to pitcher adjustments

**Deliverable: `regression_models_summary.csv` + plots**
- Model results (coefficients, p-values, R²) for each family
- Predicted probabilities of regression by loft cohort
- Interaction visualizations (loft × sweet_spot_pct on predicted regression risk)

---

## Data Requirements & Availability

### Current Status (as of May 3, 2026)

| Data | Available? | Notes |
|------|-----------|-------|
| **2026 Statcast (YTD)** | ✅ Yes | 65,278+ records across multiple weeks |
| **2023–2024 Historical Statcast** | ❓ TBD | Referenced in documentation but raw CSVs not verified |
| **2025 Statcast** | ❓ TBD | Needed for Hamilton/Horwitz 2025 validation |
| **Percentile benchmarks** | ✅ Yes | `batter_profile_overall.csv` (374 batters) |
| **Zone-specific metrics** | ✅ Yes | `batter_zone_overall.csv` available |
| **MiLB Statcast** | ✅ Yes | Available (if pre-MLB context needed) |

### Data Acquisition Needs

1. **Multi-year Statcast archive (2023–2025):**
   - Check if available in `data/raw/` or via Baseball Savant download
   - Minimum requirement: 2023, 2024, 2025 full seasons for David Hamilton, Brendan Donovan, Spencer Horwitz
   - Ideally: 2023–2025 for ALL hitters (enables broader cohort analysis)

2. **Custom percentile benchmarks (2023–2025):**
   - Current `batter_profile_overall.csv` appears to be 2026 season only
   - Will need to generate historical benchmarks per season for fair percentile rank comparison
   - Example: David Hamilton's "7th percentile oppo FB EV" in 2024 requires 2024-specific benchmarks

3. **Pitcher adjustment tracking (optional, advanced):**
   - Identify pitcher types faced by focal players year-over-year
   - Test whether pitch-mix adjustments explain volatility (beyond scope of initial plan, but noted for future)

---

## Metrics & Definitions

### Core Angle Metrics (Statcast-derived)

| Metric | Definition | Calc | Interpretation |
|--------|-----------|------|-----------------|
| **Launch Angle (LA)** | Vertical angle of batted ball relative to ground (degrees) | Statcast direct | ↑ LA = more loft; 0° = line drive; negative = ground ball |
| **Sweet Spot %** | % of BBE with LA 8–32° | (count BBE w/ 8≤LA≤32) / total_bbe | Higher = more optimal contact angles |
| **Attack Angle** | Angle of swing plane at ball contact | Statcast direct | ↑ Angle = steeper swing plane (indicator of loft) |
| **High AA %** | % of pitches with attack angle ≥ 14° | (count pitches w/ AA≥14) / total_pitches | Proxy for swing loft; >14° considered steep |
| **Exit Velocity (EV)** | Speed of batted ball off bat | Statcast direct | ↑ EV = harder contact; ≥95 mph = "hard hit" |
| **Oppo FB %** | % of fly balls to opposite field | (count oppo FB) / total_FB | ↑ % = weak pull-side power setup |
| **Oppo FB EV** | Avg exit velocity on opposite-field fly balls | avg EV on oppo FB | Lower = poorer quality opposite-field contact |
| **Barrel %** | % of BBE meeting barrel criteria (EV ≥ 92 + LA 26–30°) | Statcast direct | Higher = more optimal barrels |
| **Hard Hit %** | % of BBE with EV ≥ 95 mph | (count EV≥95) / total_bbe | Higher = more forceful contact |

### Derived Stability Metrics

| Metric | Definition | Range | Interpretation |
|--------|-----------|-------|-----------------|
| **YoY Change (pp)** | Absolute percentage-point swing in metric year-over-year | -∞ to +∞ | Positive = improvement; negative = regression |
| **Volatility (pp or degrees)** | Standard deviation across multiple years (3-year window) | 0 to ∞ | Higher = less repeatable; lower = more stable |
| **Consistency Score** | Normalized composite of volatility across SS%, LA avg, HH% | 0 to 1 | 1.0 = most consistent vs. league average |
| **Regression Event (binary)** | Did metric decline >5pp (or >2° for LA) year-over-year? | 0 or 1 | 1 = significant decline; 0 = stable/improved |

### Loft Proxy Metrics

| Metric | Component | Interpretation |
|--------|-----------|-----------------|
| **Loft Deficiency Score** | Composite of oppo FB%, oppo FB EV, high AA% | 0–1 scale; >0.60 = poor loft |
| **Attack Angle Avg** | Mean attack angle across all pitches | Degrees; >14° average = steeper plane |
| **Oppo Power Setup** | Oppo FB% (high) + Pull FB% (low) | Indicates weak pull-side mechanics |

---

## Study Design & Cohort Definition

### Inclusion Criteria

**For all analyses:**
- Minimum 150 BBEs per player-season (ensure statistical reliability)
- Appeared in MLB during 2023–2025+ (or 2026 YTD for current season)
- Complete Statcast kinematics data (launch angle, exit velocity, attack angle, etc.)
- At least one full season of data to establish baseline profile

**For transition analysis (Year N → Year N+1):**
- Same player appears in consecutive seasons
- Both years meet BBE minimum threshold
- Data collected through comparable calendar period (e.g., through May 1 for 2026)

### Focal Cohorts for Comparison

**Primary (Hypothesis Testing):**

1. **"Compensators"** (Poor Loft + Excellent Angles)
   - Loft deficiency score > 0.60
   - Sweet spot %ile ≥ 75th
   - Expected: Higher regression frequency & volatility

2. **"Structural"** (Neutral/Good Loft + Excellent Angles)
   - Loft deficiency score ≤ 0.60
   - Sweet spot %ile ≥ 75th
   - Expected: Lower regression frequency & volatility

**Secondary (Context):**

3. **"Rebuilders"** (Poor Loft + Average/Below-Avg Angles)
   - Loft deficiency score > 0.60
   - Sweet spot %ile < 60th
   - Q: Do they improve over time? Show high volatility?

4. **"Underperformers"** (Neutral/Good Loft + Average Angles)
   - Loft deficiency score ≤ 0.60
   - Sweet spot %ile 40–59th
   - Q: Should improve as approach matures?

### Sample Size Considerations

- **Anticipated "Compensators" cohort:** 20–40 player-seasons (subject to verification)
- **Anticipated "Structural" cohort:** 50–100 player-seasons
- **Powered to detect:** 15pp difference in regression frequency (Compensators 35% vs Structural 20%), α = 0.05, β = 0.20

---

## Further Considerations

### 1. Threshold & Parameter Sensitivity
- **Sweet spot range (8–32°):** Standard definition, but test sensitivity to alternative ranges (e.g., 10–30°)
- **Regression threshold (5pp, 2° LA, 3pp HH%):** Chosen as "meaningful" but subject to sensitivity analysis
- **Percentile cutoffs (75th for excellent, 60th for poor loft):** Test robustness by shifting by ±5–10 percentile points
- **Recommendation:** Run sensitivity analysis across thresholds; present findings as ranges

### 2. Mechanical Validation
- **Limitation:** Statcast kinematics alone cannot directly measure "swing plane loft" from video
- **Workaround:** Use attack angle as proxy, but acknowledge this is indirect
- **Enhancement (if available):** Cross-reference with TrackMan or K-Vest swing data, or coach notes on mechanical changes
- **Recommendation:** Document that "loft proxy" is not direct measurement; results should be framed accordingly

### 3. Pitcher Adjustment & Context Control
- **Confound:** Pitcher strategies change year-over-year (more/fewer fastballs, pitch sequencing)
- **Partial control:** Compare pitch-type mix faced each year; test whether regression predicts even controlling for pitch mix
- **Limitation:** Cannot control for all contextual variables (ballpark, league-wide adjustments, etc.)
- **Recommendation:** Acknowledge this limitation; frame findings as "conditional on similar competitive environment"

### 4. Sample Size & Regression to Mean
- **Risk:** High sweet spot rates may regress toward mean naturally (regression to mean), independent of loft status
- **Mitigation:** Fit a "naive regression model" (predict future SS% from prior SS% alone), then compare Compensator vs. Structural residuals
- **Interpretation:** If Compensators over-regress even controlling for prior SS%, that's evidence of loft-based fragility

### 5. Alternative Explanations for Hamilton Regression
Before attributing Hamilton's 2024→2025 regression to loft deficiency, investigate:
- **Injury/mechanics change:** Did he undergo mechanical coaching or sustain injury between 2024 and 2025?
- **Pitch-mix adjustment:** Did opposing pitchers throw fewer fastballs, more breaking balls in 2025?
- **Ballpark effect:** Did he move teams or see significant home-field usage change?
- **Sample timing:** Was his 2025 data collected through May 1 (early season) vs. full 2024 season? Early-season volatility is normal
- **Recommendation:** Document these contextual factors in case study

### 6. Repeatability of Poor-Loft-Good-Angles Phenotype
- **Question:** How many players fit the "Compensators" profile in each season?
- **Implication:** If rare (e.g., 2–3 players per year), findings may have limited generalizability
- **Recommendation:** Report cohort size; if small, frame analysis as exploratory / case-study based rather than definitive

---

## Success Criteria & Deliverables

### Phase 1 Deliverables (Data & Classification)

- [ ] `angles_history_player_season.csv` (multi-year player profiles)
- [ ] `loft_profile_classification.csv` (loft scores, cohort assignments)
- [ ] Data documentation memo (data quality checks, any filtering decisions)

### Phase 2 Deliverables (Stability Analysis)

- [ ] `stability_transitions.csv` (YoY changes, volatility metrics, consistency scores)
- [ ] Descriptive statistics by cohort (Compensators vs. Structural: mean SS%, mean volatility, regression frequency)
- [ ] Summary table comparing focal players (Hamilton, Donovan, Horwitz) to cohort benchmarks

### Phase 3 Deliverables (Validation & Deep Dives)

- [ ] `bucking_cases_validation.csv` (focal player case studies + cohort expansion)
- [ ] Supplementary analysis memo (mechanistic breakdowns, LA band decomposition, context checks)

### Phase 4 Deliverables (Modeling & Final Analysis)

- [ ] `regression_models_summary.csv` (coefficients, significance, R² for all model families)
- [ ] Model visualizations (predicted regression risk by loft score; volatility by cohort)
- [ ] Final research report (methods, findings, limitations, implications for player evaluation)

### Success Criteria

**For hypothesis support:**
- ✅ Loft deficiency score predicts regression risk (β₁ > 0, p < 0.05)
- ✅ Compensators cohort shows >10pp higher regression frequency than Structural cohort
- ✅ Volatility metrics (std dev, consistency score) higher for Compensators
- ✅ Hamilton's 2024→2025 regression fits Compensator pattern; Donovan's stability counter-example is explainable

**For hypothesis rejection:**
- ❌ Loft deficiency score not predictive of regression (β₁ ≈ 0, p > 0.10)
- ❌ Compensators and Structural cohorts show similar regression frequencies
- ❌ Hamilton's regression better explained by pitcher adjustments, injury, or sample timing than loft fragility

**Interim findings of value:**
- Even if primary hypothesis not supported, characterize which players within each cohort are stable vs. volatile
- Identify alternative predictors of angles metric durability (e.g., hard-hit rate consistency, LA std dev)
- Document lessons learned for future player evaluation frameworks

---

## Next Steps

1. **Verify data availability:** Confirm 2023–2025 Statcast CSVs are accessible; scope data acquisition if needed
2. **Create processing pipeline:** Build R script(s) to execute Steps 1–2 above; output Step 1–2 deliverables
3. **Validate focal players:** Extract Hamilton, Donovan, Horwitz data; confirm provided percentile ranks match Statcast
4. **Execute cohort analysis:** Complete Steps 3–5; generate all deliverables and summary statistics
5. **Iterate based on findings:** If major patterns emerge or questions arise, adjust analysis plan mid-project

---

**Document Version:** 1.0  
**Last Updated:** May 3, 2026  
**Author:** Analysis Planning Session  
**Status:** Ready for implementation
