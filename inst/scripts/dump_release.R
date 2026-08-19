###########################################################
#
# author: Ludwig Geistlinger
# date: 2021-07-13 19:49:35
#
# descr: dump all files associated with a BugSigDB release
#        into a specified folder
#
# call: Rscript dump_release.R <version> <output.directory> <validate>
#
############################################################

library(bugsigdbr)
library(httr2)
library(lubridate)
library(plyr)
library(dplyr)
library(readr)
library(rvest)
library(stringr)


# Validation
na_and_blank <- function(x)
    is.na(x) & nzchar(trimws(x))

na_or_pos_int <- function(x)
    is.na(x) | (is.numeric(x) %% 1 == 0 & x > 0)

between_exclusive <- function(x, lower = 0, upper = 1)
    as.numeric(x) > lower & as.numeric(x) < upper

between_inclusive <- function(x, lower = 0, upper = 1)
    as.numeric(x) >= lower & as.numeric(x) <= upper

valid_year <- function(x) {
    stringr::str_detect(x, "^[0-9]{4,4}$") &
        as.numeric(x) >= 1999 & as.numeric(x) <= lubridate::year(Sys.Date())
}

doi_url <- function(x)
    stringr::str_detect(x, "^(http)?.*(doi.org){1}")

valid_pmid <- function(x)
    stringr::str_detect(x, "^[0-9]{8,8}$")


## CONSTANTS

DEFAULT_USER_AGENT <- "BugSigDBExports/1.0 (https://github.com/waldronlab/BugSigDBExports)"


## FUNCTIONS

getBugSigDBExportURLs <- function(api_url = "https://bugsigdb.org/w/api.php",
                                  help_url = "https://bugsigdb.org/Help:Export",
                                  user_agent = DEFAULT_USER_AGENT)
{
    # 1. Primary approach: MediaWiki API prop=extlinks with informative User-Agent
    urls <- tryCatch({
        req <- httr2::request(api_url) |>
            httr2::req_url_query(
                action = "query",
                titles = "Help:Export",
                prop = "extlinks",
                format = "json"
            ) |>
            httr2::req_user_agent(user_agent) |>
            httr2::req_retry(max_tries = 3, backoff = ~ 5)

        resp <- httr2::req_perform(req)
        data <- httr2::resp_body_json(resp)
        pages <- data[["query"]][["pages"]]
        extlinks <- unlist(lapply(pages[[1]][["extlinks"]], function(x) x[[1]]))

        list(
            stud = grep("studies\\.csv(?:$|\\?)", extlinks, value = TRUE)[1L],
            exp  = grep("experiments\\.csv(?:$|\\?)", extlinks, value = TRUE)[1L],
            sig  = grep("signatures\\.csv(?:$|\\?)", extlinks, value = TRUE)[1L]
        )
    }, error = function(e) {
        warning(sprintf(
            "MediaWiki API query failed: %s. Falling back to HTML scraping.",
            e$message))
        NULL
    })

    if (!is.null(urls) && !is.na(urls$stud) && !is.na(urls$exp) && !is.na(urls$sig)) {
        return(urls)
    }

    # 2. Fallback: HTML scraping of Help:Export
    req <- tryCatch(
        httr2::request(help_url) |>
            httr2::req_user_agent(user_agent) |>
            httr2::req_retry(max_tries = 3, backoff = ~ 5) |>
            httr2::req_perform(),
        error = function(e) stop(sprintf(
            "Failed to reach export page '%s': %s", help_url, e$message))
    )
    html <- httr2::resp_body_html(req)
    links <- html |> rvest::html_elements("a") |> rvest::html_attr("href")

    extract_url <- function(pattern) {
        target <- grep(pattern, links, value = TRUE)
        if (length(target) == 0L)
            stop(sprintf(
                "Failed to resolve export URL matching pattern '%s' from %s",
                pattern, help_url))
        target[1L]
    }

    list(
        stud = extract_url("studies\\.csv(?:$|\\?)"),
        exp  = extract_url("experiments\\.csv(?:$|\\?)"),
        sig  = extract_url("signatures\\.csv(?:$|\\?)")
    )
}

downloadFiles <- function(links, delay = 60, max.attempts = 3, user_agent = DEFAULT_USER_AGENT)
{
    # Required in all expected BugSigDB CSV exports; used as validation sentinel.
    required.column <- "State"

    file_preview <- function(path, n.lines = 3, max.chars = 500)
    {
        if (!file.exists(path)) {
            return("<file does not exist>")
        }
        lines <- tryCatch(
            readLines(path, n = n.lines, warn = FALSE),
            error = function(e) paste0("<unable to read file: ", e$message, ">")
        )
        if (!length(lines)) {
            return("<file is empty>")
        }
        preview <- paste(lines, collapse = "\n")
        if (nchar(preview) > max.chars) {
            preview <- paste0(substr(preview, 1, max.chars), "...")
        }
        preview
    }

    is_valid_csv <- function(path)
    {
        if (!file.exists(path) || file.size(path) == 0L) {
            return(FALSE)
        }
        cols <- tryCatch(
            colnames(readr::read_csv(path, n_max = 0, show_col_types = FALSE)),
            error = function(e) NULL
        )
        required.column %in% cols
    }

    download_diagnostics <- function(csv, url, destfile)
    {
        size <- if (file.exists(destfile)) file.size(destfile) else NA_real_
        cols <- if (file.exists(destfile)) {
            tryCatch(
                colnames(readr::read_csv(destfile, n_max = 0, show_col_types = FALSE)),
                error = function(e) "<unavailable>"
            )
        } else {
            "<file does not exist>"
        }
        cols <- paste(cols, collapse = ", ")
        paste0(
            "file_key=", csv,
            "; url=", url,
            "; destfile=", normalizePath(destfile, mustWork = FALSE),
            "; size_bytes=", size,
            "; header_columns=", cols,
            "; file_head=", shQuote(file_preview(destfile))
        )
    }

    destfiles <- setNames(rep(NA_character_, length(links)), names(links))
    for (csv in names(links)) {
        url <- links[[csv]]
        destfile <- paste0(csv, ".csv")
        success <- FALSE
        last.error <- NULL
        for (attempt in seq_len(max.attempts)) {
            tryCatch({
                download.file(url,
                              destfile = destfile,
                              method = "curl",
                              extra = sprintf('--limit-rate 50K -A "%s"', user_agent))
                if (!is_valid_csv(destfile)) {
                    stop(paste("Downloaded file is not a valid BugSigDB CSV:",
                               download_diagnostics(csv, url, destfile)))
                }
                success <- TRUE
            },
            error = function(e) {
                last.error <<- e$message
                print(last.error)
                if (attempt < max.attempts) {
                    print(paste("Trying", url, "again in",
                                delay, "seconds"))
                    Sys.sleep(delay)
                }
            }
            )
            if (success) {
                break
            }
        }
        if (!success) {
            stop(paste0("Failed to download a valid CSV after ", max.attempts,
                        " attempts: ", download_diagnostics(csv, url, destfile),
                        "; last_error=",
                        ifelse(is.null(last.error), "unknown", last.error)))
        }
        destfiles[csv] <- file.path(getwd(), destfile)
    }
    return(destfiles)
}

readFiles <- function(files, delay = 60)
{
    stopifnot(file.exists(c(files["stud"], files["sig"], files["exp"])))
    studs <- readr::read_csv(files["stud"])
    studs <- subset(studs, State == "Complete")
    exps <- readr::read_csv(files["exp"])
    exps <- subset(exps, State == "Complete")
    sigs <- readr::read_csv(files["sig"])
    sigs <- subset(sigs, State == "Complete")
    # If not GitHub Action with BUGSIGDB_TIMESTAMP
    if (Sys.getenv("BUGSIGDB_TIMESTAMP") != "") {
        file.remove(c(files["stud"], files["sig"], files["exp"]))
    }
    print(gettextf("Successfully read csv files"))

    ind <- setdiff(colnames(studs), c("Reviewer", "State"))
    studs <- studs[,ind]
    ind <- colnames(studs) == "Study page name"
    colnames(studs)[ind] <- "Study"

    ind <- setdiff(colnames(exps), c("Reviewer", "State"))
    exps <- exps[,ind]
    ind <- colnames(exps) == "Experiment page name"
    colnames(exps)[ind] <- "Experiment"

    # sync studies and experiments
    ind <- exps$Study %in% studs$Study
    exps <- exps[ind,]
    ind <- match(exps$Study, studs$Study)
    stud.exp <- studs[ind,]
    ind <- colnames(exps) != "Study"
    exps <- cbind(stud.exp, exps[,ind])

    # remove signatures without experiments
    ses <- paste(sigs$Study, sigs$Experiment, sep = "-")
    es <- paste(exps$Study, exps$Experiment, sep = "-")
    ind <- ses %in% es
    sigs <- sigs[ind,]
    ses <- ses[ind]
    ind <- match(ses, es)
    exp.sig <- exps[ind,]
    ind <- setdiff(colnames(sigs), c("Study", "Experiment"))
    sigs <- cbind(exp.sig, sigs[,ind])

    # add NA fields for experiments without signatures
    ind <- es %in% ses
    fill.na <- exps[!ind,]
    na.cols <- setdiff(colnames(sigs), colnames(exps))
    na.df <- data.frame(matrix(NA, nrow = nrow(fill.na), ncol = length(na.cols)))
    colnames(na.df) <- na.cols
    fill.na <- cbind(fill.na, na.df)
    sigs <- rbind(sigs, fill.na)

    # order
    odf <- sigs[,c("Study", "Experiment", "Signature page name")]
    odf <- gsub("^[A-Z][a-z]+ ", "", as.matrix(odf))
    mode(odf) <- "integer"
    ind <- do.call(order, as.data.frame(odf))
    bugsigdb <- sigs[ind,]
    return(bugsigdb)
}

resolveCase <- function(bsdb, ncol = "Condition", icol = "EFO ID")
{
    spl <- split(bsdb[,ncol], bsdb[,icol])
    spl <- lapply(spl, unique)
    incons <- spl[lengths(spl) > 1]
    incons <- lapply(incons, tolower)
    incons <- lapply(incons, unique)
    incons <- incons[lengths(incons) == 1]
    for(n in names(incons))
    {
        ind  <- which(bsdb[,"EFO ID"] == n)
        bsdb[ind,"Condition"] <- incons[[n]]
    }
    return(bsdb)
}

addID <- function(df)
{
    eid <- sub("^Experiment ", "", df[["Experiment"]])
    sid <- sub("^Study ", "", df[["Study"]])
    sgid <- sub("^Signature ", "", df[["Signature page name"]])
    id <- paste(sid, eid, sgid, sep = "/")
    id <- paste("bsdb", id, sep = ":")
    df[,"BSDB ID"] <- id
    df <- df[,c(ncol(df),seq_len(ncol(df) - 1))]
    return(df)
}

## MAIN

# command line arguments
cmd.args <- commandArgs(trailingOnly = TRUE)
if(length(cmd.args) < 2 || length(cmd.args) > 3)
    stop("Usage: Rscript dump_release.R <version> <output.directory> <validate>")
version <- cmd.args[1]
out.dir <- cmd.args[2]
stopifnot(file.exists(out.dir))
validate <- ifelse(length(cmd.args) == 3, cmd.args[3] == 'true', FALSE)

# header line for output files
header <- paste0("# BugSigDB ", version,
                 ", License: Creative Commons Attribution 4.0 International",
                 ", URL: https://bugsigdb.org\n")

# import
links <- getBugSigDBExportURLs()
files <- downloadFiles(links)

bsdb <- readFiles(files)
abstr.col <- "Abstract"
bsdb <- bsdb[,colnames(bsdb) != abstr.col]

# resolve lower case / upper case inconsistencies
bsdb <- resolveCase(bsdb, ncol = "Condition", icol = "EFO ID")
bsdb <- resolveCase(bsdb, ncol = "Body site", icol = "UBERON ID")

# add BSDB ID
bsdb <- addID(bsdb)

# Perform additional validations to prepare for release
if (isTRUE(validate)) {
    print("Validating data for the release")
    bsdb <- bsdb |>
        dplyr::filter(stringr::str_detect(`BSDB ID`, "bsdb:.*/[0-9]+/[0-9]+|NA"),
                      !na_and_blank(Study),
                      !na_and_blank(`Study design`),
                      valid_pmid(PMID) | is.na(PMID),
                      !doi_url(DOI) | is.na(DOI),
                      valid_year(Year) | is.na(Year),
                      stringr::str_detect(Experiment, "Experiment [0-9]+"),
                      !is.na(Condition),
                      !na_and_blank(`EFO ID`),
                      !na_and_blank(`Group 0 name`),
                      !na_and_blank(`Group 1 name`),
                      !na_and_blank(`Group 1 definition`),
                      na_or_pos_int(`Group 0 sample size`),
                      na_or_pos_int(`Group 1 sample size`),
                      is.na(`Significance threshold`) |
                          between_exclusive(`Significance threshold`, 0, 1),
                      is.na(`LDA Score above`) | between_inclusive(`LDA Score above`, 0, 20),
                      stringr::str_detect(`Signature page name`, "Signature [0-9]+"),
                      !na_and_blank(Source),
                      # Check if valid date but not format
                      !is.na(as.Date(`Curated date`, format = "%d %B %Y")),
                      `Abundance in Group 1` %in% c("increased", "decreased"),
                      State == "Complete",
                      !is.na(Reviewer))
}

# write full dump
csv.file <- file.path(out.dir, "full_dump.csv")
cat(header, file = csv.file)
readr::write_csv(bsdb, file = csv.file, append = TRUE, col_names = TRUE)

# helper function to add a header line to an already written GMT file
addHeader <- function(header, out.file)
{
    fconn <- file(out.file, "r+")
    lines <- readLines(fconn)
    header <- sub("\n$", "", header)
    writeLines(c(header, lines), con = fconn)
    close(fconn)
}

# write GMT files for all combinations of ID type and taxonomic level
bsdb[["MetaPhlAn taxon names"]] <- strsplit(bsdb[["MetaPhlAn taxon names"]], ",")
bsdb[["NCBI Taxonomy IDs"]] <- strsplit(bsdb[["NCBI Taxonomy IDs"]], ";")

# rm empty strings
.rmEmpty <- function(x) x[x != ""]
bsdb[["MetaPhlAn taxon names"]] <- lapply(bsdb[["MetaPhlAn taxon names"]], .rmEmpty)
bsdb[["NCBI Taxonomy IDs"]] <- lapply(bsdb[["NCBI Taxonomy IDs"]], .rmEmpty)

# rm NA signatures
na.ind <- is.na(bsdb[["MetaPhlAn taxon names"]])
bsdb <- bsdb[!na.ind,]

tax.levels <- c("mixed", "genus", "species")
id.types <- c("ncbi", "metaphlan", "taxname")
exact.tax.levels <- c(TRUE, FALSE)

for(tl in tax.levels)
{
    for(it in id.types)
    {
        for(etl in exact.tax.levels)
        {
            if(tl == "mixed" && !etl) next
            sigs <- bugsigdbr::getSignatures(bsdb,
                                             tax.id.type = it,
                                             tax.level = tl,
                                             exact.tax.level = etl)
            gmt.file <- paste("bugsigdb", "signatures", tl, it, sep = "_")
            if(tl != "mixed" && etl) {
                gmt.file <- paste(gmt.file, "exact", sep = "_")
            }
            gmt.file <- paste(gmt.file, "gmt", sep = ".")
            gmt.file <- file.path(out.dir, gmt.file)
            bugsigdbr::writeGMT(sigs, gmt.file = gmt.file)
            addHeader(header, gmt.file)
        }
    }
}
