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
and game_date >= '2026-07-26'
  ",
  .con = conn
  )
)
## These game_pk's are good for week 6/3
mnl_sc_26 <- dbGetQuery(conn,glue::glue(
  "select
*   
from
sc_milb
where
game_date >= '2026-07-26'
 ",
  .con = conn
  )
)

# and game_pk NOT IN (815223, 816206, 815746, 814922, 815380, 844667, 814999, 815306)

write.csv(sc_2026,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/statcast_2026-07-26_2026-08-02.csv")
write.csv(mnl_sc_26,"/Users/andrewsumner/Documents/Github/report-agent/data/raw/mnl_2026-07-26_2026-08-02.csv")

# df_try <- read.csv("/Users/andrewsumner/Documents/Github/report-agent/data/raw/statcast_2026-06-15_2026-06-20.csv")

try <- fix_na26 %>%
    filter(game_date == "2026-08-03")
# 815395 815309

