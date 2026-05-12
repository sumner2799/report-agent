library(readr)
library(dplyr)
library(lubridate)

raw_files <- list.files("data/raw", pattern = "^statcast_.*\\.csv$", full.names = TRUE)

all_data <- tibble()
for (file in raw_files) {
  df <- read_csv(file, show_col_types = FALSE)
  df <- df %>%
    mutate(season = year(as.Date(game_date))) %>%
    rename(exit_velocity = launch_speed) %>%
    select(season, game_date, batter, player_name, stand, launch_angle, exit_velocity, 
           attack_angle, events, bb_type, hc_x, hc_y)
  all_data <- bind_rows(all_data, df)
}

cat('Loaded:', nrow(all_data), '\n')

# Filter to BBE
is_bbe <- function(events) {
  !is.na(events) & 
    events %in% c(
      "single", "double", "triple", "home_run",
      "field_out", "force_out", "field_error", "grounded_into_double_play",
      "double_play", "sac_bunt", "sac_fly", "fielders_choice_out",
      "fielders_choice", "triple_play", "sacrifice_bunt_double_play"
    )
}

bbe_data <- all_data %>%
  filter(is_bbe(events))

cat('BBE:', nrow(bbe_data), '\n')
cat('Unique players in BBE:', n_distinct(bbe_data$player_name), '\n')
cat('Sample player names:\n')
print(head(unique(bbe_data$player_name), 10))

# Test aggregation
test_agg <- bbe_data %>%
  filter(!is.na(player_name)) %>%
  group_by(season, player_name, batter) %>%
  summarise(count = n(), .groups = 'drop') %>%
  filter(count >= 30) %>%
  arrange(desc(count))

cat('\nPlayer-seasons with 30+ BBE:', nrow(test_agg), '\n')
if (nrow(test_agg) > 0) {
  print(head(test_agg, 15))
}
