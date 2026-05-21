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

## Two-Step Release Process

### Step 1 — Dry Run (inspect before committing)

1. Go to **Actions** → **Release BugSigDB** → **Run workflow**
2. Set the following inputs:
   - `dryrun`: `true`
   - `version`: your version tag e.g. `v1.3.2`
   - `news`: optional additional NEWS content in Bioconductor plain text
     format e.g. `NEW FEATURES\n\n    o Added new filter`
3. Wait for the workflow to complete
4. Download the artifact from the Actions run page (available for 90 days)
5. Inspect the files:
   - Check that `full_dump.csv` and the GMT files look correct
   - Check that `NEWS` has the correct row counts and any notes you provided
   - Verify row count changes are as expected
6. Review the run summary posted at the bottom of the Actions run page

If the data does not look correct, do not proceed to step 2. Investigate
the issue on `devel` and repeat step 1 when ready.

### Step 2 — Commit

1. Go to **Actions** → **Export BugSigDB** → **Run workflow**
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
   - Create the release, which should automatically create the Zenodo entry

## Finalizing the Release

After the workflow completes:

### GitHub Release

1. Go to **Releases**
2. Confirm the release was published with NEWS, version and appropriate tag

### Zenodo

1. Go to [zenodo.org](https://zenodo.org) and find the new record
2. Verify the metadata (authors, description, keywords) is accurate
3. Edit if necessary and save

## NEWS File Format

The NEWS file follows Bioconductor plain text format. The workflow
automatically prepends a new entry on each release:

```
CHANGES IN VERSION v1.3.2
------------------------

NEW DATA

    o full_dump.csv: 8421 rows (+8)
    o bugsigdb_signatures_genus_metaphlan.gmt: 5298 rows (+15)
    ...

OPTIONAL USER-PROVIDED SECTION

    o Additional notes here
```

Row counts show `+N` for additions and `-N` for removals relative to the
previous release. Counts exclude the header row.
