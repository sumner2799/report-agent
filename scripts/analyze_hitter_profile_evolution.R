# Hitter Profile Evolution & Production Patterns Analysis
# =============================================================================
# Purpose: Segment MLB hitters into profile archetypes based on ratio-based
#          launch angle and production metrics, track evolution across bi-weekly
#          snapshots, and identify normalization/regression patterns.
#
# Key Questions Addressed:
#  - Do Caissie-type profiles (good rates, poor output) normalize within season?
#  - Do Raleigh-types (good loft, low sweet spot %) improve as expected?
#  - Why do Moniak-types outperform similar profiles?
#  - Can Watson-type profiles leverage quality metrics for further gains?
#
# Output: Summary visualizations, comparison tables, evolution trajectories
# =============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(gridExtra)
library(RMySQL)
library(lubridate)
library(baseballr)
library(stringr)

# Set working directory
setwd("/Users/andrewsumner/Documents/Github/report-agent")

# =============================================================================
# 1. LOAD AND STRUCTURE BI-WEEKLY SNAPSHOTS
# =============================================================================

# Define bi-weekly boundaries (approximate mid-points for clean windows)
# statcast_files <- list.files("data/raw", pattern = "^statcast_2026.*\\.csv$", full.names = TRUE) %>% sort()

# cat("Loading statcast data from", length(statcast_files), "files...\n")

# # Read all statcast files and combine
# all_statcast <- map_df(statcast_files, function(file) {
#   read_csv(file, show_col_types = FALSE) %>%
#     mutate(
#       game_date = as.Date(game_date),
#       launch_angle = as.numeric(launch_angle),
#       launch_speed = as.numeric(launch_speed),
#       description = as.character(description)
#     )
# }) %>%
#   filter(!is.na(launch_speed) & !is.na(launch_angle) & !is.na(batter)) %>%
#   arrange(game_date)

# cat("Total records:", nrow(all_statcast), "\n")
# cat("Date range:", min(all_statcast$game_date), "to", max(all_statcast$game_date), "\n")

conn <- dbConnect(
  MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

all_statcast <- dbGetQuery(conn,glue::glue(
  "
with players as (
select
batter,
year(game_date) as season_year,
ROUND(AVG(launch_angle), 1) AS avg_la,
ROUND(100 * (SUM(CASE WHEN launch_angle >= 8 AND launch_angle <= 32 THEN 1 ELSE 0 END) / COUNT(*)), 1) AS sw_spot,
ROUND(AVG(CASE WHEN launch_speed >= 95 THEN launch_angle END), 1) AS hh_la,
ROUND(100 * (SUM(CASE WHEN attack_angle >= 14 THEN 1 ELSE 0 END) / 
               SUM(CASE WHEN attack_angle IS NOT NULL THEN 1 ELSE 0 END)), 1) AS high_aa,
count(*) as tot
from sc_mlb 
where 
game_type = 'R'
and description = 'hit_into_play'
AND (MONTH(game_date) IN (3,4,5) OR (MONTH(game_date) = 6 AND DAY(game_date) < 15))
AND LOWER(des) NOT LIKE '%bunt%'
group by batter, year(game_date)
)

select
m.*
from 
sc_mlb m
join players p
on m.batter = p.batter
and year(m.game_date) = p.season_year
and p.avg_la >= 16
and p.hh_la >= 14.9
and p.tot >= 80

  ",
  .con = conn
  )
)

players <- try(mlb_sports_players(sport_id = 1, season = 2026))
    all_statcast <- left_join(all_statcast,players,by=c("batter"="player_id"))

all_statcast$launch_speed <- as.numeric(all_statcast$launch_speed)
all_statcast$launch_angle <- as.numeric(all_statcast$launch_angle)
all_statcast$hc_x <- as.numeric(all_statcast$hc_x)
all_statcast$hc_y <- as.numeric(all_statcast$hc_y)
all_statcast$estimated_slg_using_speedangle <- as.numeric(all_statcast$estimated_slg_using_speedangle)

# Create bi-weekly period assignments based on game_date (year-independent)
# Period 1: Everything before June 14th
# Periods 2-10: Bi-weekly from June 14th through end of September
all_statcast <- all_statcast %>%
  filter(game_type == "R") %>%
  mutate(
    season_year = year(game_date),
    month_day = paste0(sprintf("%02d", month(game_date)), "-", sprintf("%02d", day(game_date))),
    period_num = case_when(
      # month_day < "06-21" ~ 1,
      month_day < "06-15" ~ 1,
      month_day < "06-28" ~ 2,
      month_day < "07-12" ~ 3,
      month_day < "07-26" ~ 4,
      month_day < "08-09" ~ 5,
      month_day < "08-23" ~ 6,
      month_day < "09-06" ~ 7,
      month_day < "09-20" ~ 8,
      month_day < "10-04" ~ 9,
      TRUE ~ 10
    ),
    is_bbe = description == "hit_into_play",
    is_sweet_spot = launch_angle >= 8 & launch_angle <= 32 & description == "hit_into_play",
    is_hard_hit = launch_speed >= 95 & description == "hit_into_play",
    is_hard_hit_sweet_spot = is_hard_hit & is_sweet_spot,
    high_launch_angle = launch_angle > 32
  )

  raw_salvy <- all_statcast %>%
  filter(last_first_name == "Perez, Salvador", season_year == 2026) %>%
  select(game_date, description, launch_speed, launch_angle, is_bbe, is_sweet_spot, is_hard_hit, is_hard_hit_sweet_spot, high_launch_angle)

# Aggregate metrics by hitter, season year, and bi-weekly period
# hitter_periods <- all_statcast %>%
#   group_by(batter, last_first_name, season_year, period_num) %>%
#   summarise(
#     BBE = sum(is_bbe, na.rm = TRUE),
#     Avg_LA = round(mean(launch_angle[is_bbe], na.rm = TRUE), 1),
#     HH_LA = round(mean(launch_angle[is_bbe & is_hard_hit], na.rm = TRUE), 1),
#     Sweet_Spot_Pct = round(100 * sum(is_sweet_spot, na.rm = TRUE) / sum(is_bbe, na.rm = TRUE), 1),
#     Hard_Hit_Pct = round(100 * sum(is_hard_hit, na.rm = TRUE) / sum(is_bbe, na.rm = TRUE), 1),
#     # METRIC SWAP: Change launch_speed to xwOBA if preferred
#     SLG = round(mean(launch_speed[is_bbe], na.rm = TRUE), 2),
#     High_AA_Pct = round(100 * sum(launch_angle >= 14, na.rm = TRUE) / sum(is_bbe, na.rm = TRUE), 1),
#     High_LA_Pct = round(100 * sum(high_launch_angle, na.rm = TRUE) / sum(is_bbe, na.rm = TRUE), 1),
#     .groups = "drop"
#   ) %>%
#   filter(BBE >= 10)  # Minimum 10 BBE per period for signal clarity

words_to_remove <- c("bunt")

hitter_periods <- all_statcast %>%
  filter(!str_detect(des, paste(words_to_remove, collapse = "|"))) %>%
  # filter(period_num < 10) %>%
  group_by(batter, last_first_name, season_year, period_num) %>%
  summarise(
    BBE = sum(is_bbe, na.rm = TRUE),
    Sum_AirBalls = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive"), na.rm = TRUE),
    Sum_GB = sum(is_bbe & bb_type %in% c("ground_ball"), na.rm = TRUE),
    Sum_Air32 = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive") & launch_angle > 32, na.rm = TRUE),
    Sum_Airless32 = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive") & launch_angle <= 32, na.rm = TRUE),
    Has_AA = sum(!is.na(attack_angle) & is_bbe, na.rm = TRUE),
    Sum_LA = sum(launch_angle[is_bbe], na.rm = TRUE),
    Sum_HH_LA = sum(launch_angle[is_bbe & is_hard_hit], na.rm = TRUE),
    Sum_SLG = ((1*sum(events == "single" & is_bbe == 1,na.rm = T))+(2*sum(events == "double" & is_bbe == 1,na.rm = T))+
                                      (3*sum(events == "triple" & is_bbe == 1,na.rm = T))+
                                      (4*sum(events == "home_run" & is_bbe == 1,na.rm = T))),
    Sum_xSLG = sum(estimated_slg_using_speedangle[is_bbe], na.rm = TRUE),
    Sum_AirSLG = ((1*sum(events == "single" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+(2*sum(events == "double" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+
                                      (3*sum(events == "triple" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+
                                      (4*sum(events == "home_run" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))),
    Sum_AirxSLG = sum(estimated_slg_using_speedangle[is_bbe & bb_type %in% c("fly_ball", "line_drive")], na.rm = TRUE),
    Count_HH = sum(is_hard_hit, na.rm = TRUE),
    Count_Sweet_Spot = sum(is_sweet_spot, na.rm = TRUE),
    Sum_Launch_Speed = sum(launch_speed[is_bbe], na.rm = TRUE),
    Count_High_AA = sum(attack_angle >= 14 & is_bbe == 1 & !is.na(attack_angle), na.rm = TRUE),
    Count_High_LA = sum(high_launch_angle, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  filter(BBE >= 10) %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(
    # Cumulative raw sums
    Cumul_BBE = cumsum(BBE),
    Cumul_GB = cumsum(Sum_GB),
    Cumul_AirBalls = cumsum(Sum_AirBalls),
    Cumul_Air32 = cumsum(Sum_Air32),
    Cumul_Airless32 = cumsum(Sum_Airless32),
    cumul_Has_AA = cumsum(Has_AA),
    Cumul_Sum_LA = cumsum(Sum_LA),
    Cumul_Sum_HH_LA = cumsum(Sum_HH_LA),
    Cumul_Sum_AirSLG = cumsum(Sum_AirSLG),
    Cumul_Sum_AirxSLG = cumsum(Sum_AirxSLG),
    Cumul_Sum_SLG = cumsum(Sum_SLG),
    Cumul_Sum_xSLG = cumsum(Sum_xSLG),
    Cumul_Count_HH = cumsum(Count_HH),
    Cumul_Count_Sweet_Spot = cumsum(Count_Sweet_Spot),
    Cumul_Sum_Launch_Speed = cumsum(Sum_Launch_Speed),
    Cumul_Count_High_AA = cumsum(Count_High_AA),
    Cumul_Count_High_LA = cumsum(Count_High_LA),
    # Period-level metrics
    Avg_LA = round(Sum_LA / BBE, 1),
    HH_LA = round(Sum_HH_LA / Count_HH, 1),
    Sweet_Spot_Pct = round(100 * Count_Sweet_Spot / BBE, 1),
    Hard_Hit_Pct = round(100 * Count_HH / BBE, 1),
    SLG = round(Sum_SLG / BBE, 3),
    xSLG = round(Sum_xSLG / BBE, 3),
    SLG_Air = round(Sum_AirSLG / Sum_AirBalls, 3),
    xSLG_Air = round(Sum_AirxSLG / Sum_AirBalls, 3),
    Air32_Pct = round(100 * Sum_Air32 / BBE, 1),
    Under32_Pct = round(100 * Sum_Airless32 / BBE, 1),
    gb_pct = round(100 * Sum_GB / BBE, 1),
    High_AA_Pct = round(100 * (Count_High_AA / Has_AA), 1),
    High_LA_Pct = round(100 * Count_High_LA / BBE, 1),
    # Cumulative metrics derived from cumulative sums
    Cumul_Avg_LA = round(Cumul_Sum_LA / Cumul_BBE, 1),
    Cumul_HH_LA = round(Cumul_Sum_HH_LA / Cumul_Count_HH, 1),
    Cumul_Sweet_Spot_Pct = round(100 * Cumul_Count_Sweet_Spot / Cumul_BBE, 1),
    Cumul_Hard_Hit_Pct = round(100 * Cumul_Count_HH / Cumul_BBE, 1),
    Cumul_SLG = round(Cumul_Sum_SLG / Cumul_BBE, 3),
    Cumul_xSLG = round(Cumul_Sum_xSLG / Cumul_BBE, 3),
    Cumul_High_AA_Pct = round(100 * (Cumul_Count_High_AA / cumul_Has_AA), 1),
    Cumul_Air32_Pct = round(100 * Cumul_Air32 / Cumul_BBE, 1),
    Cumul_Under32_Pct = round(100 * Cumul_Airless32 / Cumul_BBE, 1),
    Cumul_GB_Pct = round(100 * Cumul_GB / Cumul_BBE, 1),
    Cumul_AirSLG = round(Cumul_Sum_AirSLG / Cumul_AirBalls, 3),
    Cumul_AirxSLG = round(Cumul_Sum_AirxSLG / Cumul_AirBalls, 3),
    .groups = "drop"
  ) %>%
  select(batter, last_first_name, season_year, period_num, BBE, Avg_LA, HH_LA, Sweet_Spot_Pct, Hard_Hit_Pct, SLG, xSLG, 
         Cumul_Avg_LA, Cumul_HH_LA, Cumul_Sweet_Spot_Pct, Cumul_Hard_Hit_Pct, Cumul_SLG, Cumul_xSLG, Cumul_High_AA_Pct, Cumul_AirSLG, Cumul_AirxSLG, Air32_Pct, Under32_Pct, Cumul_Air32_Pct, Cumul_Under32_Pct, gb_pct, Cumul_GB_Pct) %>%
  filter(BBE >= 10)  # Minimum 10 BBE per period for signal clarity

  salvy <- hitter_periods %>%
  filter(last_first_name == "Perez, Salvador", season_year == 2026)

# Calculate total BBE per hitter per year across all periods
hitter_totals <- hitter_periods %>%
  group_by(batter, last_first_name, season_year) %>%
  summarise(total_BBE = sum(BBE), .groups = "drop") %>%
  filter(total_BBE >= 100)  # Minimum 100 BBE total per year

cat("Hitters with 100+ BBE:", nrow(hitter_totals), "\n")

# Filter periods to only include hitters meeting minimum threshold
hitter_periods_filtered <- hitter_periods %>%
  semi_join(hitter_totals, by = c("batter", "season_year"))

cat("Total hitter-period observations:", nrow(hitter_periods_filtered), "\n")

# =============================================================================
# 2. CALCULATE PERCENTILE RANKS FOR PROFILE CLASSIFICATION
# =============================================================================

# Load supporting data for percentile comparisons
supporting_data <- read_csv("data/supporting/batter_overall_overall.csv", show_col_types = FALSE) %>%
  select(last_first_name, `Avg LA`, `Sweet Spot%`, `HH LA`, `High AA%`, `SLGcon`, `HH%`) %>%
  rename(
    batter_name = last_first_name,
    avg_la = `Avg LA`,
    sweet_spot_pct = `Sweet Spot%`,
    hh_la = `HH LA`,
    high_aa_pct = `High AA%`,
    slg = `SLGcon`,
    hard_hit_pct = `HH%`
  )

# Calculate percentile thresholds from supporting data
percentiles <- supporting_data %>%
  summarise(
    avg_la_70 = quantile(avg_la, 0.70, na.rm = TRUE),
    avg_la_80 = quantile(avg_la, 0.80, na.rm = TRUE),
    hh_la_70 = quantile(hh_la, 0.70, na.rm = TRUE),
    hh_la_80 = quantile(hh_la, 0.80, na.rm = TRUE),
    high_aa_70 = quantile(high_aa_pct, 0.70, na.rm = TRUE),
    sweet_spot_40 = quantile(sweet_spot_pct, 0.40, na.rm = TRUE),
    sweet_spot_70 = quantile(sweet_spot_pct, 0.70, na.rm = TRUE),
    slg_40 = quantile(slg, 0.40, na.rm = TRUE),
    slg_60 = quantile(slg, 0.60, na.rm = TRUE),
    slg_80 = quantile(slg, 0.80, na.rm = TRUE),
    hard_hit_70 = quantile(hard_hit_pct, 0.70, na.rm = TRUE),
    hard_hit_50 = quantile(hard_hit_pct, 0.50, na.rm = TRUE)
  ) %>%
  as.list()  # Convert to list for scalar access

cat("Percentile thresholds calculated:\n")
cat("  Avg LA (70th):", percentiles$avg_la_70, "\n")
cat("  HH LA (70th):", percentiles$hh_la_70, "\n")
cat("  High AA% (70th):", percentiles$high_aa_70, "\n")
cat("  Sweet Spot% (40th):", percentiles$sweet_spot_40, "\n")
cat("  SLG (80th):", percentiles$slg_80, "\n")
cat("  Hard Hit% (70th):", percentiles$hard_hit_70, "\n")
cat("  Hard Hit% (50th):", percentiles$hard_hit_50, "\n")

# =============================================================================
# 3. CLASSIFY HITTERS INTO PROFILE ARCHETYPES
# =============================================================================

# Calculate full-season metrics for each hitter to enable profile classification
hitter_full_season <- hitter_periods %>%
  filter(period_num == 1) %>%
  # group_by(batter, last_first_name, season_year) %>%
  # summarise(
  #   n_periods = n(),
  #   Avg_LA_season = round(weighted.mean(Avg_LA, BBE, na.rm = TRUE), 1),
  #   HH_LA_season = round(weighted.mean(HH_LA, BBE, na.rm = TRUE), 1),
  #   Sweet_Spot_Pct_season = round(weighted.mean(Sweet_Spot_Pct, BBE, na.rm = TRUE), 1),
  #   Hard_Hit_Pct_season = round(weighted.mean(Hard_Hit_Pct, BBE, na.rm = TRUE), 1),
  #   SLG_season = round(weighted.mean(SLG, BBE, na.rm = TRUE), 2),
  #   High_AA_Pct_season = round(weighted.mean(High_AA_Pct, BBE, na.rm = TRUE), 1),
  #   High_LA_Pct_season = round(weighted.mean(High_LA_Pct, BBE, na.rm = TRUE), 1),
  #   total_BBE = sum(BBE),
  #   .groups = "drop"
  # ) %>%
  mutate(
    profile_type = case_when(
      # Caissie-type: High Avg LA, HH LA, Ideal AA%, but low SLG (below 60th)
      Avg_LA >= percentiles$avg_la_70 & 
        HH_LA >= percentiles$hh_la_70 & 
        Sweet_Spot_Pct >= percentiles$sweet_spot_70 & 
        # High_AA_Pct >= percentiles$high_aa_70 & 
        SLG < percentiles$slg_40 ~ "Caissie",
      
      # Raleigh-type: High Avg LA, HH LA, but low Sweet Spot% (below 40th)
      Avg_LA >= percentiles$avg_la_70 & 
        HH_LA >= percentiles$hh_la_70 & 
        Sweet_Spot_Pct <= percentiles$sweet_spot_40 & 
        SLG < percentiles$slg_40 ~ "Raleigh",
      
      # Moniak-type: High Avg LA, HH LA, excellent SLG (above 80th)
      Avg_LA >= percentiles$avg_la_70 & 
        HH_LA >= percentiles$hh_la_70 & 
        Sweet_Spot_Pct <= percentiles$sweet_spot_40 & 
        # Hard_Hit_Pct < percentiles$hard_hit_50 &
        SLG >= percentiles$slg_80 ~ "Moniak",
      
      # Watson-type: Good across most metrics except Sweet Spot%
      Avg_LA >= percentiles$avg_la_70 & 
        HH_LA >= percentiles$hh_la_70 & 
        Hard_Hit_Pct >= percentiles$hard_hit_70 & 
        Sweet_Spot_Pct <= percentiles$sweet_spot_40 &
        SLG >= percentiles$slg_60 ~ "Watson",
      
      TRUE ~ "Other"
    )
  )

cat("\nProfile Classification Summary:\n")
print(hitter_full_season %>% group_by(profile_type) %>% summarise(count = n(), .groups = "drop"))

# Merge profile classifications back to period data
hitter_periods_profiled <- hitter_periods %>%
  left_join(
    hitter_full_season %>% select(batter, season_year, profile_type),
    by = c("batter", "season_year")
  ) %>%
  filter(profile_type != "Other", season_year != 2026)  # Focus on profiled archetypes

sample_limit <- hitter_periods_profiled %>%
  group_by(batter, last_first_name, season_year) %>%
  summarise(n_periods = n(), .groups = "drop") %>%
  filter(n_periods >= 5)

hitter_periods_profiled <- inner_join(hitter_periods_profiled, sample_limit, by = c("batter", "season_year"))

cat("Total period observations for profiled archetypes:", nrow(hitter_periods_profiled), "\n")

# =============================================================================
# 4. VISUALIZE EVOLUTION TRAJECTORIES BY PROFILE TYPE
# =============================================================================

# Plot 1: SLG improvement/decline by profile type (average delta across all years)
trajectory_plot <- hitter_periods_profiled %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(Delta_SLG = Cumul_SLG - lag(Cumul_SLG)) %>%
  ungroup() %>%
  group_by(profile_type, period_num) %>%
  summarise(Avg_Delta_SLG = mean(Delta_SLG, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = period_num, y = Avg_Delta_SLG, color = profile_type, group = profile_type)) +
  geom_line(size = 1) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  facet_wrap(~profile_type, nrow = 2) +
  labs(
    title = "SLG Improvement/Decline by Hitter Profile Type (Average Period-to-Period Change)",
    x = "Bi-Weekly Period",
    y = "Average Change in Exit Velocity",
    color = "Profile Type"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  scale_x_continuous(breaks = 1:10)

cat("\nSaving trajectory plot...\n")
ggsave("outputs/01_slg_trajectory_by_profile.png", trajectory_plot, width = 12, height = 8, dpi = 300)

# Plot 2: Sweet Spot% improvement/decline by profile type (average delta across all years)
sweet_spot_plot <- hitter_periods_profiled %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(Delta_Sweet_Spot_Pct = Cumul_Sweet_Spot_Pct - lag(Cumul_Sweet_Spot_Pct)) %>%
  ungroup() %>%
  group_by(profile_type, period_num) %>%
  summarise(Avg_Delta_Sweet_Spot_Pct = mean(Delta_Sweet_Spot_Pct, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = period_num, y = Avg_Delta_Sweet_Spot_Pct, color = profile_type, group = profile_type)) +
  geom_line(size = 1) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  facet_wrap(~profile_type, nrow = 2) +
  labs(
    title = "Sweet Spot% Improvement/Decline by Hitter Profile Type (Average Period-to-Period Change)",
    x = "Bi-Weekly Period",
    y = "Average Change in Sweet Spot %",
    color = "Profile Type"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  scale_x_continuous(breaks = 1:10)

ggsave("outputs/02_sweet_spot_trajectory_by_profile.png", sweet_spot_plot, width = 12, height = 8, dpi = 300)

# Plot 3: Hard Hit % improvement/decline by profile type (average delta across all years)
hard_hit_plot <- hitter_periods_profiled %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(Delta_Hard_Hit_Pct = Cumul_Hard_Hit_Pct - lag(Cumul_Hard_Hit_Pct)) %>%
  ungroup() %>%
  group_by(profile_type, period_num) %>%
  summarise(Avg_Delta_Hard_Hit_Pct = mean(Delta_Hard_Hit_Pct, na.rm = TRUE), .groups = "drop") %>%
  ggplot(aes(x = period_num, y = Avg_Delta_Hard_Hit_Pct, color = profile_type, group = profile_type)) +
  geom_line(size = 1) +
  geom_point(size = 2.5) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  facet_wrap(~profile_type, nrow = 2) +
  labs(
    title = "Hard Hit % Improvement/Decline by Hitter Profile Type (Average Period-to-Period Change)",
    x = "Bi-Weekly Period",
    y = "Average Change in Hard Hit %",
    color = "Profile Type"
  ) +
  theme_minimal() +
  theme(
    plot.title = element_text(face = "bold", size = 12),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom"
  ) +
  scale_x_continuous(breaks = 1:10)

ggsave("outputs/03_hard_hit_trajectory_by_profile.png", hard_hit_plot, width = 12, height = 8, dpi = 300)

# =============================================================================
# 5a. ANALYZE SWANSON/RALEIGH VS MONIAK BATTED BALL DISTRIBUTIONS
# Moniak - 666160
# Swanson - 621020
# Raleigh - 663728
# =============================================================================

slg_outcomes <- all_statcast %>%
  filter(batter %in% c(666160,621020,663728), description == "hit_into_play", game_year == 2026, period_num == 1,
  bb_type %in% c("fly_ball", "line_drive")) %>%
  group_by(batter) %>%
  summarise(
    total_bbe = n(),
    xSLG = round(mean(estimated_slg_using_speedangle, na.rm = TRUE), 3),
    SLG = round(((1*sum(events == "single" & description == "hit_into_play",na.rm = T))+(2*sum(events == "double" & description == "hit_into_play",na.rm = T))+
                                      (3*sum(events == "triple" & description == "hit_into_play",na.rm = T))+
                                      (4*sum(events == "home_run" & description == "hit_into_play",na.rm = T)))/n(),3)
  )

hh_proportions <- all_statcast %>%
  filter(batter %in% c(666160,621020,663728), description == "hit_into_play", game_year == 2026, launch_speed >= 95, period_num == 1) %>%
  group_by(batter) %>%
  summarise(
    total_bbe = n(),
    gb = sum(bb_type == "ground_ball", na.rm = TRUE)/n(),
    ld = sum(bb_type == "line_drive", na.rm = TRUE)/n(),
    la_ld = round(mean(launch_angle[bb_type == "line_drive"], na.rm = TRUE), 1),
    fb = sum(bb_type == "fly_ball", na.rm = TRUE)/n(),
    la_fb = round(mean(launch_angle[bb_type == "fly_ball"], na.rm = TRUE), 1),

  )

# proportion of flyballs hit above 32 degrees vs all air balls below 32
# xSLGcon vs SLGcon on all air balls

# =============================================================================
# 5b. ANALYZE CAISSIE-TYPE DISTRIBUTION MISMATCH
# =============================================================================

cat("\n=== CAISSIE-TYPE DISTRIBUTION ANALYSIS ===\n")

caissie_hitters <- hitter_full_season %>%
  filter(profile_type == "Caissie") %>%
  pull(batter)

cat("Caissie-type hitters:", paste(caissie_hitters, collapse = ", "), "\n")

# For Caissie-types, analyze launch angle distribution on hard hits
caissie_analysis <- all_statcast %>%
  filter(batter %in% caissie_hitters & is_bbe) %>%
  mutate(
    hard_hit_category = case_when(
      is_hard_hit & is_sweet_spot ~ "Productive (HH + SS)",
      is_hard_hit & !is_sweet_spot ~ "Unproductive (HH, no SS)",
      !is_hard_hit & is_sweet_spot ~ "Contact (SS, not HH)",
      TRUE ~ "Other"
    )
  ) %>%
  group_by(batter, hard_hit_category) %>%
  summarise(
    count = n(),
    avg_ev = round(mean(launch_speed, na.rm = TRUE), 1),
    avg_la = round(mean(launch_angle, na.rm = TRUE), 1),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = hard_hit_category,
    values_from = c(count, avg_ev, avg_la),
    values_fill = 0
  )

cat("\nCaissie-type ball distribution:\n")
print(caissie_analysis)

# Calculate productivity metric: % of hard hits in productive zone
caissie_productivity <- all_statcast %>%
  filter(batter %in% caissie_hitters & is_bbe) %>%
  group_by(batter) %>%
  summarise(
    total_bbe = n(),
    productive_hh = sum(is_hard_hit & is_sweet_spot, na.rm = TRUE),
    unproductive_hh = sum(is_hard_hit & !is_sweet_spot, na.rm = TRUE),
    productive_hh_pct = round(100 * sum(is_hard_hit & is_sweet_spot) / sum(is_hard_hit), 1),
    total_hh = sum(is_hard_hit, na.rm = TRUE),
    .groups = "drop"
  )

cat("\nCaissie-type productivity (HH distribution):\n")
print(caissie_productivity)

# =============================================================================
# 5c. SWANSON 2026 COMPARISON
# =============================================================================

swanson_df <- read.csv("/Users/andrewsumner/Downloads/savant_data (20).csv")

swanson_df <- swanson_df %>%
  filter(game_type == "R") %>%
  mutate(
    season_year = year(game_date),
    month_day = paste0(sprintf("%02d", month(game_date)), "-", sprintf("%02d", day(game_date))),
    period_num = case_when(
      # month_day < "06-21" ~ 1,
      month_day < "06-15" ~ 1,
      month_day < "06-28" ~ 2,
      month_day < "07-12" ~ 3,
      month_day < "07-26" ~ 4,
      month_day < "08-09" ~ 5,
      month_day < "08-23" ~ 6,
      month_day < "09-06" ~ 7,
      month_day < "09-20" ~ 8,
      month_day < "10-04" ~ 9,
      TRUE ~ 10
    ),
    is_bbe = description == "hit_into_play",
    is_sweet_spot = launch_angle >= 8 & launch_angle <= 32 & description == "hit_into_play",
    is_hard_hit = launch_speed >= 95 & description == "hit_into_play",
    is_hard_hit_sweet_spot = is_hard_hit & is_sweet_spot,
    high_launch_angle = launch_angle > 32
  )

add_metrics <- swanson_df %>%
  filter(!str_detect(des, paste(words_to_remove, collapse = "|"))) %>%
  # filter(period_num < 10) %>%
  group_by(batter, player_name, season_year, period_num) %>%
  summarise(
    BBE = sum(is_bbe, na.rm = TRUE),
    Sum_AirBalls = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive"), na.rm = TRUE),
    Sum_GB = sum(is_bbe & bb_type %in% c("ground_ball"), na.rm = TRUE),
    Sum_Air32 = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive") & launch_angle > 32, na.rm = TRUE),
    Sum_Airless32 = sum(is_bbe & bb_type %in% c("fly_ball", "line_drive") & launch_angle <= 32, na.rm = TRUE),
    Has_AA = sum(!is.na(attack_angle) & is_bbe, na.rm = TRUE),
    Sum_LA = sum(launch_angle[is_bbe], na.rm = TRUE),
    Sum_HH_LA = sum(launch_angle[is_bbe & is_hard_hit], na.rm = TRUE),
    Sum_SLG = ((1*sum(events == "single" & is_bbe == 1,na.rm = T))+(2*sum(events == "double" & is_bbe == 1,na.rm = T))+
                                      (3*sum(events == "triple" & is_bbe == 1,na.rm = T))+
                                      (4*sum(events == "home_run" & is_bbe == 1,na.rm = T))),
    Sum_xSLG = sum(estimated_slg_using_speedangle[is_bbe], na.rm = TRUE),
    Sum_AirSLG = ((1*sum(events == "single" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+(2*sum(events == "double" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+
                                      (3*sum(events == "triple" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))+
                                      (4*sum(events == "home_run" & is_bbe == 1 & bb_type %in% c("fly_ball", "line_drive"),na.rm = T))),
    Sum_AirxSLG = sum(estimated_slg_using_speedangle[is_bbe & bb_type %in% c("fly_ball", "line_drive")], na.rm = TRUE),
    Count_HH = sum(is_hard_hit, na.rm = TRUE),
    Count_Sweet_Spot = sum(is_sweet_spot, na.rm = TRUE),
    Sum_Launch_Speed = sum(launch_speed[is_bbe], na.rm = TRUE),
    Count_High_AA = sum(attack_angle >= 14 & is_bbe == 1 & !is.na(attack_angle), na.rm = TRUE),
    Count_High_LA = sum(high_launch_angle, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  # filter(BBE >= 10) %>%
  arrange(batter, season_year, period_num) %>%
  group_by(batter, season_year) %>%
  mutate(
    # Cumulative raw sums
    Cumul_BBE = cumsum(BBE),
    Cumul_GB = cumsum(Sum_GB),
    Cumul_AirBalls = cumsum(Sum_AirBalls),
    Cumul_Air32 = cumsum(Sum_Air32),
    Cumul_Airless32 = cumsum(Sum_Airless32),
    cumul_Has_AA = cumsum(Has_AA),
    Cumul_Sum_LA = cumsum(Sum_LA),
    Cumul_Sum_HH_LA = cumsum(Sum_HH_LA),
    Cumul_Sum_AirSLG = cumsum(Sum_AirSLG),
    Cumul_Sum_AirxSLG = cumsum(Sum_AirxSLG),
    Cumul_Sum_SLG = cumsum(Sum_SLG),
    Cumul_Sum_xSLG = cumsum(Sum_xSLG),
    Cumul_Count_HH = cumsum(Count_HH),
    Cumul_Count_Sweet_Spot = cumsum(Count_Sweet_Spot),
    Cumul_Sum_Launch_Speed = cumsum(Sum_Launch_Speed),
    Cumul_Count_High_AA = cumsum(Count_High_AA),
    Cumul_Count_High_LA = cumsum(Count_High_LA),
    # Period-level metrics
    Avg_LA = round(Sum_LA / BBE, 1),
    HH_LA = round(Sum_HH_LA / Count_HH, 1),
    Sweet_Spot_Pct = round(100 * Count_Sweet_Spot / BBE, 1),
    Hard_Hit_Pct = round(100 * Count_HH / BBE, 1),
    SLG = round(Sum_SLG / BBE, 3),
    xSLG = round(Sum_xSLG / BBE, 3),
    SLG_Air = round(Sum_AirSLG / Sum_AirBalls, 3),
    xSLG_Air = round(Sum_AirxSLG / Sum_AirBalls, 3),
    Air32_Pct = round(100 * Sum_Air32 / BBE, 1),
    Under32_Pct = round(100 * Sum_Airless32 / BBE, 1),
    gb_pct = round(100 * Sum_GB / BBE, 1),
    High_AA_Pct = round(100 * (Count_High_AA / Has_AA), 1),
    High_LA_Pct = round(100 * Count_High_LA / BBE, 1),
    # Cumulative metrics derived from cumulative sums
    Cumul_Avg_LA = round(Cumul_Sum_LA / Cumul_BBE, 1),
    Cumul_HH_LA = round(Cumul_Sum_HH_LA / Cumul_Count_HH, 1),
    Cumul_Sweet_Spot_Pct = round(100 * Cumul_Count_Sweet_Spot / Cumul_BBE, 1),
    Cumul_Hard_Hit_Pct = round(100 * Cumul_Count_HH / Cumul_BBE, 1),
    Cumul_SLG = round(Cumul_Sum_SLG / Cumul_BBE, 3),
    Cumul_xSLG = round(Cumul_Sum_xSLG / Cumul_BBE, 3),
    Cumul_High_AA_Pct = round(100 * (Cumul_Count_High_AA / cumul_Has_AA), 1),
    Cumul_Air32_Pct = round(100 * Cumul_Air32 / Cumul_BBE, 1),
    Cumul_Under32_Pct = round(100 * Cumul_Airless32 / Cumul_BBE, 1),
    Cumul_GB_Pct = round(100 * Cumul_GB / Cumul_BBE, 1),
    Cumul_AirSLG = round(Cumul_Sum_AirSLG / Cumul_AirBalls, 3),
    Cumul_AirxSLG = round(Cumul_Sum_AirxSLG / Cumul_AirBalls, 3),
    .groups = "drop"
  ) %>%
  select(batter, player_name, season_year, period_num, BBE, Count_Sweet_Spot, Avg_LA, HH_LA, Sweet_Spot_Pct, Hard_Hit_Pct, SLG, xSLG, 
         Cumul_Avg_LA, Cumul_HH_LA, Cumul_Sweet_Spot_Pct, Cumul_Hard_Hit_Pct, Cumul_SLG, Cumul_xSLG, Cumul_High_AA_Pct, Cumul_AirSLG, Cumul_AirxSLG, Air32_Pct, Under32_Pct, Cumul_Air32_Pct, Cumul_Under32_Pct, gb_pct, Cumul_GB_Pct)
  # filter(BBE >= 10) 

## 2 batted balls that statcast didn't flag as sweet spot but are at 8 degrees. They do have one batted ball at 8 degrees and is labeled sweet spot
# =============================================================================
# 6. BUILD PROFILE-MATCHED COMPARISON TABLES
# =============================================================================

cat("\n=== PRODUCTIVE VS UNPRODUCTIVE SIMILAR PROFILES ===\n")

# Identify potential profile pairs (e.g., Moniak vs Raleigh/Watson with similar LA metrics)
profile_comparison <- hitter_full_season %>%
  filter(profile_type %in% c("Moniak", "Raleigh", "Watson")) %>%
  select(batter, profile_type, Avg_LA_season, HH_LA_season, Sweet_Spot_Pct_season, SLG_season, Hard_Hit_Pct_season)

# Create comparison tibble with early, mid, and late season snapshots
comparison_snapshots <- hitter_periods_profiled %>%
  filter(profile_type %in% c("Moniak", "Raleigh", "Watson")) %>%
  mutate(
    phase = case_when(
      period_num <= 3 ~ "Early",
      period_num <= 7 ~ "Mid",
      TRUE ~ "Late"
    )
  ) %>%
  group_by(batter, season_year, profile_type, phase) %>%
  summarise(
    Avg_LA = round(mean(Avg_LA, na.rm = TRUE), 1),
    HH_LA = round(mean(HH_LA, na.rm = TRUE), 1),
    Sweet_Spot_Pct = round(mean(Sweet_Spot_Pct, na.rm = TRUE), 1),
    Hard_Hit_Pct = round(mean(Hard_Hit_Pct, na.rm = TRUE), 1),
    SLG = round(mean(SLG, na.rm = TRUE), 2),
    BBE_total = sum(BBE),
    .groups = "drop"
  ) %>%
  pivot_wider(
    names_from = phase,
    values_from = c(Avg_LA, HH_LA, Sweet_Spot_Pct, Hard_Hit_Pct, SLG, BBE_total),
    values_fill = NA
  )

cat("\nComparison snapshot (Early/Mid/Late phase metrics):\n")
print(comparison_snapshots)

# Write to CSV for manual exploration
write_csv(comparison_snapshots, "outputs/profile_comparison_snapshots.csv")

# =============================================================================
# 7. SUMMARIZE NORMALIZATION AND REGRESSION PATTERNS
# =============================================================================

cat("\n=== NORMALIZATION/REGRESSION PATTERN SUMMARY ===\n")

# For each profile type, calculate trajectory changes
trajectory_summary <- hitter_periods_profiled %>%
  group_by(batter, season_year, profile_type) %>%
  arrange(period_num) %>%
  summarise(
    first_slg = first(SLG, na_rm = TRUE),
    last_slg = last(SLG, na_rm = TRUE),
    slg_change = round(last_slg - first_slg, 2),
    slg_change_pct = round(((last_slg - first_slg) / first_slg) * 100, 1),
    
    first_sweet_spot = first(Sweet_Spot_Pct, na_rm = TRUE),
    last_sweet_spot = last(Sweet_Spot_Pct, na_rm = TRUE),
    sweet_spot_change = round(last_sweet_spot - first_sweet_spot, 1),
    
    first_hard_hit = first(Hard_Hit_Pct, na_rm = TRUE),
    last_hard_hit = last(Hard_Hit_Pct, na_rm = TRUE),
    hard_hit_change = round(last_hard_hit - first_hard_hit, 1),
    
    n_periods = n(),
    .groups = "drop"
  )

# Summarize by profile type
normalization_summary <- trajectory_summary %>%
  group_by(profile_type, season_year) %>%
  summarise(
    n_hitters = n(),
    
    # SLG change statistics
    avg_slg_change = round(mean(slg_change, na.rm = TRUE), 2),
    median_slg_change = round(median(slg_change, na.rm = TRUE), 2),
    pct_improved_slg = round(100 * sum(slg_change > 0) / n(), 1),
    pct_regressed_slg = round(100 * sum(slg_change < 0) / n(), 1),
    
    # Sweet Spot improvement statistics
    avg_sweet_spot_change = round(mean(sweet_spot_change, na.rm = TRUE), 1),
    median_sweet_spot_change = round(median(sweet_spot_change, na.rm = TRUE), 1),
    pct_improved_sweet_spot = round(100 * sum(sweet_spot_change > 0) / n(), 1),
    
    # Hard Hit consistency
    avg_hard_hit_change = round(mean(hard_hit_change, na.rm = TRUE), 1),
    hard_hit_volatility = round(sd(hard_hit_change, na.rm = TRUE), 1),
    
    .groups = "drop"
  )

cat("\nNormalization/Regression Summary:\n")
print(normalization_summary)

# Write detailed trajectory summary
write_csv(trajectory_summary, "outputs/individual_trajectory_summary.csv")
write_csv(normalization_summary, "outputs/normalization_regression_summary.csv")

# =============================================================================
# 8. PROFILE DIVERGENCE ANALYSIS (Moniak vs Raleigh/Watson)
# =============================================================================

cat("\n=== MONIAK VS RALEIGH/WATSON DIVERGENCE ANALYSIS ===\n")

# Compare hard-hit consistency and spray patterns between profiles
hard_hit_consistency <- hitter_periods_profiled %>%
  filter(profile_type %in% c("Moniak", "Raleigh", "Watson")) %>%
  group_by(batter, season_year, profile_type) %>%
  summarise(
    mean_hard_hit_pct = round(mean(Hard_Hit_Pct, na.rm = TRUE), 1),
    sd_hard_hit_pct = round(sd(Hard_Hit_Pct, na.rm = TRUE), 1),
    mean_slg = round(mean(SLG, na.rm = TRUE), 2),
    mean_sweet_spot_pct = round(mean(Sweet_Spot_Pct, na.rm = TRUE), 1),
    consistency_score = round(100 * (1 - (sd_hard_hit_pct / mean_hard_hit_pct)), 1),
    .groups = "drop"
  )

cat("\nHard-Hit Consistency by Profile:\n")
print(hard_hit_consistency)

write_csv(hard_hit_consistency, "outputs/hard_hit_consistency.csv")

# =============================================================================
# 9. FINAL SUMMARY STATISTICS
# =============================================================================

cat("\n=== FINAL SUMMARY STATISTICS ===\n")

final_summary <- tibble(
  Metric = c(
    "Total MLB hitters eligible (100+ BBE)",
    "Hitters with identified profiles",
    "Bi-weekly periods analyzed",
    "Total period observations",
    "",
    "Caissie-type hitters",
    "Raleigh-type hitters",
    "Watson-type hitters",
    "Moniak-type hitters"
  ),
  Count = c(
    nrow(hitter_totals),
    nrow(hitter_full_season %>% filter(profile_type != "Other")),
    10,
    nrow(hitter_periods_profiled),
    NA,
    nrow(hitter_full_season %>% filter(profile_type == "Caissie")),
    nrow(hitter_full_season %>% filter(profile_type == "Raleigh")),
    nrow(hitter_full_season %>% filter(profile_type == "Watson")),
    nrow(hitter_full_season %>% filter(profile_type == "Moniak"))
  )
)

print(final_summary)

cat("\n=== ANALYSIS COMPLETE ===\n")
cat("Outputs saved to: outputs/\n")
cat("  - 01_slg_trajectory_by_profile.png\n")
cat("  - 02_sweet_spot_trajectory_by_profile.png\n")
cat("  - 03_hard_hit_trajectory_by_profile.png\n")
cat("  - profile_comparison_snapshots.csv\n")
cat("  - individual_trajectory_summary.csv\n")
cat("  - normalization_regression_summary.csv\n")
cat("  - hard_hit_consistency.csv\n")
