"""已处理 ends a thing: a draft still waiting on it goes too, or the row stays as 「确认发送」.

Run: python3 -m unittest discover -s tests"""
import argparse
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

HOME = tempfile.mkdtemp(prefix="pit-test-ack-")
os.environ["PIT_HOME"] = HOME
_spec = importlib.util.spec_from_file_location("pit_ack", os.path.join(os.path.dirname(__file__), "..", "pit", "pit.py"))
pit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pit)


class AckTest(unittest.TestCase):
    def setUp(self):
        if os.path.exists(pit.DB_PATH):
            os.remove(pit.DB_PATH)
        self.conn = pit.db()

    def draft(self, target):
        return self.conn.execute("INSERT INTO drafts(session,target,text,note,created) VALUES('s',?,'t','n',0)",
                                 (json.dumps(target),)).lastrowid

    def status(self, d):
        return self.conn.execute("SELECT status FROM drafts WHERE id=?", (d,)).fetchone()["status"]

    def ack(self, *keys):
        with redirect_stdout(io.StringIO()):
            pit.cmd_ack(argparse.Namespace(object=list(keys)))

    def test_ack_discards_the_draft_on_that_thing_only(self):
        pit.record_event(self.conn, "slack", "e1", {"text": "?"},
                         {"key": "slack_thread:C1/1.0", "state": "等你回复", "level": "attention"})
        mine = self.draft({"kind": "slack", "channel": "C1", "thread_ts": "1.0"})
        other = self.draft({"kind": "slack", "channel": "C2", "thread_ts": None})
        self.ack("slack_thread:C1/1.0")
        self.assertEqual(self.status(mine), "discarded")
        self.assertEqual(self.status(other), "pending")


if __name__ == "__main__":
    unittest.main()
