"""A thread or comment has one reply waiting at a time: a newer draft replaces the pending one.

Run: python3 -m unittest discover -s tests"""
import argparse
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

HOME = tempfile.mkdtemp(prefix="pit-test-draft-")
os.environ["PIT_HOME"] = HOME
_spec = importlib.util.spec_from_file_location("pit_draft", os.path.join(os.path.dirname(__file__), "..", "pit", "pit.py"))
pit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pit)


class DraftTest(unittest.TestCase):
    def setUp(self):
        if os.path.exists(pit.DB_PATH):
            os.remove(pit.DB_PATH)
        self.conn = pit.db()

    def add(self, text, channel="C1", thread="1.0", session="s"):
        path = os.path.join(HOME, "draft.txt")
        with open(path, "w") as f:
            f.write(text)
        buf = io.StringIO()
        with redirect_stdout(buf):
            pit.cmd_draft_add(argparse.Namespace(session=session, slack_channel=channel, thread=thread, doc=None,
                                                 comment=None, text_file=path, note="n"))
        return json.loads(buf.getvalue())

    def pending(self):
        return [r["text"] for r in pit.db().execute("SELECT text FROM drafts WHERE status='pending' ORDER BY id")]

    def test_newer_draft_to_the_same_thread_replaces_the_pending_one(self):
        first = self.add("方案：预期下一个版本带上")
        second = self.add("已经加好，更新即可", session="other")
        self.assertEqual(second["replaced"], [first["draft"]])
        self.assertEqual(self.pending(), ["已经加好，更新即可"])

    def test_other_threads_and_the_channel_itself_keep_their_drafts(self):
        self.add("thread 1.0")
        self.add("thread 2.0", thread="2.0")
        out = self.add("channel", thread=None)
        self.assertNotIn("replaced", out)
        self.assertEqual(self.pending(), ["thread 1.0", "thread 2.0", "channel"])

    def test_a_sent_draft_is_left_alone(self):
        first = self.add("sent already")
        self.conn = pit.db()
        self.conn.execute("UPDATE drafts SET status='sent' WHERE id=?", (first["draft"],))
        self.conn.commit()
        self.assertNotIn("replaced", self.add("follow-up"))


if __name__ == "__main__":
    unittest.main()
