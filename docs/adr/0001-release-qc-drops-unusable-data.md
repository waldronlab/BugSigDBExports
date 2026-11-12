# 0001. Release QC drops data that can't be used or trusted; other quality problems stay as columns

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** Levi Waldron

## Context and Problem Statement

The hourly devel export is unfiltered. Stable releases, the default for `bugsigdbr::importBugSigDB()`, are filtered by the checks in `inst/scripts/release_qc.R`. BugSigDB now exports study-level `Review state` and `Quality control tag` columns (waldronlab/BugSigDB#302, waldronlab/BugSigDB#335), which the release filter ignored, so a release would have included a retracted study. The filter also dropped every study whose DOI was written as a `https://doi.org/...` URL, 415 studies in the 12 November 2026 export, for formatting alone.

## Decision

1. Devel exports stay unfiltered.
2. Releases drop:
   - retracted studies (`Quality control tag` contains "Retracted paper");
   - studies whose `Review state` is "Incorrect";
   - studies with neither a valid PMID nor a valid DOI;
   - unreviewed data: signatures without a Reviewer, and experiments without signatures whose study isn't reviewed (ADR 0003);
   - signatures with no taxa resolved to an NCBI Taxonomy ID;
   - rows failing the existing completeness and format checks.
3. Other QC tags, such as "Contamination issues suspected" and "Results are suspect", don't drop data. They stay as columns for users to filter.
4. DOIs are normalized to the `10.xxxx/...` form in the release, not rejected for their format.
5. Every dropped row is listed in the release QC report, `release_qc/dropped.md` and `dropped.csv`, with the checks it failed.

## Alternatives Considered

- **Drop every row with any QC tag.** Rejected: suspect results are still results, and users can judge them from the tag.
- **Keep dropping URL-form DOIs.** Rejected: the DOI is valid, and the study was lost for its format.
- **Release signatures whose taxa didn't resolve, with their names.** Rejected: the export leaves out unresolved names, so such signatures have no usable taxa. Most can be fixed by a curator finding the right NCBI taxon.

## Consequences

- A release can't include a retracted or incorrect study, and a change to bugsigdb.org's export columns stops the release with a clear message.
- The release QC report is the curators' list of what to fix (ADR 0002).
- Released DOIs can differ in format from those on bugsigdb.org.

References: #47, #59, #67, waldronlab/BugSigDB#302, waldronlab/BugSigDB#335.
