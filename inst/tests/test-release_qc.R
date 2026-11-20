# Tests for inst/scripts/release_qc.R and release_summary.R.
# Run from the repository root: Rscript -e 'testthat::test_dir("inst/tests")'

library(testthat)
scripts <- file.path(testthat::test_path(), "..", "scripts")
source(file.path(scripts, "release_qc.R"))

test_that("normalize_doi strips prefixes, decodes %2F and removes whitespace", {
    expect_equal(normalize_doi(c("doi: 10.1186/s40168-024-01758-4.",
                                 "https://doi.org/10.1186/abc",
                                 "http://dx.doi.org/10.1186/abc",
                                 "10.3389%2Ffmicb.2022.875101",
                                 "10.1038/ s41531-026-01332-9",
                                 "  ", NA)),
                 c("10.1186/s40168-024-01758-4", "10.1186/abc", "10.1186/abc",
                   "10.3389/fmicb.2022.875101", "10.1038/s41531-026-01332-9",
                   NA, NA))
    # can't be fixed, so valid_doi still fails them
    bad <- normalize_doi(c("0.1186/s12879-020-05324-9", "http://dx.doi. 438 org/10.3233/JAD-180176"))
    expect_false(any(valid_doi(bad)))
})

# Minimal release rows: one per signature, or per experiment without signatures
mk <- function(study, exp, sig, dir = "increased", ids = "1|2", mp = "k__A|p__B",
               doi = NA, g0 = "control", g1 = "case", n0 = 10, n1 = 10)
    data.frame(Study = study, Experiment = paste("Experiment", exp),
               `Signature page name` = ifelse(is.na(sig), NA, paste("Signature", sig)),
               `Abundance in Group 1` = dir, `NCBI Taxonomy IDs` = ids,
               `MetaPhlAn taxon names` = mp, DOI = doi, `Group 0 name` = g0,
               `Group 1 name` = g1, `Group 0 sample size` = n0,
               `Group 1 sample size` = n1, check.names = FALSE)

flagged <- function(kept, check) kept[kept$check == check, ]

test_that("keptProblems finds a taxon in both directions, with species counts", {
    b <- rbind(mk("1", 1, 1, "increased", "1|2;1|2|3", "k__A|g__B,k__A|g__B|s__B c"),
               mk("1", 1, 2, "decreased", "1|2|3;9", "k__A|g__B|s__B c,k__Z"),
               mk("1", 2, 1, "increased", "1|2"), mk("1", 2, 2, "decreased", "5"))
    k <- flagged(keptProblems(b), "both_directions")
    expect_equal(k$item, "1")
    expect_match(k$detail, "^1 taxon, 1 species: B c$")
})

test_that("keptProblems finds identical signatures and duplicate taxa", {
    b <- rbind(mk("1", 1, 1, "increased", "1|2;3"), mk("1", 1, 2, "increased", "3;1|2"),
               mk("2", 1, 1, "increased", "1|2;3;1|2", "k__A,k__C,k__A"))
    k <- keptProblems(b)
    expect_equal(flagged(k, "identical_signatures")$detail, "Signatures 1 and 2")
    expect_equal(flagged(k, "duplicate_taxa")$item, "1/1")
    expect_equal(flagged(k, "duplicate_taxa")$detail, "A")
})

test_that("keptProblems finds empty NCBI ID entries anywhere in the list", {
    b <- rbind(mk("1", 1, 1, ids = "1;;2"), mk("1", 1, 2, ids = ";2"),
               mk("1", 1, 3, ids = "2;"), mk("1", 1, 4, ids = "2;3"))
    expect_equal(flagged(keptProblems(b), "empty_ncbi_id")$item, c("1/1", "1/2", "1/3"))
})

test_that("keptProblems tolerates misaligned ID and name lists", {
    b <- rbind(mk("1", 1, 1, "increased", "1|2;7", "k__A"),
               mk("1", 1, 2, "decreased", "1|2", "k__A,k__B"))
    k <- flagged(keptProblems(b), "both_directions")
    expect_equal(nrow(k), 1)
    expect_match(k$detail, "1|2", fixed = TRUE)
})

test_that("keptProblems checks experiments without signatures for group problems", {
    b <- rbind(mk("1", 1, NA, NA, NA, NA, g0 = "same", g1 = "Same "),
               mk("2", 1, NA, NA, NA, NA, n0 = 1))
    k <- keptProblems(b)
    expect_equal(flagged(k, "same_group_names")$Study, "1")
    expect_equal(flagged(k, "group_size_one")$Study, "2")
    expect_equal(nrow(flagged(k, "both_directions")), 0)
})

test_that("keptProblems finds shared DOIs regardless of case, and malformed DOIs", {
    b <- rbind(mk("1", 1, 1, doi = "10.1000/ABC"), mk("2", 1, 1, doi = "10.1000/abc"),
               mk("3", 1, 1, doi = "0.1186/x"), mk("4", 1, 1, doi = NA))
    k <- keptProblems(b)
    expect_equal(sort(flagged(k, "shared_doi")$Study), c("1", "2"))
    expect_equal(flagged(k, "malformed_doi")$Study, "3")
})

test_that("keptProblems handles no signatures and no problems", {
    expect_equal(nrow(keptProblems(mk("1", 1, NA, NA, NA, NA)[0, ])), 0)
    expect_equal(nrow(keptProblems(mk("1", 1, 1))), 0)
})

test_that("release_summary.R counts signatures, experiments and studies", {
    write_dump <- function(df, file) {
        cat("# BugSigDB test\n", file = file)
        readr::write_csv(df, file, append = TRUE, col_names = TRUE)
    }
    new <- rbind(mk("1", 1, 1), mk("1", 1, 2), mk("2", 1, NA))
    new$Description <- "two\nlines"  # line breaks must not count as rows
    old <- mk("1", 1, 1)
    f.new <- tempfile(fileext = ".csv"); f.old <- tempfile(fileext = ".csv")
    f.news <- tempfile()
    write_dump(new, f.new); write_dump(old, f.old)
    writeLines(c("CHANGES IN VERSION v9.9.9", "---"), f.news)
    rscript <- file.path(R.home("bin"), "Rscript")
    out <- system2(rscript, c(file.path(scripts, "release_summary.R"), f.new, f.old, f.news),
                   stdout = TRUE)
    expect_equal(paste(trimws(out), collapse = " "),
                 paste("o SUMMARY: 2 signatures and 1 experiments without signatures",
                       "from 2 studies (v9.9.9: 1, 0 and 1)"))
    out <- system2(rscript, c(file.path(scripts, "release_summary.R"), f.new, "missing.csv"),
                   stdout = TRUE)
    expect_match(paste(out, collapse = " "), "the previous release: 0, 0 and 0", fixed = TRUE)
})

test_that("kept items get a labelled Fixed box, and continued parts a reminder", {
    expect_equal(fixedBoxes(c("[1](u1): 2", "[3](u3): 4")),
                 c("- [1](u1): 2", "  - [ ] Fixed on bugsigdb.org",
                   "- [3](u3): 4", "  - [ ] Fixed on bugsigdb.org"))
    kept <- c("", "### Kept section", "", strrep("x", 50))
    attr(kept, "continued") <- keptContinued()
    dropped <- c("", "### Dropped section", "", strrep("y", 50))
    md <- tempfile(fileext = ".md")
    capture.output(writeReportParts("header", list(dropped, kept, kept, dropped), md, limit = 100))
    parts <- lapply(c(md, paste0(sub("\\.md$", "", md), c("-2.md", "-3.md", "-4.md"))), readLines)
    expect_equal(parts[[1]][3], "### Dropped section")
    expect_equal(parts[[2]][1], keptContinued())
    expect_equal(parts[[3]][1], keptContinued())
    expect_equal(parts[[4]][1], "### Dropped section")
})

test_that("the continued reminder asks to tick a box only where there are boxes", {
    expect_match(keptContinued(TRUE), "Tick **Fixed on bugsigdb.org**", fixed = TRUE)
    expect_no_match(keptContinued(FALSE), "Tick", fixed = TRUE)
    md <- tempfile(fileext = ".md")
    dropped <- c("", "### Dropped section", "", strrep("y", 50))
    capture.output(writeReportParts("header", list(dropped,
        structure(c("", "### No boxes", "", "- [1](u)"), continued = keptContinued(FALSE))),
        md, limit = 100))
    expect_equal(readLines(paste0(sub("\\.md$", "", md), "-2.md"))[1], keptContinued(FALSE))
})

