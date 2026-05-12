library(stringr)
library(RMySQL)

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
and game_date >= '2026-05-02'
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
game_date >= '2026-05-02'
and game_pk NOT IN (815388,815007,815312)
  ",
  .con = conn
  )
)

write.csv(sc_2026,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/statcast_2026-05-02_2026-05-09.csv")
write.csv(mnl_sc_26,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/mnl_2026-05-02_2026-05-09.csv")

# df_try <- read.csv("/Users/andrewsumner/Documents/Github/report-agent/data/raw/mnl_2026-04-26_2026-05-01.csv")

try <- mnl_sc_26 %>%
    filter(game_date == "2026-05-10")
# 815395 815309

