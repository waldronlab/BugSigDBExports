library(dplyr)
library(countries)
library(lubridate)
library(stringr)


not_na_or_blank <- function(x) {
    !is.na(x) | x != ""
}

na_or_pos_int <- function(x) {
    is.na(x) | (is.integer(x) & x > 0)
}

between_strict <- function(x, lower = 0, upper = 1) {
    as.numeric(x) > lower & as.numeric(x) < upper
}

between_inclusive <- function(x, lower = 0, upper = 1) {
    as.numeric(x) >= lower & as.numeric(x) <= upper
}

full_dump <- read.csv("full_dump.csv", skip = 1)

valid_year <- function(x) {
    stringr::str_detect(x, "^[0-9]{4,4}$") & 
        as.numeric(x) >= 1999 & as.numeric(x) <= lubridate::year(Sys.Date())
}

doi_url <- function(x) {
    stringr::str_detect(x, "^(http)?.*(doi.org){1}")
}

valid_pmid <- function(x) {
    stringr::str_detect(x, "^[0-9]{8,8}$")
}

qcfd <- full_dump |>
    dplyr::filter(stringr::str_detect(BSDB.ID, "bsdb:.*/[0-9]+/[0-9]+"),
                  not_na_or_blank(Study),
                  not_na_or_blank(Study.design),
                  valid_pmid(PMID) | is.na(PMID),
                  !doi_url(DOI) | is.na(DOI),
                  valid_year(Year) | is.na(Year),
                  stringr::str_detect(Experiment, "Experiment [0-9]+"),
                  countries::is_country(Location.of.subjects),
                  !is.na(Condition),
                  not_na_or_blank(EFO.ID),
                  not_na_or_blank(Group.0.name),
                  not_na_or_blank(Group.1.name),
                  not_na_or_blank(Group.1.definition),
                  na_or_pos_int(Group.0.sample.size),
                  na_or_pos_int(Group.1.sample.size),
                  is.na(Significance.threshold) | 
                      between_strict(Significance.threshold, 0, 1),
                  is.na(LDA.Score.above) | between_inclusive(LDA.Score.above, 0, 20),
                  stringr::str_detect(Signature.page.name, "Signature [0-9]+"),
                  not_na_or_blank(Source),
                  # Check if valid date but not format
                  !is.na(as.Date(Curated.date, format = "%d %B %Y")),
                  `Abundance.in.Group.1` %in% c("increased", "decreased"),
                  State == "Complete",
                  !is.na(Reviewer))
