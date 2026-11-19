# 0002. Each release's QC report is posted as a curation issue

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** Levi Waldron

## Context and Problem Statement

Release QC (ADR 0001) drops data with fixable problems: missing fields, malformed identifiers, taxa that didn't resolve to an NCBI ID. Previously the dropped data wasn't reported anywhere, so curators couldn't fix it and it stayed out of every release. The release workflow now writes `release_qc/dropped.md`, which lists every dropped row by check and study, but a workflow artifact expires after 90 days and isn't where curators work.

## Decision

1. For each release, the `dropped.md` from the commit run of **Release BugSigDB** is checked by hand and posted as a meta-issue on waldronlab/BugSigDBcuration. `dropped-2.md` and later parts, written when the report exceeds GitHub's issue size limit, are posted as comments in order. The commit run's report is used, not the dry run's, because each run downloads the data again.
2. Curators link existing and new curation issues next to the studies they cover.
3. Each study has a **Fixed on bugsigdb.org** box for curators to tick after correcting it. A fix that worked takes the data out of the next report, so the next export confirms it.
4. The previous release's meta-issue is closed when the next one is posted. Studies that are still listed reappear, unticked, in the new issue.

## Alternatives Considered

- **Attach the report to the GitHub release or the Zenodo record.** Rejected: curators don't work there, and there's no way to record fixes.
- **One curation issue per problem.** Rejected: today's report covers hundreds of studies.
- **Leave the report as a workflow artifact.** Rejected: it expires, and nobody would follow up.

## Consequences

- Every release produces one open list of what curators can fix to get data into the next release.
- The meta-issue also carries the boxes for approving exceptions (ADR 0003).

References: #67, ADR 0001, ADR 0003.
