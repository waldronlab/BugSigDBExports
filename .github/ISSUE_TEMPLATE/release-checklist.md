---
name: Release checklist
about: Track a BugSigDB data release and the bugsigdbr update for a Bioconductor release
title: "Bioconductor 3.XX release checklist (DD Month YYYY)"
labels: []
assignees: []
---

<!--
Replace the placeholders (3.XX, dates, vX.Y.Z, DOIs, counts) and delete
steps that don't apply. Release-specific findings and decisions go in the
summary below; see RELEASE_PROCESS.md for how each step works.
-->

Tracking issue for the BugSigDB data release that ships with Bioconductor 3.XX, following #<previous checklist issue>. Dates from the [release schedule](https://bioconductor.org/developers/release-schedule/): release candidate <date>, deadline for packages passing build and check <date>, last commit and NEWS <date>, release <date>.

The last release is vX.Y.Z ([<DOI>](https://doi.org/<DOI>)): <S0> signatures from <T0> studies, the `importBugSigDB()` default in bugsigdbr <version>.

<!-- Summarize what changed since then: new or renamed columns in the BugSigDB export, changes to release QC, and decisions for this release. -->

There are two NEWS files: `NEWS` on the `release` branch of this repo, written by the Release BugSigDB workflow from its `news` input, and `NEWS.md` in bugsigdbr. Signature and study counts:

```r
# rows without a signature are experiments recording a negative taxonomic result and alpha diversity
counts <- function(bsdb)
    c(signatures = sum(!is.na(bsdb$`Signature page name`)),
      studies = length(unique(bsdb$Study)))

## Previous release
counts(bugsigdbr::importBugSigDB(version = "<previous DOI>", cache = FALSE))

## New release, once the DOI exists
counts(bugsigdbr::importBugSigDB(version = "<new DOI>", cache = FALSE))
```

### BugSigDBExports, before the dry run

- [ ] Check waldronlab/BugSigDB issues closed since the last release for changes to the export: new or renamed columns, taxonomy, QC flags
- [ ] Decide which open issues in this repo and waldronlab/bugsigdbr are in this release, and list the rest under "Not in this release"
- [ ] Merge any changes to release QC (`inst/scripts/release_qc.R`)
- [ ] Add approved exceptions from the previous release's QC meta-issue: `Rscript inst/scripts/scan_qc_issue.R <issue URL>`, fill in the reasons, and merge the overrides PR
- [ ] Confirm `.zenodo.json` creators on `release` are current

### BugSigDBExports, release

- [ ] Dry run of **Release BugSigDB** as vX.Y.Z; check `NEWS` in the artifact and read `release_qc/dropped.md`
- [ ] Commit run with the same tag. Pass new fields, QC changes and anything else users should know in the `news` input, in Bioconductor NEWS format
- [ ] GitHub release and tag checked; Zenodo record published and its metadata checked
- [ ] `importBugSigDB(version = "<new DOI>")` works and returns any new columns
- [ ] Check the commit run's `dropped.md` by hand and post it as a meta-issue on waldronlab/BugSigDBcuration (`dropped-2.md` and on as comments), linking existing and new curation issues next to the studies they cover

### bugsigdbr, after the DOI exists, pushed by the day before the build and check deadline

- [ ] New DOI as the `importBugSigDB()` default; add vX.Y.Z to the release list in the roxygen and regenerate `man/`
- [ ] Document new columns in `importBugSigDB()`
- [ ] R CMD check against the new release
- [ ] Version bump in `DESCRIPTION` (devel stays odd, e.g. 1.19.1), and a `NEWS.md` entry headed with the upcoming release version (even, e.g. 1.20.0); check it parses with `utils::news()` so it reaches the release announcement:

  ```
  ## Changes in version <release version, e.g. 1.20.0>

  * `importBugSigDB()` defaults to BugSigDB release vX.Y.Z
    (<new DOI>): <S> signatures from <T> studies, up from <S0>
    signatures from <T0> studies in the previous release.
  ```
- [ ] Push to git.bioconductor.org; check the next build report
- [ ] Close #<previous checklist issue>

Not in this release: <issues>. Close this issue when 3.XX ships.
