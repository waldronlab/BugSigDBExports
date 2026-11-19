############################################################
#
# descr: read a release QC meta-issue on waldronlab/BugSigDBcuration (the
#        posted dropped.md written by dump_release.R) and add its ticked
#        "Release anyway" boxes to inst/extdata/release_qc_overrides.tsv.
#        "Fixed on bugsigdb.org" boxes are the curators' record only.
#        Fill in the reason column by hand and merge the change as a pull
#        request; that review is the approval.
#
# call: Rscript inst/scripts/scan_qc_issue.R <issue URL or owner/repo#number>
#
# needs: the gh CLI, logged in
#
############################################################

script.dir <- dirname(normalizePath(sub("^--file=", "",
    grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))))
source(file.path(script.dir, "release_qc.R"))
ov.file <- file.path(script.dir, "..", "extdata", "release_qc_overrides.tsv")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1)
    stop("Usage: Rscript scan_qc_issue.R <issue URL or owner/repo#number>")
m <- regmatches(args, regexec("github\\.com/([^/]+/[^/]+)/issues/([0-9]+)|^([^/#]+/[^/#]+)#([0-9]+)$", args))[[1]]
if (!length(m)) stop("Can't parse issue reference: ", args)
repo <- if (nzchar(m[2])) m[2] else m[4]
num <- if (nzchar(m[3])) m[3] else m[5]
issue <- sprintf("%s#%s", repo, num)

# The report is the issue body plus, when it's long, the comments that
# continue it (dropped-2.md, ...)
gh <- function(...) {
    out <- system2("gh", c("api", ...), stdout = TRUE)
    if (!is.null(attr(out, "status"))) stop("gh api failed for ", issue)
    out
}
lines <- c(gh(sprintf("repos/%s/issues/%s", repo, num), "--jq", ".body"),
           gh("--paginate", sprintf("repos/%s/issues/%s/comments", repo, num),
              "--jq", ".[].body"))
marks <- parseOverrideMarkers(lines)
if (!nrow(marks)) stop("No release QC checkboxes found in ", issue)

old <- readOverrides(ov.file)
key <- function(d) paste(d$check, d$bsdb_id)
bad <- !(marks$check %in% setdiff(names(CHECK_LABELS), NOT_OVERRIDABLE))
if (any(bad))
    warning("Skipping boxes for unknown or non-overridable checks: ",
            paste(unique(marks$check[bad]), collapse = ", "))
marks <- marks[!bad, ]
both <- marks$checked & marks$fixed
if (any(both)) {
    cat("Both Fixed and Release anyway are ticked; skipping these until one is unticked:\n")
    cat(sprintf("  %s\t%s\n", marks$check[both], marks$bsdb_id[both]), sep = "")
    marks <- marks[!both, ]
}

new <- unique(marks[marks$checked & !(key(marks) %in% key(old)), c("check", "bsdb_id")])
if (nrow(new)) {
    new$reason <- ""
    new$issue <- issue
    # rewrite the whole file, keeping any rows readOverrides() skipped
    raw <- if (file.exists(ov.file) && file.info(ov.file)$size > 0)
        utils::read.delim(ov.file, colClasses = "character", na.strings = "",
                          quote = "", comment.char = "") else old
    writeOverrides(rbind(raw, new[, OVERRIDE_COLUMNS]), ov.file)
}
cat(sprintf("%d ticked, %d added to %s\n", sum(marks$checked), nrow(new),
            normalizePath(ov.file)))

# Overrides whose Release anyway box is unticked in this issue: report, don't delete
unticked <- old[key(old) %in% key(marks[!marks$checked, ]), ]
if (nrow(unticked)) {
    cat("\nUnticked in", issue, "but present in the overrides file; remove them by hand if the override is revoked:\n")
    cat(sprintf("  %s\t%s\n", unticked$check, unticked$bsdb_id), sep = "")
}
if (nrow(new))
    cat("\nFill in the reason column for the new rows, then open a pull request.\n")
