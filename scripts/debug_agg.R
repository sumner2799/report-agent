library(readr)
library(dplyr)
library(lubridate)

# Simple aggregation check
df <- read_csv('data/raw/statcast_2026-03-25_2026-04-11.csv', show_col_types = FALSE)
df <- df %>%
  mutate(season = year(as.Date(game_date)))

cat('Seasons in data:', unique(df$season), '\n')
cat('Sample player_name values:\n')
print(head(unique(df$player_name), 10))

# Filter to BBE manually
df_bbe <- df %>%
  filter(!is.na(events) & 
    events %in% c('single', 'double', 'triple', 'home_run',
      'field_out', 'force_out', 'field_error', 'grounded_into_double_play',
      'double_play', 'sac_bunt', 'sac_fly', 'fielders_choice_out',
      'fielders_choice', 'triple_play', 'sacrifice_bunt_double_play'))

cat('BBE records:', nrow(df_bbe), '\n')

# Group by player-season
agg_test <- df_bbe %>%
  group_by(season, batter, player_name) %>%
  summarise(total_bbe = n(), .groups='drop') %>%
  filter(total_bbe >= 50) %>%
  arrange(desc(total_bbe))

cat('Player-seasons with 50+ BBE:', nrow(agg_test), '\n')
print(head(agg_test, 15))

cat('\n\nFocal players:\n')
focal <- c("Hamilton, David", "Donovan, Brendan", "Horwitz, Spencer")
for (p in focal) {
  found <- agg_test %>% filter(player_name == p)
  if (nrow(found) > 0) {
    cat(p, ':', found$total_bbe, '\n')
  } else {
    cat(p, ': NOT FOUND\n')
  }
}
