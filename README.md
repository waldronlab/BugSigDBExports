Hourly export status: ![hourly export](https://github.com/waldronlab/BugSigDBExports/actions/workflows/export-bugsigdb.yml/badge.svg)

# BugSigDBExports

This repository contains data files exported from
[BugSigDB](https://bugsigdb.org), a manually curated database of published
microbial signatures.

See https://doi.org/10.5281/zenodo.5606165 for all releases.

## Citation

Ludwig Geistlinger, Chloe Mirzayi, Fatima Zohra, Rimsha Azhar,
Shaimaa Elsafoury, Claire Grieve, Jennifer Wokaty, Samuel David Gamboa-Tuz,
Pratyay Sengupta, Isaac Hecht, Aarthi Ravikrishnan, Rafael Goncalves,
Eric Franzosa, Karthik Raman, Vincent Carey, Jennifer B. Dowd,
Heidi E. Jones, Sean Davis, Nicola Segata, Curtis Huttenhower, Levi Waldron (2022)
BugSigDB: accelerating microbiome research through systematic comparison to published
microbial signatures. medRxiv, doi:
[10.1101/2022.10.24.22281483](https://doi.org/10.1101/2022.10.24.22281483).

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
