# 0003. Exceptions to release QC are approved overrides kept in the repo

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** Levi Waldron

## Context and Problem Statement

Some data fails a release check but is right as it is. Study 562's signatures describe body sites rather than contrast two groups, so Abundance in Group 1 is neither increased nor decreased. Fixing such data on bugsigdb.org isn't possible, and loosening the check would let real errors through. Exceptions need a reviewed, recorded approval.

## Decision

1. Each study in the release QC meta-issue (ADR 0002) has, besides the Fixed on bugsigdb.org box, a **Release anyway** box for data to release despite the check.
2. `inst/scripts/scan_qc_issue.R` adds ticked Release anyway boxes to `inst/extdata/release_qc_overrides.tsv`: one row per check and BSDB ID, with a reason and the issue. The pull request that adds them is the approval. Entries with both boxes ticked are skipped.
3. An override covers one check for the listed signatures only. A signature failing several checks needs each approved, and signatures added to the study later are checked as usual.
4. Unreviewed data, retracted studies and studies whose review state is "Incorrect" can't be overridden.
5. The next report lists approved overrides under "Released by override", and overrides that match nothing under "Stale overrides" for removal.

## Alternatives Considered

- **Override a whole study or check.** Rejected: it would release later additions to the study without review.
- **Record exceptions on bugsigdb.org.** Rejected: there's no field for them, and the approval wouldn't be reviewed or versioned with the release code.
- **One box per study meaning "done".** Rejected: curators would tick it for fixes, and the scanner would turn those into overrides.

## Consequences

- Every exception is reviewed in a pull request and dated in git, like corrections in waldronlab/bugphyzzExports ADR 0005.
- Approved overrides carry over from one release's meta-issue to the next.

References: #67, ADR 0001, ADR 0002.
