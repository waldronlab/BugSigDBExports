# Release Process

This document describes how to create a new release of BugSigDBExports.

## Overview

BugSigDBExports has two long-lived branches:

- **`devel`** — unfiltered files, updated hourly by a GitHub Action workflow
- **`release`** — quailty-control-filtered files, updated only on release

Each release is also tagged (e.g. `v1.3.2`) for permanent, citable access.
Tags point to a specific commit on `release` and never change.

## Prerequisites

Before making a release:

- Confirm you have write access to the repository
- Decide on a version tag in the format `vMAJOR.MINOR.PATCH` (e.g. `v1.3.2`)
- Prepare any additional NEWS content you want to include beyond the
  automatically generated row counts (optional)

## Quality Control

QC filtering is applied automatically when creating a release. Filters are
defined in `inst/scripts/dump_release.R` and remove incomplete signatures.

Row count reductions between releases are expected and intentional when
QC filters remove invalid signatures.

Experiments without signatures, which record a negative result or only
alpha diversity, are released when their study's Review state is
"Reviewed". They appear in `full_dump.csv` with empty signature columns,
and not in the GMT files.

DOIs are normalized before the checks, so `doi: 10.1186/...` and
`https://doi.org/10.1186/...` both become `10.1186/...`.

### Release QC report

With validation on, `dump_release.R` writes `release_qc/dropped.md` and
`release_qc/dropped.csv`, listing every row that release QC removed and
why. The checks, overrides and report are in `inst/scripts/release_qc.R`.
Both runs of the workflow upload the report as an artifact
(`release-qc-dryrun` or `release-qc-release`), and the dry run also shows
it in its run summary.

Check `dropped.md` by hand before posting it as a meta-issue on
[BugSigDBcuration](https://github.com/waldronlab/BugSigDBcuration/issues),
and link existing or new curation issues next to the studies they cover.
Post the report from the commit run, since that run downloads the data
again and its list can differ from the dry run's. GitHub limits an issue
to 65,536 characters, so a long report is split into `dropped-2.md`,
`dropped-3.md`, ...; post those as comments, in order. Close the previous
release's meta-issue when posting the new one.

The report ends with a "Kept, needs fixing" part, also in
`release_qc/kept.csv`: problems in released data that don't justify
dropping it, such as a taxon in both the increased and decreased signature
of an experiment, identical signatures, a taxon listed twice, equal group
names, groups of size 1, and missing or shared DOIs. Each study has a Fixed
on bugsigdb.org box only. It also lists Complete studies missing from every
export because their page name contains `/`, which the BugSigDB CSV export
splits on.

Tests for the checks, the report helpers and the NEWS SUMMARY are in
`inst/tests`; run them with `Rscript -e 'testthat::test_dir("inst/tests")'`.
The release workflow runs them before exporting.

### Overrides

Each study in the meta-issue has two boxes. Curators tick **Fixed on
bugsigdb.org** after correcting a study; the fix shows up in the next export
and the study drops out of the next report. **Release anyway** is for data
that fails a check but is right as it is, e.g. Study 562, whose signatures
describe body sites rather than contrast two groups, so Abundance in Group 1
is neither increased nor decreased. To approve such an exception:

1. Tick its Release anyway box in the meta-issue.
2. Run `Rscript inst/scripts/scan_qc_issue.R <issue URL>` (needs the gh
   CLI). It adds the ticked signatures to
   `inst/extdata/release_qc_overrides.tsv`, one row per check and BSDB ID.
   It skips entries with both boxes ticked, and lists overrides whose boxes
   were unticked.
3. Fill in the `reason` column and merge the change as a pull request.

An override covers one check for the listed signatures only, so a
signature failing several checks needs each of them approved, and new
signatures in the same study are checked as usual. The unreviewed check
can't be overridden, nor can retracted studies or studies whose review
state is Incorrect. The next report
lists approved overrides, ticked, under "Released by override", and
overrides that match nothing under "Stale overrides", for removal.

## Two-Step Release Process

### Step 1 — Dry Run (inspect before committing)

1. Go to **Actions** → **Release BugSigDB** → **Run workflow**
2. Set the following inputs:
   - `dryrun`: `true`
   - `version`: your version tag e.g. `v1.3.2`
   - `news`: optional additional NEWS content in Bioconductor plain text
     format. The web form takes a single line, so for multi-line content
     use the gh CLI from a file:
     `gh workflow run release-bugsigdb.yml -f dryrun=true -f version=v1.3.2 -f news="$(cat news.txt)"`
3. Wait for the workflow to complete
4. Download the artifact from the Actions run page (available for 90 days)
5. Inspect the files:
   - Check that `full_dump.csv` and the GMT files look correct
   - Check the SUMMARY and row counts in `NEWS`, and any notes you provided
   - Verify row count changes are as expected
6. Review the run summary posted at the bottom of the Actions run page

If the data does not look correct, do not proceed to step 2. Investigate
the issue on `devel` and repeat step 1 when ready.

### Step 2 — Commit

1. Go to **Actions** → **Release BugSigDB** → **Run workflow**
2. Set the following inputs:
   - `dryrun`: `false`
   - `version`: the same tag as step 1
   - `news`: the same content as step 1
3. Wait for the workflow to complete
4. The workflow will automatically:
   - Export and QC-filter data from `devel`
   - Count row differences vs the previous release
   - Write the NEWS entry with row counts and your notes
   - Commit filtered files and NEWS to the `release` branch
   - Create and push the version tag
   - Create the GitHub release
   - Publish the release on Zenodo (the **Upload BugSigDB release to Zenodo**
     workflow, below)

## Finalizing the Release

After the workflow completes:

### GitHub Release

1. Go to **Releases**
2. Confirm the release was published with NEWS, version and appropriate tag

### Zenodo

The commit run ends by calling **Upload BugSigDB release to Zenodo**
(`.github/workflows/zenodo-bugsigdb.yml`, `inst/scripts/zenodo_release.py`).
It publishes a new version of the BugSigDB record,
[10.5281/zenodo.19740649](https://doi.org/10.5281/zenodo.19740649), with
`README.md`, `full_dump.csv` and the 15 GMT files from the release tag as
individual files. Title, creators, keywords and license come from
`.zenodo.json` on the tag; the description is the release's NEWS entry.
Before publishing, it checks that the new version has exactly these files,
with matching MD5 checksums.

`bugsigdbr::importBugSigDB()` downloads `full_dump.csv` from the record, so
it can't use the zip of the repository that the Zenodo GitHub integration
archives. The integration is turned off for this repository; the workflow
replaces it. Releases up to v1.3.1 were uploaded by hand under
[10.5281/zenodo.5606165](https://doi.org/10.5281/zenodo.5606165); v1.4.0
(10.5281/zenodo.24379934) was archived by the integration, and its files
were added afterwards.

It needs the `ZENODO_TOKEN` repository secret: a Zenodo personal access token
with the `deposit:write` and `deposit:actions` scopes, from the account that
owns the record.

To retry, or to upload a tag released without it, run the workflow by hand
with the tag. With `publish` set to `false` it leaves a draft to check on
Zenodo, which the next run reuses; a version already on Zenodo with
`full_dump.csv` is not uploaded again. To see what would be uploaded without
a token:
`python3 inst/scripts/zenodo_release.py --version vX.Y.Z --dir <checkout of the tag> --plan`.

After publishing:

1. Open the DOI in the workflow summary and check the files and metadata
2. Use the DOI as the `importBugSigDB()` default in bugsigdbr

## NEWS File Format

The NEWS file follows Bioconductor plain text format. The workflow
automatically prepends a new entry on each release:

```
CHANGES IN VERSION v1.3.2
------------------------

NEW DATA

    o SUMMARY: 7,433 signatures and 0 experiments without signatures
      from 1,250 studies (v1.3.1: 7,425, 0 and 1,246)
    o bugsigdb_signatures_genus_metaphlan.gmt: 5298 rows (+15)
    ...

OPTIONAL USER-PROVIDED SECTION

    o Additional notes here
```

The SUMMARY is computed by `inst/scripts/release_summary.R` from
`full_dump.csv`, whose line count would include line breaks inside
Description fields. GMT row counts, one signature per row, show `+N` for
additions and `-N` for removals relative to the previous release. Counts
exclude the header row.
