# From https://mesonet.agron.iastate.edu/request/download.phtml?network=NY_ASOS

library(httr)
library(dplyr)
library(lubridate)
library(readr)

# Download

get_asos <- function(station) {
  url <- "http://mesonet.agron.iastate.edu/cgi-bin/request/asos.py?"
  query <- list(
    station = station, data = "all",
    year1 = "2013", month1 = "1", day1 = "1",
    year2 = "2013", month2 = "12", day2 = "31", tz = "GMT",
    format = "comma", latlon = "no", direct = "yes")

  dir.create("data-raw/weather", showWarnings = FALSE, recursive = TRUE)
  r <- GET(url, query = query, write_disk(paste0("./data-raw/weather/", station, ".csv")))
  stop_for_status(r)
}

stations <- c("JFK", "LGA", "EWR")
paths <- paste0(stations, ".csv")
missing <- stations[!(paths %in% dir("data-raw/weather/"))]
lapply(missing, get_asos)

# Load

# Original Variable Descriptions
#   https://mesonet.agron.iastate.edu/request/download.phtml?network=NY_ASOS

# station: Three or four character site identifier
# valid:   Timestamp of the observation
# tmpf:    Air Temperature in Fahrenheit, typically @ 2 meters
# dwpf:    Dew Point Temperature in Fahrenheit, typically @ 2 meters
# relh:    Relative Humidity in %
# drct:    Wind Direction in degrees from north
# sknt:    Wind Speed in knots
# p01i:    One hour precipitation for the period from the observation time
#          to the time of the previous hourly precipitation reset.
#          This varies slightly by site. Values are in inches.
#          This value may or may not contain frozen precipitation melted
#          by some device on the sensor or estimated by some other means.
#          Unfortunately, we do not know of an authoritative database
#          denoting which station has which sensor.
# alti:    Pressure altimeter in inches
# mslp:    Sea Level Pressure in millibar
# vsby:    Visibility in miles
# gust:    Wind Gust in knots
# skyc1:   Sky Level 1 Coverage
# skyc2:   Sky Level 2 Coverage
# skyc3:   Sky Level 3 Coverage
# skyc4:   Sky Level 4 Coverage
# skyl1:   Sky Level 1 Altitude in feet
# skyl2:   Sky Level 2 Altitude in feet
# skyl3:   Sky Level 3 Altitude in feet
# skyl4:   Sky Level 4 Altitude in feet
# presentwx: Present Weather Codes (space seperated)
# metar:   unprocessed reported observation in METAR format
# https://cran.r-project.org/web/packages/readr/vignettes/column-types.html

problematic_cols = cols(
  X12 = col_character(),
  X18 = col_character(),
  X19 = col_character(),
  X20 = col_character()
)
paths <- dir("data-raw/weather", full.names = TRUE)
all <- lapply(paths, read_csv, skip = 6, na = "M", col_names = FALSE,
              col_types = problematic_cols)

raw <- bind_rows(all)
var_names <- c("station", "time", "tmpf", "dwpf", "relh", "drct", "sknt",
  "p01i", "alti", "mslp", "vsby", "gust", "skyc1", "skyc2", "skyc3", "skyc4",
  "skyl1", "skyl2", "skyl3", "skyl4", "presentwx", "metar")
# length(var_names)
names(raw) <- var_names

weather <- raw %>%
  select(
    station, time, temp = tmpf, dewp = dwpf, humid = relh,
    wind_dir = drct, wind_speed = sknt, wind_gust = gust,
    precip = p01i, pressure = mslp, visib = vsby
  ) %>%
  mutate(
    time = as.POSIXct(strptime(time, "%Y-%m-%d %H:%M")),
    wind_speed = as.numeric(wind_speed) * 1.15078, # convert to mpg
    wind_gust = as.numeric(wind_speed) * 1.15078
  ) %>%
  mutate(year = 2013, month = month(time), day = mday(time), hour = hour(time)) %>%
  group_by(station, month, day, hour) %>%
  filter(row_number() == 1) %>%
  select(origin = station, year:hour, temp:visib) %>%
  ungroup() %>%
  filter(!is.na(month)) %>%
  mutate(
    time_hour = ISOdatetime(year, month, day, hour, 0, 0)
  )

write.csv(weather, gzfile("data-raw/weather.csv.gz"), row.names = FALSE, quote = FALSE, na = "")
save(weather, file = "data/weather.rda", compress = "bzip2")
