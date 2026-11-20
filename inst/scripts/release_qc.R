############################################################
#
# descr: release QC for BugSigDB exports, sourced by dump_release.R and
#        scan_qc_issue.R. Checks which rows to drop from a release,
#        applies approved overrides from inst/extdata/release_qc_overrides.tsv,
#        and writes the release QC report (release_qc/dropped.md and
#        dropped.csv) for posting as a meta-issue on
#        waldronlab/BugSigDBcuration.
#
#        The report ends with "Kept, needs fixing" (also kept.csv):
#        problems in released data that don't justify dropping it, such as
#        a taxon in both the increased and decreased signature of an
#        experiment. It also lists Complete studies missing from every
#        export because their page name contains "/", which the BugSigDB
#        CSV export splits on. GitHub limits an issue or comment to 65,536
#        characters, so a long report is split into dropped-2.md, ...
#
############################################################

## Validation helpers

na_and_blank <- function(x)
    is.na(x) | !nzchar(trimws(x))

na_or_pos_int <- function(x)
{
    n <- suppressWarnings(as.numeric(x))
    is.na(x) | (!is.na(n) & n %% 1 == 0 & n > 0)
}

between_exclusive <- function(x, lower = 0, upper = 1)
    as.numeric(x) > lower & as.numeric(x) < upper

between_inclusive <- function(x, lower = 0, upper = 1)
    as.numeric(x) >= lower & as.numeric(x) <= upper

valid_year <- function(x) {
    stringr::str_detect(x, "^[0-9]{4,4}$") &
        as.numeric(x) >= 1999 & as.numeric(x) <= lubridate::year(Sys.Date())
}

valid_pmid <- function(x)
    stringr::str_detect(x, "^[0-9]{8,8}$")

valid_doi <- function(x)
    stringr::str_detect(x, "^10\\.[0-9]{4,9}/\\S+$")

# Strip "doi:" and doi.org URL prefixes, a trailing period and whitespace,
# and decode URL-encoded slashes, so that e.g.
# "doi: 10.1186/s40168-024-01758-4." becomes "10.1186/s40168-024-01758-4"
# and "10.3389%2Ffmicb.2022.875101" becomes "10.3389/fmicb.2022.875101"
normalize_doi <- function(x)
{
    x <- trimws(x)
    x <- sub("^(?i)[\\s:]*(doi:\\s*|(https?://)?(dx\\.)?doi\\.org[/_])?", "", x, perl = TRUE)
    x <- gsub("%2F", "/", x, ignore.case = TRUE)
    x <- gsub("\\s+", "", x)
    x <- sub("\\.$", "", x)
    x[!is.na(x) & !nzchar(x)] <- NA
    x
}


## Checks

# Short keys are used in the overrides file and in the hidden markers of
# dropped.md; labels are the headings of dropped.md.
CHECK_LABELS <- c(
    bsdb_id = "Malformed BSDB ID",
    study = "Study missing",
    study_design = "Study design missing",
    pmid = "Malformed PMID",
    identifier = "Neither a valid PMID nor a valid DOI",
    year = "Invalid year",
    experiment_name = "Malformed experiment name",
    condition = "Condition missing",
    efo_id = "EFO ID missing",
    group0_name = "Group 0 name missing",
    group1_name = "Group 1 name missing",
    group1_definition = "Group 1 definition missing",
    sample_size = "Sample size not a positive integer",
    significance = "Significance threshold not between 0 and 1",
    lda = "LDA score not between 0 and 20",
    signature_name = "Malformed signature name",
    source = "Source missing",
    curated_date = "Invalid curated date",
    abundance = "Abundance in Group 1 not increased or decreased",
    unreviewed = "Not reviewed",
    no_ncbi_taxa = "No taxa with an NCBI Taxonomy ID",
    retracted = "Retracted paper",
    review_incorrect = "Review state is Incorrect"
)

# Checks that an override cannot clear: unreviewed data needs review, and
# retracted and incorrect studies are never released
NOT_OVERRIDABLE <- c("unreviewed", "retracted", "review_incorrect")

# Explanations printed under a check's heading in dropped.md
CHECK_NOTES <- c(
    no_ncbi_taxa = paste(
        "Most of these signatures list taxa, but none of them resolved to an NCBI",
        "Taxonomy ID: GTDB names such as `Blautia A`, SILVA groups such as",
        "`Lachnospiraceae NK4A136 group`, outdated names such as `Proteobacteria`,",
        "or typos. The export leaves out unresolved names, so check the signature",
        "page; a curator can fix these by finding the right NCBI taxon. A few",
        "signatures list no taxa at all.")
)

# One column per check, named by key, TRUE where a row fails it. A row is
# dropped from the release if it fails any check that isn't overridden.
# Rows for experiments without complete signatures record a negative result
# or only alpha diversity. They skip the signature-level checks, and count as
# reviewed when their study's Review state is "Reviewed"; signatures count as
# reviewed when they have a Reviewer.
releaseChecks <- function(bsdb)
{
    # columns that come from bugsigdb.org's export; stop with a clear message
    # if one is renamed or dropped there
    needed <- c("BSDB ID", "Study", "Study design", "PMID", "DOI", "Year",
                "Experiment", "Condition", "EFO ID", "Group 0 name", "Group 1 name",
                "Group 1 definition", "Group 0 sample size", "Group 1 sample size",
                "Significance threshold", "LDA Score above", "Signature page name",
                "Source", "Curated date", "Abundance in Group 1", "Reviewer",
                "NCBI Taxonomy IDs", "Quality control tag", "Review state")
    missing <- setdiff(needed, names(bsdb))
    if (length(missing))
        stop("Release QC needs columns missing from the BugSigDB export: ",
             paste(missing, collapse = ", "))
    has.sig <- !is.na(bsdb[["Signature page name"]])
    fail <- function(pass, sig.level = FALSE)
    {
        pass[is.na(pass)] <- FALSE
        if (sig.level) pass[!has.sig] <- TRUE
        !pass
    }
    failed <- data.frame(
        bsdb_id = fail(stringr::str_detect(bsdb$`BSDB ID`, "bsdb:.*/[0-9]+/[0-9]+|NA")),
        study = fail(!na_and_blank(bsdb$Study)),
        study_design = fail(!na_and_blank(bsdb$`Study design`)),
        pmid = fail(valid_pmid(bsdb$PMID) | is.na(bsdb$PMID)),
        identifier = fail(valid_pmid(bsdb$PMID) | valid_doi(bsdb$DOI)),
        year = fail(valid_year(bsdb$Year) | is.na(bsdb$Year)),
        experiment_name = fail(stringr::str_detect(bsdb$Experiment, "Experiment [0-9]+")),
        condition = fail(!is.na(bsdb$Condition)),
        efo_id = fail(!na_and_blank(bsdb$`EFO ID`)),
        group0_name = fail(!na_and_blank(bsdb$`Group 0 name`)),
        group1_name = fail(!na_and_blank(bsdb$`Group 1 name`)),
        group1_definition = fail(!na_and_blank(bsdb$`Group 1 definition`)),
        sample_size = fail(na_or_pos_int(bsdb$`Group 0 sample size`) &
                           na_or_pos_int(bsdb$`Group 1 sample size`)),
        significance = fail(is.na(bsdb$`Significance threshold`) |
                            between_exclusive(bsdb$`Significance threshold`, 0, 1)),
        lda = fail(is.na(bsdb$`LDA Score above`) |
                   between_inclusive(bsdb$`LDA Score above`, 0, 20)),
        signature_name = fail(stringr::str_detect(bsdb$`Signature page name`,
                                                  "Signature [0-9]+"), TRUE),
        source = fail(!na_and_blank(bsdb$Source), TRUE),
        curated_date = fail(!is.na(as.Date(bsdb$`Curated date`, format = "%d %B %Y")), TRUE),
        abundance = fail(bsdb$`Abundance in Group 1` %in% c("increased", "decreased"), TRUE),
        unreviewed = fail(ifelse(has.sig, !is.na(bsdb$Reviewer),
                                 bsdb$`Review state` %in% "Reviewed")),
        no_ncbi_taxa = fail(!na_and_blank(bsdb$`NCBI Taxonomy IDs`), TRUE),
        retracted = fail(!grepl("Retracted paper", bsdb$`Quality control tag`, fixed = TRUE)),
        review_incorrect = fail(!(bsdb$`Review state` %in% "Incorrect"))
    )
    stopifnot(identical(names(failed), names(CHECK_LABELS)))
    failed
}


## Kept, needs fixing

# Problems in released data that don't justify dropping it, listed in
# dropped.md for curators. Labels are the headings of dropped.md.
KEPT_LABELS <- c(
    both_directions = "Taxon in both the increased and decreased signature",
    identical_signatures = "Identical signatures in one experiment",
    duplicate_taxa = "Same taxon listed twice in a signature",
    same_group_names = "Group 0 name equal to Group 1 name",
    group_size_one = "Group of size 1",
    shared_doi = "Same DOI as another study",
    malformed_doi = "DOI that normalization can't fix",
    empty_ncbi_id = "Empty entry in the NCBI Taxonomy ID list"
)

KEPT_NOTES <- c(
    both_directions = paste(
        "Within one experiment, the same taxon is in a signature with increased",
        "abundance and in one with decreased abundance. Shown as the number of",
        "such taxa, with the number at species level, and the first few names."),
    duplicate_taxa = paste(
        "Usually two names that NCBI Taxonomy treats as synonyms; keep one."),
    empty_ncbi_id = paste(
        "Not for curators: these signatures list a taxon whose NCBI ID has no",
        "ranked lineage, such as 2 (Bacteria), which the BugSigDB export writes",
        "as an empty entry. Listed for the BugSigDB export to fix.")
)

# Checks listed without checkboxes, because curators can't fix them
KEPT_NO_CHECKBOX <- "empty_ncbi_id"

# Last element of MetaPhlAn names, without its rank prefix
taxonLeaf <- function(x) sub("^.*\\|?[a-z]__", "", x)

# One row per flagged experiment or signature (or study, for DOI problems):
# check key, Study, item ("2" for Experiment 2, "2/1" for its Signature 1,
# or "" for the study) and a short detail.
keptProblems <- function(bsdb)
{
    out <- list()
    add <- function(check, study, item, detail = "")
        if (length(study))
            out[[length(out) + 1]] <<- data.frame(check = check, Study = study,
                                                 item = item, detail = detail)
    expNum <- function(e) sub("^Experiment ", "", e)
    sigNum <- function(s) sub("^Signature ", "", s)

    sigs <- bsdb[!is.na(bsdb$`Signature page name`), ]
    noNA <- function(x) { x <- as.character(x); x[is.na(x)] <- ""; x }
    raw.ids <- noNA(sigs$`NCBI Taxonomy IDs`)
    ids <- strsplit(raw.ids, ";")
    mp <- strsplit(noNA(sigs$`MetaPhlAn taxon names`), ",")
    aligned <- lengths(ids) == lengths(mp)
    dir <- sigs$`Abundance in Group 1`

    # signature level
    dup <- vapply(ids, function(x) anyDuplicated(x[x != ""]) > 0, logical(1))
    dup.names <- vapply(which(dup), function(i) {
        x <- ids[[i]]
        d <- unique(x[x != "" & duplicated(x)])
        if (aligned[i]) paste(unique(taxonLeaf(mp[[i]][x %in% d])), collapse = ", ")
        else paste(d, collapse = ", ")
    }, character(1))
    add("duplicate_taxa", sigs$Study[dup],
        paste(expNum(sigs$Experiment[dup]), sigNum(sigs$`Signature page name`[dup]), sep = "/"),
        dup.names)
    # an empty entry anywhere, including a leading or trailing ";"
    emp <- nzchar(raw.ids) & grepl("(^|;)(;|$)", raw.ids)
    add("empty_ncbi_id", sigs$Study[emp],
        paste(expNum(sigs$Experiment[emp]), sigNum(sigs$`Signature page name`[emp]), sep = "/"))

    # experiment level, over signatures
    by.exp <- split(seq_len(nrow(sigs)), factor(paste(sigs$Study, sigs$Experiment, sep = "\r"),
                                                 levels = unique(paste(sigs$Study, sigs$Experiment, sep = "\r"))))
    for (r in by.exp) {
        study <- sigs$Study[r[1]]
        exp <- expNum(sigs$Experiment[r[1]])
        inc <- r[dir[r] %in% "increased"]
        dec <- r[dir[r] %in% "decreased"]
        both <- setdiff(intersect(unlist(ids[inc]), unlist(ids[dec])), "")
        if (length(both)) {
            names.r <- r[aligned[r]]
            lookup <- setNames(as.character(unlist(mp[names.r])),
                               as.character(unlist(ids[names.r])))
            nm <- unname(lookup[both])
            nm[is.na(nm)] <- both[is.na(nm)]
            nspec <- sum(grepl("s__[^|]*$", nm))
            first <- paste(head(taxonLeaf(nm), 3), collapse = ", ")
            add("both_directions", study, exp,
                sprintf("%d %s, %d species: %s%s", length(both),
                        if (length(both) == 1) "taxon" else "taxa", nspec, first,
                        if (length(both) > 3) ", ..." else ""))
        }
        key <- vapply(ids[r], function(x) paste(sort(unique(x[x != ""])), collapse = ";"), character(1))
        key[!nzchar(key)] <- NA
        d <- !is.na(key) & (duplicated(key) | duplicated(key, fromLast = TRUE))
        if (any(d)) {
            sets <- split(sigNum(sigs$`Signature page name`[r][d]), key[d])
            add("identical_signatures", study, exp,
                paste(vapply(sets, function(s) paste("Signatures", paste(s, collapse = " and ")),
                             character(1)), collapse = "; "))
        }
    }

    # experiment level, over experiments
    exps <- bsdb[!duplicated(bsdb[, c("Study", "Experiment")]), ]
    same <- !is.na(exps$`Group 0 name`) & !is.na(exps$`Group 1 name`) &
        trimws(tolower(exps$`Group 0 name`)) == trimws(tolower(exps$`Group 1 name`))
    add("same_group_names", exps$Study[same], expNum(exps$Experiment[same]),
        exps$`Group 1 name`[same])
    n0 <- suppressWarnings(as.numeric(exps$`Group 0 sample size`))
    n1 <- suppressWarnings(as.numeric(exps$`Group 1 sample size`))
    one <- n0 %in% 1 | n1 %in% 1
    add("group_size_one", exps$Study[one], expNum(exps$Experiment[one]),
        sprintf("Group 0: %s, Group 1: %s", n0[one], n1[one]))

    # study level
    studs <- bsdb[!duplicated(bsdb$Study), c("Study", "DOI")]
    studs <- studs[!is.na(studs$DOI), ]
    doi <- tolower(studs$DOI)
    shared <- doi %in% doi[duplicated(doi)]
    add("shared_doi", studs$Study[shared], "",
        vapply(which(shared), function(i)
            paste("same as", paste(setdiff(studs$Study[doi == doi[i]], studs$Study[i]),
                                   collapse = ", ")), character(1)))
    bad <- !valid_doi(studs$DOI)
    add("malformed_doi", studs$Study[bad], "", studs$DOI[bad])

    if (!length(out))
        return(data.frame(check = character(), Study = character(),
                          item = character(), detail = character()))
    kept <- do.call(rbind, out)
    kept$check <- factor(kept$check, levels = names(KEPT_LABELS))
    kept <- kept[order(kept$check), ]
    kept$check <- as.character(kept$check)
    rownames(kept) <- NULL
    kept
}


## Overrides

OVERRIDE_COLUMNS <- c("check", "bsdb_id", "reason", "issue")

readOverrides <- function(file)
{
    if (!file.exists(file) || file.info(file)$size == 0) {
        warning("No release QC overrides in ", file)
        return(data.frame(check = character(), bsdb_id = character(),
                          reason = character(), issue = character()))
    }
    ov <- utils::read.delim(file, colClasses = "character", na.strings = "",
                            quote = "", comment.char = "")
    stopifnot(identical(names(ov), OVERRIDE_COLUMNS))
    bad <- !(ov$check %in% setdiff(names(CHECK_LABELS), NOT_OVERRIDABLE))
    if (any(bad))
        warning("Ignoring overrides for unknown or non-overridable checks: ",
                paste(unique(ov$check[bad]), collapse = ", "))
    ov <- ov[!bad, ]
    ov[!duplicated(ov[, c("check", "bsdb_id")]), ]
}

writeOverrides <- function(ov, file)
    utils::write.table(ov[, OVERRIDE_COLUMNS], file, sep = "\t", quote = FALSE,
                       row.names = FALSE, na = "")

# Clear the failures that an override approves. Returns the updated failures,
# a logical matrix of the failures that were cleared, and the overrides that
# matched no failure (stale: the signature is gone or now passes the check).
applyOverrides <- function(bsdb, failed, overrides)
{
    cleared <- failed
    cleared[] <- FALSE
    used <- logical(nrow(overrides))
    for (i in seq_len(nrow(overrides))) {
        rows <- which(bsdb$`BSDB ID` == overrides$bsdb_id[i])
        col <- overrides$check[i]
        hit <- rows[failed[rows, col]]
        if (length(hit)) {
            used[i] <- TRUE
            cleared[hit, col] <- TRUE
            failed[hit, col] <- FALSE
        }
    }
    list(failed = failed, cleared = cleared, stale = overrides[!used, ])
}


## Report

# Hidden marker on each checkbox line of dropped.md, read by scan_qc_issue.R:
# <!-- qc-override check=<key> study=<study> ids=<exp/sig>,<exp/sig> -->,
# where study/exp/sig make up the BSDB ID bsdb:<study>/<exp>/<sig>, and "%",
# " ", "," and ">" in the study are percent-encoded.
encodeId <- function(x)
{
    for (ch in c("%", " ", ",", ">"))
        x <- gsub(ch, sprintf("%%%02X", utf8ToInt(ch)), x, fixed = TRUE)
    x
}

decodeId <- function(x) utils::URLdecode(x)

overrideMarker <- function(check, bsdb.ids)
{
    id <- sub("^bsdb:", "", bsdb.ids)
    study <- unique(sub("/[^/]+/[^/]+$", "", id))
    stopifnot(length(study) == 1)
    sprintf("<!-- qc-override check=%s study=%s ids=%s -->", check, encodeId(study),
            paste(sub("^.*/([^/]+/[^/]+)$", "\\1", id), collapse = ","))
}

# Parse the Release anyway boxes; returns check, bsdb_id, whether the box
# is ticked, and whether the Fixed on bugsigdb.org box above it is ticked
parseOverrideMarkers <- function(lines)
{
    pat <- "^\\s*- \\[([ xX])\\] .*<!-- qc-override check=([a-z0-9_]+) study=(\\S+) ids=(\\S+) -->"
    m <- regmatches(lines, regexec(pat, lines))
    i <- which(lengths(m) == 5)
    if (!length(i))
        return(data.frame(check = character(), bsdb_id = character(),
                          checked = logical(), fixed = logical()))
    # the Fixed box is a sibling under the same study bullet, above this one
    fixed <- vapply(i, function(k) {
        j <- k - 1
        while (j >= 1 && !grepl("^- ", lines[j])) {
            if (grepl("^\\s*- \\[[xX]\\] Fixed on bugsigdb.org", lines[j])) return(TRUE)
            j <- j - 1
        }
        FALSE
    }, logical(1))
    do.call(rbind, lapply(seq_along(i), function(j) {
        x <- m[[i[j]]]
        ids <- strsplit(x[5], ",")[[1]]
        data.frame(check = x[3], bsdb_id = sprintf("bsdb:%s/%s", decodeId(x[4]), ids),
                   checked = tolower(x[2]) == "x", fixed = fixed[j])
    }))
}

# Markdown list of dropped data, grouped by check and study, for a human to
# review and post as a meta-issue on waldronlab/BugSigDBcuration
#
# kept: data frame from keptProblems() on the released rows, listed in a
# "Kept, needs fixing" part; kept.csv is written next to csv.file.
# unexported: Complete studies whose experiments and signatures can't be
# matched to them in the BugSigDB export (page names containing "/").
writeDroppedReport <- function(bsdb, failed, cleared, stale, version,
                               md.file, csv.file, max.ids = 10,
                               kept = NULL, unexported = character())
{
    dropped <- rowSums(failed) > 0
    reasons <- apply(failed[dropped, , drop = FALSE], 1,
                     function(r) paste(CHECK_LABELS[names(failed)[r]], collapse = "; "))
    readr::write_csv(cbind(bsdb[dropped, c("BSDB ID", "Study", "Experiment",
                                           "Signature page name", "PMID", "DOI")],
                           Reasons = as.character(reasons)), csv.file)

    page <- function(...) paste0("https://bugsigdb.org/", gsub(" ", "_", paste(..., sep = "/")))
    nstud <- function(i) length(unique(bsdb$Study[i]))
    byStudy <- function(i) split(which(i), factor(bsdb$Study[i], levels = unique(bsdb$Study[i])))
    # one checkbox line per study, with a hidden marker listing all its IDs;
    # plain bullets for checks that can't be overridden
    # One entry per study with two boxes: "Fixed on bugsigdb.org" for the
    # curator's record, and "Release anyway", whose hidden marker lists all
    # its IDs for scan_qc_issue.R. Checks that can't be overridden get only
    # the first box; released overrides get only the second, ticked.
    items <- function(key, i, released = FALSE) {
        overridable <- !(key %in% NOT_OVERRIDABLE)
        by.study <- byStudy(i)
        unlist(lapply(names(by.study), function(s) {
            rows <- by.study[[s]]
            exp <- bsdb$Experiment[rows]
            sig <- bsdb$`Signature page name`[rows]
            # experiment/signature numbers, e.g. 2/1; the study link leads to them
            ids <- ifelse(is.na(sig), exp,
                          paste(sub("^Experiment ", "", exp), sub("^Signature ", "", sig), sep = "/"))
            more <- if (length(ids) > max.ids) sprintf(" and %d more", length(ids) - max.ids) else ""
            c(sprintf("- [%s](%s): %s%s", s, page(s),
                      paste(head(ids, max.ids), collapse = ", "), more),
              if (!released) "  - [ ] Fixed on bugsigdb.org",
              if (overridable)
                  sprintf("  - [%s] Release anyway %s", if (released) "x" else " ",
                          overrideMarker(key, bsdb$`BSDB ID`[rows])))
        }))
    }

    counts <- vapply(failed, sum, numeric(1))
    out <- c(
        paste("Data dropped by release QC from the BugSigDB export of", version),
        "",
        sprintf(paste("%d signatures and %d experiments without signatures, from %d studies,",
                      "pass; %d rows from %d studies are dropped."),
                sum(!dropped & !is.na(bsdb$`Signature page name`)),
                sum(!dropped & is.na(bsdb$`Signature page name`)),
                nstud(!dropped), sum(dropped), nstud(dropped)),
        "A study can have both passing and dropped rows, and a row can fail more than one",
        "check, so it can appear in more than one section. Studies, experiments and",
        "signatures that are not Complete are left out of every export and are not listed here.",
        "",
        paste("Each study has two boxes. Tick **Fixed on bugsigdb.org** after correcting",
              "the study; fixed data passes in the next export and drops out of the next",
              "report. Tick **Release anyway** only for data that is right as it is and",
              "should be released despite the check. Release anyway boxes become",
              "overrides in `inst/extdata/release_qc_overrides.tsv` of",
              "waldronlab/BugSigDBExports through `inst/scripts/scan_qc_issue.R`, after",
              "review in a pull request; an override covers one check for the listed",
              "signatures only. Studies without a Release anyway box can't be overridden."),
        "",
        "| Check | Rows | Studies |", "|---|---|---|")
    for (k in names(failed)[counts > 0])
        out <- c(out, sprintf("| %s | %d | %d |", CHECK_LABELS[[k]], counts[[k]], nstud(failed[[k]])))

    # one element per section, packed into parts below
    sections <- list()
    for (k in names(failed)[counts > 0]) {
        sec <- c("", paste("###", CHECK_LABELS[[k]]), "")
        if (k %in% names(CHECK_NOTES)) sec <- c(sec, CHECK_NOTES[[k]], "")
        if (k == "unreviewed") {
            # the review backlog: list studies only, without checkboxes
            by.study <- byStudy(failed[[k]])
            links <- sprintf("%s (%d)", names(by.study), lengths(by.study))
            sec <- c(sec, sprintf("<details><summary>%d studies, with the number of %s</summary>",
                                  length(links), "unreviewed rows"),
                     "", paste(links, collapse = ", "), "", "</details>")
        } else {
            # not collapsed in <details>, where GitHub may disable checkboxes
            sec <- c(sec, items(k, failed[[k]]))
        }
        sections <- c(sections, list(sec))
    }
    if (any(as.matrix(cleared))) {
        sec <- c("", "### Released by override", "",
                 paste("Approved in `inst/extdata/release_qc_overrides.tsv`. Untick a box",
                       "to propose removing the override."))
        for (k in names(cleared)[colSums(cleared) > 0])
            sec <- c(sec, "", paste0("**", CHECK_LABELS[[k]], "**"), "",
                     items(k, cleared[[k]], released = TRUE))
        sections <- c(sections, list(sec))
    }
    if (nrow(stale)) {
        sections <- c(sections, list(c("", "### Stale overrides", "",
            "These overrides match nothing in this export; remove them from the overrides file.", "",
            sprintf("- %s: %s", stale$check, stale$bsdb_id))))
    }
    if (length(unexported)) {
        sections <- c(sections, list(c("", "### Study page name contains a slash", "",
            paste("These Complete studies are missing from every export, because the",
                  "BugSigDB CSV export splits page names at `/`, so their experiments and",
                  "signatures can't be matched to them. Studies named by a URL should be",
                  "renamed to their PMID or DOI."), "",
            fixedBoxes(sprintf("[%s](%s)", unexported, page(unexported))))))
    }

    if (!is.null(kept) && nrow(kept)) {
        readr::write_csv(kept, file.path(dirname(csv.file), "kept.csv"))
        kcounts <- table(factor(kept$check, levels = names(KEPT_LABELS)))
        kstud <- tapply(kept$Study, factor(kept$check, levels = names(KEPT_LABELS)),
                        function(s) length(unique(s)))
        has <- names(kcounts)[kcounts > 0]
        sections <- c(sections, list(c("", "## Kept, needs fixing", "",
            paste("Problems in released data that don't justify dropping it. Tick",
                  "**Fixed on bugsigdb.org** after correcting the study. Items are",
                  "experiments (`2`), signatures (`2/1`) or the whole study."), "",
            "| Problem | Items | Studies |", "|---|---|---|",
            sprintf("| %s | %d | %d |", KEPT_LABELS[has], kcounts[has], kstud[has]))))
        for (k in has) {
            kk <- kept[kept$check == k, ]
            sec <- c("", paste("###", KEPT_LABELS[[k]]), "")
            if (k %in% names(KEPT_NOTES)) sec <- c(sec, KEPT_NOTES[[k]], "")
            by.study <- split(seq_len(nrow(kk)), factor(kk$Study, levels = unique(kk$Study)))
            lines <- vapply(names(by.study), function(s) {
                i <- by.study[[s]]
                if (k == "malformed_doi") kk$detail[i] <- sprintf("`%s`", kk$detail[i])
                it <- ifelse(nzchar(kk$item[i]),
                             ifelse(nzchar(kk$detail[i]), sprintf("%s (%s)", kk$item[i], kk$detail[i]),
                                    kk$item[i]),
                             kk$detail[i])
                more <- if (length(it) > max.ids) sprintf(" and %d more", length(it) - max.ids) else ""
                sprintf("[%s](%s): %s%s", s, page(s), paste(head(it, max.ids), collapse = "; "), more)
            }, character(1))
            if (k %in% KEPT_NO_CHECKBOX)
                sec <- c(sec, sprintf("<details><summary>%d studies</summary>", length(lines)), "",
                         paste0("- ", lines), "", "</details>")
            else
                sec <- c(sec, fixedBoxes(lines))
            # shown where a comment starts inside this part
            attr(sec, "continued") <- keptContinued(!(k %in% KEPT_NO_CHECKBOX))
            sections <- c(sections, list(sec))
        }
    }
    writeReportParts(out, sections, md.file)
}

# One study per line, each with a labelled Fixed on bugsigdb.org box, as in
# the dropped sections
fixedBoxes <- function(lines)
    as.vector(rbind(paste0("- ", lines), "  - [ ] Fixed on bugsigdb.org"))

keptContinued <- function(boxes = TRUE)
    paste("**Kept, needs fixing (continued)**: released data with problems to fix",
          if (boxes) "on bugsigdb.org. Tick **Fixed on bugsigdb.org** after correcting the study."
          else "on bugsigdb.org.")

# GitHub limits an issue body or comment to 65,536 characters. Pack the
# sections into dropped.md (the issue body) and, if needed, dropped-2.md,
# dropped-3.md, ... (one comment each), keeping each section whole. A
# section's "continued" attribute is shown when it starts a new part.
writeReportParts <- function(header, sections, md.file, limit = 60000)
{
    size <- function(x) sum(nchar(x, type = "bytes")) + length(x)
    parts <- list(header)
    for (sec in sections) {
        n <- length(parts)
        if (size(parts[[n]]) + size(sec) > limit)
            parts[[n + 1]] <- c(if (!is.null(attr(sec, "continued")))
                                    c(attr(sec, "continued"), ""),
                                sec[-1])
        else
            parts[[n]] <- c(parts[[n]], sec)
    }
    files <- md.file
    if (length(parts) > 1) {
        files <- c(md.file, paste0(sub("\\.md$", "", md.file), "-", seq_along(parts)[-1], ".md"))
        parts[[1]] <- c(parts[[1]], "",
            sprintf("Continued in the next %s, posted from `%s`.",
                    ifelse(length(parts) == 2, "comment", paste(length(parts) - 1, "comments")),
                    paste(basename(files[-1]), collapse = "`, `")))
    }
    for (i in seq_along(parts)) {
        writeLines(parts[[i]], files[i])
        print(gettextf("Wrote release QC report: %s (%d characters)", files[i], size(parts[[i]])))
        if (size(parts[[i]]) > 65536)
            warning(files[i], " exceeds GitHub's 65,536 character limit; split its largest section")
    }
}
