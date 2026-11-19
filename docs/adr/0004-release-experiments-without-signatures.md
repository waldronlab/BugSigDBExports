# 0004. Experiments without signatures are released when their study is reviewed

- **Status:** Proposed
- **Date:** 2026-11-12
- **Deciders:** Levi Waldron

## Context and Problem Statement

An experiment with no signatures can record a negative taxonomic result, with differential alpha diversity recorded in the experiment itself. Releases dropped all such experiments, 406 in the 12 November 2026 export, as if they were incomplete curation. None of them had a signature page in progress, and 185 record alpha diversity. The export has no review field for experiments: `Reviewer` is per signature, and `Review state` is per study.

## Decision

1. An experiment without signatures is released when its study's `Review state` is "Reviewed".
2. Otherwise it is dropped as unreviewed, which can't be overridden (ADR 0003).
3. The other release checks that apply to experiments and studies still apply (ADR 0001).
4. These experiments appear in `full_dump.csv` with empty signature columns, and not in the GMT files.

## Alternatives Considered

- **Release them only if they record alpha diversity.** Rejected: a negative taxonomic result is worth releasing on its own.
- **Approve them one by one with Release anyway.** Rejected: it would put about 150 routine approvals in the overrides file.
- **Keep dropping them.** Rejected: it loses negative results.

## Consequences

- `full_dump.csv` rows no longer all have a signature. Counts of signatures should count rows with a `Signature page name`; `bugsigdbr::getSignatures()` already skips the other rows.
- Experiments in unreviewed studies wait for the study's review.

References: #67, ADR 0001, ADR 0003.
