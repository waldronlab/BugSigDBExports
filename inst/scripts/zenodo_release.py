#!/usr/bin/env python3
"""Publish a BugSigDB release on Zenodo as a new version of the BugSigDB
record (concept 10.5281/zenodo.5606165), with full_dump.csv, the GMT files
and README.md as individual files, which bugsigdbr::importBugSigDB() reads.

The Zenodo GitHub integration archives only a zip of the repository, which
importBugSigDB() can't read (#31, #69).

Usage:
  ZENODO_TOKEN=... python3 zenodo_release.py --version v1.4.0 --dir <release checkout> [--publish]
  python3 zenodo_release.py --version v1.4.0 --dir <release checkout> --plan   # no token, no changes

Without --publish, the new version is left as a draft to check on Zenodo;
running again reuses the draft. The token (ZENODO_TOKEN, or ZENODO_PAT)
needs the deposit:write and deposit:actions scopes, from an account that can
edit the BugSigDB record. Before publishing, the script checks that the
draft has exactly the release files, with matching MD5 checksums.
Uses only the Python standard library.
"""

import argparse
import datetime
import glob
import hashlib
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request

CONCEPT = "5606165"
INTRO = ('<p>This repository contains data files exported from&nbsp;'
         '<a href="https://bugsigdb.org/">BugSigDB</a>, a manually curated '
         'database of published microbial signatures.</p>')


def request(method, url, token=None, data=None, content_type="application/json"):
    headers = {"Accept": "application/json", "User-Agent": "BugSigDBExports release workflow"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if data is not None:
        headers["Content-Type"] = content_type
        if content_type == "application/json":
            data = json.dumps(data).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url} failed: HTTP {e.code}\n{e.read().decode(errors='replace')[:2000]}")
    except (urllib.error.URLError, TimeoutError) as e:
        sys.exit(f"{method} {url} failed: {e}")
    return json.loads(body) if body else {}


def release_files(directory):
    files = ["README.md", "full_dump.csv"] + sorted(
        os.path.basename(f) for f in glob.glob(os.path.join(directory, "bugsigdb_signatures_*.gmt")))
    missing = [f for f in files if not os.path.isfile(os.path.join(directory, f))]
    if missing:
        sys.exit("Missing release files: " + ", ".join(missing))
    if len(files) != 17:
        sys.exit(f"Expected README.md, full_dump.csv and 15 GMT files, found {len(files)}")
    with open(os.path.join(directory, "full_dump.csv"), encoding="utf-8") as f:
        if not f.readline().startswith("# BugSigDB "):
            sys.exit("full_dump.csv doesn't start with the '# BugSigDB' header line")
    return files


def news_entry(directory, version):
    path = os.path.join(directory, "NEWS")
    if not os.path.isfile(path):
        return ""
    entry, inside = [], False
    for line in open(path, encoding="utf-8"):
        if line.startswith("CHANGES IN VERSION "):
            if inside:
                break
            inside = line.strip() == f"CHANGES IN VERSION {version}"
            continue
        if inside and not (line.strip() and set(line.strip()) <= {"-"}):
            entry.append(line.rstrip("\n"))
    if not entry:
        sys.exit(f"No 'CHANGES IN VERSION {version}' entry in NEWS")
    return "\n".join(entry).strip("\n")


def metadata(base, version, news, repo):
    """Metadata of the new version: the previous version's (as carried over to
    the draft), with the release-specific fields replaced."""
    md = {k: v for k, v in base.items() if k not in ("doi", "prereserve_doi", "version", "publication_date")}
    description = INTRO + f"\n<p>Release {version}</p>"
    if news:
        description += "\n<pre>" + html.escape(news) + "</pre>"
    tree = f"https://github.com/{repo}/tree/"
    related = [r for r in md.get("related_identifiers", []) if not r.get("identifier", "").startswith(tree)]
    related.append({"identifier": tree + version, "relation": "isSupplementTo", "scheme": "url"})
    md.update({
        "title": f"waldronlab/BugSigDBExports: Release {version}",
        "description": description,
        "version": version,
        "publication_date": datetime.date.today().isoformat(),
        "related_identifiers": related,
    })
    md.setdefault("upload_type", "dataset")
    md.setdefault("access_right", "open")
    md.setdefault("license", "cc-by-4.0")
    return md


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def file_names(record):
    files = record.get("files", [])
    if isinstance(files, dict):  # records API: {"entries": {...}} or a count
        files = list(files.get("entries", {}).values())
    return {f.get("key") or f.get("filename") for f in files}


def summary(text):
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(text + "\n")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", required=True, help="release tag, e.g. v1.4.0")
    p.add_argument("--dir", required=True, help="checkout of the release tag")
    p.add_argument("--concept", default=CONCEPT, help="Zenodo concept record ID")
    p.add_argument("--base", default="https://zenodo.org", help="e.g. https://sandbox.zenodo.org")
    p.add_argument("--repo", default="waldronlab/BugSigDBExports")
    p.add_argument("--publish", action="store_true", help="publish; otherwise leave a draft")
    p.add_argument("--plan", action="store_true", help="only show what would be uploaded")
    a = p.parse_args()
    api = a.base.rstrip("/") + "/api"

    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", a.version):
        sys.exit(f"Version must look like v1.4.0, not {a.version}")
    files = release_files(a.dir)
    checksums = {name: md5(os.path.join(a.dir, name)) for name in files}
    news = news_entry(a.dir, a.version)

    # the latest published version; the new version starts from its metadata.
    # size=25 is the most an anonymous request may list: enough to find a
    # recent release.
    latest = request("GET", f"{api}/records/{a.concept}/versions/latest")
    versions = request("GET", f"{api}/records/{latest['id']}/versions?size=25&sort=newest")
    published_ids = {str(h["id"]) for h in versions["hits"]["hits"]}
    for h in versions["hits"]["hits"]:
        if h["metadata"].get("version") == a.version:
            if "full_dump.csv" not in file_names(h):
                sys.exit(f"{a.version} is on Zenodo (https://doi.org/{h['doi']}) without "
                         "full_dump.csv as a separate file, so importBugSigDB() can't read it")
            summary(f"{a.version} is already on Zenodo: https://doi.org/{h['doi']}")
            return
    print(f"Latest version: {latest['metadata'].get('version')} ({latest['doi']})")
    print(f"New version {a.version} with {len(files)} files: {', '.join(files)}")

    if a.plan:
        print(json.dumps(metadata(latest["metadata"], a.version, news, a.repo), indent=1))
        return
    token = os.environ.get("ZENODO_TOKEN") or os.environ.get("ZENODO_PAT")
    if not token:
        sys.exit("Set ZENODO_TOKEN")

    def is_new_draft(d):
        return d.get("submitted") is False and str(d["id"]) not in published_ids

    # reuse an unpublished new-version draft of this record from an earlier
    # run; never an edit draft of a published version
    drafts = request("GET", f"{api}/deposit/depositions?status=draft&size=100", token)
    drafts = [d for d in drafts if str(d.get("conceptrecid")) == a.concept and is_new_draft(d)]
    if len(drafts) > 1:
        sys.exit("More than one unpublished draft of the BugSigDB record: "
                 + ", ".join(d["links"]["html"] for d in drafts) + "; discard all but one")
    if drafts:
        draft = request("GET", drafts[0]["links"]["self"], token)
        old = draft["metadata"].get("version")
        if old and old != a.version:
            sys.exit(f"Draft {draft['links']['html']} is for {old}, not {a.version}; publish or discard it")
        print(f"Reusing draft {draft['id']}")
    else:
        r = request("POST", f"{api}/deposit/depositions/{latest['id']}/actions/newversion", token)
        draft = request("GET", r["links"].get("latest_draft", r["links"]["self"]), token)
        print(f"Created draft {draft['id']}")
    if not is_new_draft(draft):
        sys.exit(f"Deposition {draft['id']} is not an unpublished new version; stopping")

    # replace the files carried over from the previous version
    for f in draft.get("files", []):
        request("DELETE", f["links"]["self"], token)
    bucket = draft["links"]["bucket"]
    for name in files:
        with open(os.path.join(a.dir, name), "rb") as f:
            request("PUT", f"{bucket}/{name}", token, f.read(), "application/octet-stream")
        print(f"Uploaded {name}")
    draft = request("PUT", draft["links"]["self"], token,
                    {"metadata": metadata(draft["metadata"], a.version, news, a.repo)})

    # the draft must have exactly the release files, with matching checksums
    uploaded = {f["filename"]: f["checksum"].split(":")[-1]
                for f in request("GET", draft["links"]["files"], token)}
    if uploaded != checksums:
        sys.exit("Files in the draft don't match the release: "
                 f"missing {sorted(set(checksums) - set(uploaded))}, "
                 f"extra {sorted(set(uploaded) - set(checksums))}, "
                 f"different {sorted(k for k in checksums if k in uploaded and uploaded[k] != checksums[k])}")
    print(f"Checked {len(uploaded)} files in the draft")

    if not a.publish:
        summary(f"Zenodo draft for {a.version}, not published: {draft['links']['html']}")
        return
    pub = request("POST", draft["links"]["publish"], token)
    summary(f"Published {a.version} on Zenodo: https://doi.org/{pub['doi']}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"doi={pub['doi']}\n")


if __name__ == "__main__":
    main()
