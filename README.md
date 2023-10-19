Hourly export status: ![hourly export](https://github.com/waldronlab/BugSigDBExports/actions/workflows/export-bugsigdb.yml/badge.svg)

# BugSigDBExports

This repository contains data files exported from
[BugSigDB](https://bugsigdb.org), a manually curated database of published
microbial signatures.

See https://doi.org/10.5281/zenodo.5606165 for all releases.

## Citation

Ludwig Geistlinger, Chloe Mirzayi, Fatima Zohra, Rimsha Azhar,
Shaimaa Elsafoury, Clare Grieve, Jennifer Wokaty, Samuel David Gamboa-Tuz,
Pratyay Sengupta, Isaac Hecht, Aarthi Ravikrishnan, Rafael Goncalves,
Eric Franzosa, Karthik Raman, Vincent Carey, Jennifer B. Dowd,
Heidi E. Jones, Sean Davis, Nicola Segata, Curtis Huttenhower, Levi Waldron (2023)
BugSigDB captures patterns of differential abundance across a broad range of host-associated microbial signatures. 
*Nature Biotechnology*, doi: [10.1038/s41587-023-01872-y](https://doi.org/10.1038/s41587-023-01872-y).

## What does BugSigDBExports do?

At the core of the repo is the 
[dump_release.R](https://github.com/waldronlab/BugSigDBExports/blob/main/inst/scripts/dump_release.R) 
script which

1. obtains and merges the exported study, experiment, and signature tables from https://bugsigdb.org/Help:Export,
2. filters incomplete records,
3. adds signature IDs,
4. writes the full dump to csv, and
5. writes GMT files of signatures for all combinations of ID type and taxonomic level.

This script is invoked automatically every hour via a cron job.

# bugsigdb-related links

* [bugsigdb.org](https://bugsigdb.org): A Comprehensive Database of Published Microbial Signatures
* [BugSigDB issue tracker](https://github.com/waldronlab/BugSigDB/issues): Report bugs or feature requests for bugsigdb.org
* [BugSigDBExports](https://github.com/waldronlab/BugSigDBExports): Hourly data exports of bugsigdb.org
* [Stable data releases](https://zenodo.org/records/6468009): Periodic manually-reviewed stable data releses on Zenodo
* [bugsigdbr](https://bioconductor.org/packages/bugsigdbr/): R/Bioconductor access to published microbial signatures from BugSigDB
* [Curation issues](https://github.com/waldronlab/BugSigDBcuration/issues): Report curation issues, requests studies to be added
* [bugSigSimple](https://github.com/waldronlab/bugSigSimple): Simple analyses of BugSigDB data in R
* [BugSigDBStats](https://github.com/waldronlab/BugSigDBStats): Statistics and trends of BugSigDB
* [BugSigDBPaper](https://github.com/waldronlab/BugSigDBPaper): Reproduces analyses of the [Nature Biotechnology publication](https://www.nature.com/articles/s41587-023-01872-y)
* [community-bioc Slack Team](https://slack.bioconductor.org/): Join #bugsigdb channel

