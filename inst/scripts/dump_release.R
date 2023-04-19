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
#     sigs <- subset(sigs, State == "Complete") ## uncomment when State issue resolved
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
links <- scrapeLinks()
bsdb <- readFiles(links)
abstr.col <- "Abstract"
bsdb <- bsdb[,colnames(bsdb) != abstr.col]

# resolve lower case / upper case inconsistencies
bsdb <- resolveCase(bsdb, ncol = "Condition", icol = "EFO ID")
bsdb <- resolveCase(bsdb, ncol = "Body site", icol = "UBERON ID")

# add BSDB ID
bsdb <- addID(bsdb)

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

# Change back to the following when fixed:
# tax.levels <- c("mixed", "genus", "species")
# id.types <- c("ncbi", "metaphlan", "taxname")
tax.levels <- c("mixed")
id.types <- c("metaphlan")
exact.tax.levels <- c(TRUE, FALSE)

for(tl in tax.levels)
{
    for(it in id.types)
    {
        for(etl in exact.tax.levels)
        {
            if(tl == "mixed" && etl) next
          print(paste0("Starting tl: ", tl, "  /  it: ", it, "  /  etl: ", etl))
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
            print(paste0("Finished tl: ", tl, "  /  it: ", it, "  /  etl: ", etl))
        }
    }
}        

