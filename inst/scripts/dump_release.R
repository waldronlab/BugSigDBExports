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
library(plyr)
library(readr)
library(rvest)

## FUNCTIONS

scrapeLinks <- function(url = "https://bugsigdb.org/Help:Export",
                        delay = 60)
{
    destfile <- "bugsigdb_help_export.html"
    tryCatch(
        download.file(url, destfile = destfile),
        error = function(e) {
            print(e$message)
            print(gettextf("Retrying in %s seconds", delay))
            Sys.sleep(delay)
            download.file(url, destfile = destfile)
        }
    )
    stopifnot(file.exists(destfile))
    dat <- rvest::read_html(destfile)
    file.remove(destfile)
    print(gettextf("Successfully read %s", url))
    elems <- rvest::html_elements(dat, ".smw-csv-furtherresults")
    elems <- rvest::html_elements(elems, "a")
    attr <- rvest::html_attr(elems, "href")
    names(attr) <- c("stud", "exp", "sig")
    prefix <- dirname(url)
    ind <- grepl(prefix, attr)
    attr[!ind] <- paste0(prefix, attr[!ind]) 
    return(attr)
}

readFiles <- function(links, delay = 60)
{
    csvs <- list("sig", "exp", "stud")
    for (csv in csvs) {
        tryCatch({
                destfile <- paste0(csv, ".csv")
                download.file(unname(links[csv]), destfile = destfile)
            },
            error = function(e) {
                print(e$message)
                print(gettextf("Retrying in %s seconds", delay))
                Sys.sleep(delay)
                download.file(unname(links[csv]), destfile = destfile)
            }
        )
    }
    stopifnot(file.exists(c("sig.csv", "exp.csv", "stud.csv")))
    studs <- readr::read_csv("stud.csv")
    studs <- subset(studs, State == "Complete")
    exps <- readr::read_csv("exp.csv")
    exps <- subset(exps, State == "Complete")
    sigs <- readr::read_csv("sig.csv")
    sigs <- subset(sigs, State == "Complete")
    file.remove(c("sig.csv", "exp.csv", "stud.csv"))
    print(gettextf("Successfully read csv files"))

    ind <- setdiff(colnames(studs), c("Reviewer", "State"))
    studs <- studs[,ind]
    ind <- colnames(studs) == "Study page name"
    colnames(studs)[ind] <- "Study"

    ind <- setdiff(colnames(exps), c("Reviewer", "State"))
    exps <- exps[,ind]
    ind <- colnames(exps) == "Experiment page name"
    colnames(exps)[ind] <- "Experiment"

    # remove experiments without signatures, and signatures without experiments
    ses <- paste(sigs$Study, sigs$Experiment, sep = "-")
    es <- paste(exps$Study, exps$Experiment, sep = "-")
    valid.entries <- unique(intersect(es, ses))
    spl <- strsplit(valid.entries, "-")
    valid.studs <- vapply(spl, `[`, character(1), x = 1)
    valid.studs <- unique(valid.studs)    
    studs <- subset(studs, Study %in% valid.studs)
    exps <- exps[es %in% valid.entries,]
    sigs <- sigs[ses %in% valid.entries,]

    sig.exp <- plyr::join(exps, sigs, by = c("Study", "Experiment"))
    sig.exp <- subset(sig.exp, Study %in% studs$Study)
    bugsigdb <- plyr::join(studs, sig.exp, by = "Study")
    return(bugsigdb)
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
links <- scrapeLinks()
bsdb <- readFiles(links)
abstr.col <- "Abstract"
bsdb <- bsdb[,colnames(bsdb) != abstr.col]


# resolve lower case / upper case inconsistencies

spl <- split(bsdb[,"Condition"], bsdb[,"EFO ID"])
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

spl <- split(bsdb[,"Body site"], bsdb[,"UBERON ID"])
spl <- lapply(spl, unique)
incons <- spl[lengths(spl) > 1]
incons <- lapply(incons, tolower)
incons <- lapply(incons, unique)
incons <- incons[lengths(incons) == 1]
for(n in names(incons))
{ 
    ind  <- which(bsdb[,"UBERON ID"] == n)   
    bsdb[ind,"Body site"] <- incons[[n]]
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
tax.levels <- c("mixed", "genus", "species")
id.types <- c("ncbi", "metaphlan", "taxname")
exact.tax.levels <- c(TRUE, FALSE)

for(tl in tax.levels)
{
    for(it in id.types)
    {
        for(etl in exact.tax.levels)
        {
            if(tl == "mixed" && etl) next
            sigs <- bugsigdbr::getSignatures(bsdb, 
                                             tax.id.type = it,
                                             tax.level = tl,
                                             exact.tax.level = etl)
            gmt.file <- paste("bugsigdb", "signatures", tl, it, sep = "_")
            if(etl) {
                gmt.file <- paste(gmt.file, "exact", sep = "_") 
            }
            gmt.file <- paste(gmt.file, "gmt", sep = ".")
            gmt.file <- file.path(out.dir, gmt.file)
            bugsigdbr::writeGMT(sigs, gmt.file = gmt.file) 
            addHeader(header, gmt.file)
        }
    }
}        

