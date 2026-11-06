"""Nothing a company pack calls private shows up outside org/, so a copy without org/ is the open-source one.

Run: python3 -m unittest discover -s tests"""
import glob
import json
import os
import subprocess
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def tracked():
    """The files that would ship, as git sees them; every file under ROOT when there is no git."""
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "--cached", "--others", "--exclude-standard"],
                             capture_output=True, text=True, check=True).stdout.split("\n")
    except (OSError, subprocess.CalledProcessError):
        out = [os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, "**"), recursive=True) if os.path.isfile(p)]
    return [f for f in out if f and not f.startswith(("org/", "dist/", ".git/")) and os.path.isfile(os.path.join(ROOT, f))]


class OpenSourceTest(unittest.TestCase):
    def test_private_terms_stay_in_org(self):
        terms = [t for p in glob.glob(os.path.join(ROOT, "org", "*", "org.json")) for t in json.load(open(p)).get("private_terms", [])]
        hits = []
        for f in tracked():
            try:
                text = open(os.path.join(ROOT, f), encoding="utf-8").read().lower()
            except (UnicodeDecodeError, OSError):
                continue  # images
            hits += ["%s: %s" % (f, t) for t in terms if t.lower() in text]
        self.assertEqual(hits, [])


if __name__ == "__main__":
    unittest.main()
