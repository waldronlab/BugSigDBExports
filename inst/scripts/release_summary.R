############################################################
#
# descr: SUMMARY line for NEWS, computed from the exported full_dump.csv
#        rather than its line count, which also counts line breaks inside
#        Description fields. Compares with the previous release.
#
# call: Rscript release_summary.R <new full_dump.csv> <previous full_dump.csv> [<previous NEWS>]
#
############################################################

cmd.args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(cmd.args) %in% 2:3)

readDump <- function(file)
{
    # the first line is the "# BugSigDB <version>, License: ..." header
    skip <- as.integer(startsWith(readLines(file, n = 1), "#"))
    readr::read_csv(file, skip = skip, show_col_types = FALSE,
                    col_types = readr::cols(.default = readr::col_character()))
}

# rows without a signature are experiments recording a negative taxonomic
# result or alpha diversity
counts <- function(bsdb)
    c(signatures = sum(!is.na(bsdb$`Signature page name`)),
      experiments = sum(is.na(bsdb$`Signature page name`)),
      studies = length(unique(bsdb$Study)))

new <- counts(readDump(cmd.args[1]))
old <- if (file.exists(cmd.args[2])) counts(readDump(cmd.args[2])) else
    c(signatures = 0, experiments = 0, studies = 0)

prev <- "the previous release"
if (length(cmd.args) == 3 && file.exists(cmd.args[3])) {
    v <- grep("^CHANGES IN VERSION ", readLines(cmd.args[3]), value = TRUE)
    if (length(v)) prev <- sub("^CHANGES IN VERSION ", "", v[1])
}

fmt <- function(x) format(x, big.mark = ",", trim = TRUE)
text <- sprintf(paste("SUMMARY: %s signatures and %s experiments without",
                      "signatures from %s studies (%s: %s, %s and %s)"),
                fmt(new[["signatures"]]), fmt(new[["experiments"]]), fmt(new[["studies"]]),
                prev, fmt(old[["signatures"]]), fmt(old[["experiments"]]),
                fmt(old[["studies"]]))
writeLines(strwrap(text, width = 72, initial = "    o ", prefix = "      "))
