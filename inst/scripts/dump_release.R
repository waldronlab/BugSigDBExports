###########################################################
# 
# author: Ludwig Geistlinger
# date: 2021-07-13 19:49:35
# 
# descr: dump all files associated with a BugSigDB release
#        into a specified folder
#
# call: Rscript dump_release.R <version> <output.directory> 
#
############################################################

library(bugsigdbr)
library(countries)
library(lubridate)
library(plyr)
library(dplyr)
library(readr)
library(rvest)
library(stringr)


not_na_or_blank <- function(x) 
    !is.na(x) | x != ""

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


## FUNCTIONS

downloadFiles <- function(links, delay = 60)
{
    destfiles <- names(links)
    for (csv in destfiles) {
        tryCatch({
                destfile <- paste0(csv, ".csv")
                download.file(unname(links[csv]),
                              destfile = destfile,
                              method = "curl",
                              extra = "--limit-rate 50K")
                stopifnot(file.size(destfile) != 0L)
            },
            error = function(e) {
                print(e$message)
                print(paste("Trying", links[csv], "again in",
                            delay, "seconds"))
                Sys.sleep(delay)
                download.file(unname(links[csv]), destfile = destfile)
            }
        )
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
if(length(cmd.args) != 2) 
    stop("Usage: Rscript dump_release.R <version> <output.directory>")
version <- cmd.args[1]
out.dir <- cmd.args[2]
stopifnot(file.exists(out.dir))

# header line for output files
header <- paste0("# BugSigDB ", version, 
                 ", License: Creative Commons Attribution 4.0 International",
                 ", URL: https://bugsigdb.org\n")

# import
links <- c(stud = "https://bugsigdb.org/w/images/csv_reports/studies.csv",
           exp = "https://bugsigdb.org/w/images/csv_reports/experiments.csv",
           sig = "https://bugsigdb.org/w/images/csv_reports/signatures.csv")
#files <- downloadFiles(links)

files <- c(stud = "stud.csv", sig = "sig.csv", exp = "exp.csv")
bsdb <- readFiles(files)
abstr.col <- "Abstract"
bsdb <- bsdb[,colnames(bsdb) != abstr.col]

# resolve lower case / upper case inconsistencies
bsdb <- resolveCase(bsdb, ncol = "Condition", icol = "EFO ID")
bsdb <- resolveCase(bsdb, ncol = "Body site", icol = "UBERON ID")

# add BSDB ID
bsdb <- addID(bsdb)

qc_bsdb <- bsdb |>
    dplyr::filter(stringr::str_detect(`BSDB ID`, "bsdb:.*/[0-9]+/[0-9]+"),
                  not_na_or_blank(Study),
                  not_na_or_blank(`Study design`),
                  valid_pmid(PMID) | is.na(PMID),
                  !doi_url(DOI) | is.na(DOI),
                  valid_year(Year) | is.na(Year),
                  stringr::str_detect(Experiment, "Experiment [0-9]+"),
                  countries::is_country(`Location of subjects`),
                  !is.na(Condition),
                  not_na_or_blank(`EFO ID`),
                  not_na_or_blank(`Group 0 name`),
                  not_na_or_blank(`Group 1 name`),
                  not_na_or_blank(`Group 1 definition`),
                  na_or_pos_int(`Group 0 sample size`),
                  na_or_pos_int(`Group 1 sample size`),
                  is.na(`Significance threshold`) | 
                      between_exclusive(`Significance threshold`, 0, 1),
                  is.na(`LDA Score above`) | between_inclusive(`LDA Score above`, 0, 20),
                  stringr::str_detect(`Signature page name`, "Signature [0-9]+"),
                  not_na_or_blank(Source),
                  # Check if valid date but not format
                  !is.na(as.Date(`Curated date`, format = "%d %B %Y")),
                  `Abundance in Group 1` %in% c("increased", "decreased"),
                  State == "Complete",
                  !is.na(Reviewer))

# write full dump
csv.file <- file.path(out.dir, "full_dump.csv")
cat(header, file = csv.file)
readr::write_csv(qc_bsdb, file = csv.file, append = TRUE, col_names = TRUE)

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

