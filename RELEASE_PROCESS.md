# Release Process

How to make a BugSigDB data release. Track each release in an issue from the
**Release checklist** template,
[`.github/ISSUE_TEMPLATE/release-checklist.md`](.github/ISSUE_TEMPLATE/release-checklist.md)
(**Issues** → **New issue** → **Release checklist**), which also covers the
bugsigdbr update.

## How it works

- **`devel`** has the code and the unfiltered export, updated hourly.
- **`release`** has the quality-controlled files, one commit per release,
  tagged `vX.Y.Z`. The release workflow commits to it, so don't delete it.

A release runs on GitHub Actions: it downloads the current export from
bugsigdb.org, drops data that fails release QC, writes the files and `NEWS`,
and on the commit run tags the release and publishes it on GitHub and on
Zenodo, as a new version of
[10.5281/zenodo.19740649](https://doi.org/10.5281/zenodo.19740649). Locally,
you review its output, approve exceptions to QC, and post the QC report for
curators.

| File | Role |
|---|---|
| `.github/workflows/release-bugsigdb.yml` (**Release BugSigDB**) | Dry run: builds the release and uploads it as artifacts. Commit run: commits it to `release`, tags it, creates the GitHub release, and calls the Zenodo workflow |
| `inst/scripts/dump_release.R` | Downloads the export and writes `full_dump.csv` and the GMT files |
| `inst/scripts/release_qc.R` | Release QC checks, and the report of dropped data (`release_qc/dropped.md`) |
| `inst/extdata/release_qc_overrides.tsv` | Approved exceptions to release QC |
| `inst/scripts/scan_qc_issue.R` | Run locally: adds the ticked "Release anyway" boxes of a QC report issue to the overrides |
| `inst/scripts/release_summary.R` | The SUMMARY line in `NEWS` |
| `.github/workflows/zenodo-bugsigdb.yml`, `inst/scripts/zenodo_release.py` | **Upload BugSigDB release to Zenodo**: publishes the release files on Zenodo |
| `inst/tests/` | Tests, run by the release workflow before it exports and by the Zenodo workflow before it uploads |
| `docs/adr/` | Why release QC works as it does |

## Before you start

- You need write access to the repository, and the `ZENODO_TOKEN` repository
  secret must be set: a Zenodo token with the `deposit:write` and
  `deposit:actions` scopes, from the account that owns the Zenodo record.
- Add the overrides approved in the previous release's QC report issue:
  `Rscript inst/scripts/scan_qc_issue.R <issue URL>`, fill in the `reason`
  column, and merge the change as a pull request.
- Write the release notes for `NEWS` in a file, e.g. `news.txt`, in
  Bioconductor NEWS format (see [NEWS](#news)).

## Steps

1. **Dry run.**

   ```sh
   gh workflow run release-bugsigdb.yml -f dryrun=true -f version=vX.Y.Z -f news="$(cat news.txt)"
   ```

   Or use **Actions** → **Release BugSigDB** → **Run workflow**, where `\n`
   in `news` starts a new line.

2. **Check the dry run.** Its artifacts are `candidate`, with the files and
   `NEWS`, and `release-qc-dryrun`, with `dropped.md`, which the run summary
   also shows. Check the SUMMARY in `NEWS` and read `dropped.md`. For data
   that is right as it is but fails a check, add an override to
   `release_qc_overrides.tsv` by pull request and repeat the dry run.
   Unreviewed signatures, retracted studies and studies whose Review state
   is Incorrect can't be overridden; fix those on bugsigdb.org.

3. **Commit run.** The same command with `-f dryrun=false`. It downloads the
   export again, so it can include curation done since the dry run. If the
   export hasn't changed since the last release, it releases nothing.

4. **Check the release.** The GitHub release has the `NEWS` entry, and the
   Zenodo DOI is in the summary of the **Upload BugSigDB release to Zenodo**
   job, with `full_dump.csv` and the GMT files as separate files. If that
   job failed, run the workflow by hand with the tag; `publish=false` leaves
   a draft to check first.

5. **Post the QC report.** Post `dropped.md` from the commit run's
   `release-qc-release` artifact as an issue on
   [BugSigDBcuration](https://github.com/waldronlab/BugSigDBcuration/issues),
   and `dropped-2.md`, `dropped-3.md`, ... as comments, in order. Link open
   curation issues next to the studies they cover, and close the previous
   release's QC report issue.

6. **Update bugsigdbr** to use the new DOI, as listed in the release
   checklist.

## NEWS

The workflow adds an entry to `NEWS` on `release`, with a SUMMARY and the
GMT row counts, followed by the `news` input:

```
CHANGES IN VERSION vX.Y.Z
------------------------

NEW DATA

    o SUMMARY: 11,939 signatures and 147 experiments without signatures
      from 1,847 studies (v1.3.1: 7,425, 0 and 1,246)
    o bugsigdb_signatures_genus_metaphlan.gmt: 8444 rows (+3161)
    ...

QUALITY CONTROL

    o Release notes from the news input
```
