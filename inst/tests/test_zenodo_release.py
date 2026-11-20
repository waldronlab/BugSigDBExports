"""Tests for inst/scripts/zenodo_release.py that don't call Zenodo.
Run from the repository root: python3 -m unittest discover -s inst/tests -p 'test_*.py'
"""

import hashlib
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "zenodo_release", os.path.join(HERE, "..", "scripts", "zenodo_release.py"))
zr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(zr)

NEWS = """CHANGES IN VERSION v1.5.0
------------------------

NEW DATA

    o SUMMARY: 2 signatures

QUALITY CONTROL

    o Removed studies tagged "Retracted paper"

CHANGES IN VERSION v1.4.0
------------------------

NEW DATA

    o SUMMARY: 1 signature
"""

GMTS = [f"bugsigdb_signatures_{lvl}_{ids}{ex}.gmt"
        for lvl in ("genus", "species") for ids in ("metaphlan", "ncbi", "taxname")
        for ex in ("", "_exact")] + \
       [f"bugsigdb_signatures_mixed_{ids}.gmt" for ids in ("metaphlan", "ncbi", "taxname")]


def release_dir(header="# BugSigDB 2026-11-19, License: CC BY 4.0\n", gmts=GMTS):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "full_dump.csv"), "w") as f:
        f.write(header + "Study,Experiment\n")
    for name in ["README.md"] + gmts:
        with open(os.path.join(d, name), "w") as f:
            f.write(name)
    with open(os.path.join(d, "NEWS"), "w") as f:
        f.write(NEWS)
    return d


class ReleaseFiles(unittest.TestCase):
    def test_complete_release(self):
        files = zr.release_files(release_dir())
        self.assertEqual(len(files), 17)
        self.assertEqual(files[:2], ["README.md", "full_dump.csv"])

    def test_missing_gmt(self):
        with self.assertRaises(SystemExit):
            zr.release_files(release_dir(gmts=GMTS[1:]))

    def test_full_dump_without_header(self):
        with self.assertRaises(SystemExit):
            zr.release_files(release_dir(header=""))


class NewsEntry(unittest.TestCase):
    def test_entry_of_this_version_only(self):
        entry = zr.news_entry(release_dir(), "v1.5.0")
        self.assertTrue(entry.startswith("NEW DATA\n\n    o SUMMARY: 2 signatures"))
        self.assertIn('"Retracted paper"', entry)
        self.assertNotIn("1 signature\n", entry + "\n")
        self.assertNotIn("----", entry)
        self.assertIn("\n\nQUALITY CONTROL\n\n", entry)  # blank lines kept

    def test_older_entry(self):
        self.assertEqual(zr.news_entry(release_dir(), "v1.4.0"), "NEW DATA\n\n    o SUMMARY: 1 signature")

    def test_missing_entry(self):
        with self.assertRaises(SystemExit):
            zr.news_entry(release_dir(), "v9.9.9")


class Metadata(unittest.TestCase):
    base = {
        "title": "old title", "doi": "10.5281/zenodo.1", "prereserve_doi": {"doi": "x"},
        "version": "v1.4.0", "publication_date": "2026-11-19", "upload_type": "software",
        "license": {"id": "CC-BY-4.0"}, "grants": [{"id": "g"}],
        "related_identifiers": [
            {"identifier": "https://github.com/waldronlab/BugSigDBExports/tree/v1.4.0",
             "relation": "isSupplementTo", "scheme": "url"},
            {"identifier": "10.1093/nar/gkad", "relation": "isCitedBy", "scheme": "doi"}],
    }
    zenodo_json = {"title": "BugSigDB", "creators": [{"name": "Waldron, Levi"}],
                   "keywords": ["human microbiome"], "license": "CC-by-4.0"}

    def test_release_fields(self):
        md = zr.metadata(self.base, "v1.5.0", 'o "x" < y', "waldronlab/BugSigDBExports", self.zenodo_json)
        self.assertEqual(md["version"], "v1.5.0")
        self.assertEqual(md["title"], "BugSigDB")
        self.assertEqual(md["creators"], [{"name": "Waldron, Levi"}])
        self.assertEqual(md["upload_type"], "dataset")
        self.assertEqual(md["license"], "cc-by-4.0")
        self.assertNotIn("doi", md)
        self.assertNotIn("prereserve_doi", md)
        self.assertEqual(md["grants"], [{"id": "g"}])  # other metadata kept
        self.assertIn("<pre>o &quot;x&quot; &lt; y</pre>", md["description"])
        ids = [r["identifier"] for r in md["related_identifiers"]]
        self.assertEqual(ids, ["10.1093/nar/gkad",
                               "https://github.com/waldronlab/BugSigDBExports/tree/v1.5.0"])

    def test_without_zenodo_json(self):
        md = zr.metadata(self.base, "v1.5.0", "", "waldronlab/BugSigDBExports")
        self.assertEqual(md["title"], "old title")
        self.assertEqual(md["license"], "cc-by-4.0")
        self.assertNotIn("<pre>", md["description"])


class Helpers(unittest.TestCase):
    def test_md5(self):
        d = release_dir()
        path = os.path.join(d, "README.md")
        self.assertEqual(zr.md5(path), hashlib.md5(b"README.md").hexdigest())

    def test_file_names_from_records_and_deposit_api(self):
        self.assertEqual(zr.file_names({"files": [{"key": "full_dump.csv"}]}), {"full_dump.csv"})
        self.assertEqual(zr.file_names({"files": [{"filename": "a.gmt"}]}), {"a.gmt"})
        self.assertEqual(zr.file_names({"files": {"entries": {"x": {"key": "x.zip"}}}}), {"x.zip"})
        self.assertEqual(zr.file_names({"files": {"count": 1}}), set())


if __name__ == "__main__":
    unittest.main()
