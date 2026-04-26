conn <- dbConnect(
  MySQL(),
  host = "127.0.0.1",
  user = "root",
  password = "Fletcher!23",
  dbname = "DBPuzz"
)

sc_2026 <- dbGetQuery(conn,glue::glue(
  "select
*   
from
sc_mlb
where
game_year = 2026
and game_date >= '2026-04-18'
  ",
  .con = conn
  )
)

mnl_sc_26 <- dbGetQuery(conn,glue::glue(
  "select
*   
from
sc_milb
where
game_date >= '2026-04-18'
and game_pk NOT IN (816219,815091,815462,814946,815160,814792)
  ",
  .con = conn
  )
)

write.csv(sc_2026,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/statcast_2026-04-18_2026-04-25.csv")
write.csv(mnl_sc_26,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/mnl_2026-04-18_2026-04-25.csv")

# df_try <- read.csv("/Users/andrewsumner/Documents/Github/report-agent/data/raw/mnl_2026-04-12_2026-04-17.csv")

try <- mnl_sc_26 %>%
    filter(game_date == "2026-04-26")
# 815395 815309

