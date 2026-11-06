"""One object, one session: a conversation keeps the session that followed it after the wait ends.

Run: python3 -m unittest discover -s tests"""
import argparse
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

HOME = tempfile.mkdtemp(prefix="pit-test-owner-")
os.environ["PIT_HOME"] = HOME
_spec = importlib.util.spec_from_file_location("pit_owner", os.path.join(os.path.dirname(__file__), "..", "pit", "pit.py"))
pit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pit)


def watch(kind, session, **kw):
    a = argparse.Namespace(session=session, title=None, link=None, note="n", dossier=None, timeout=None,
                           thread=None, sender=None, channel=None, doc=None, object=None, state=None)
    for k, v in kw.items():
        setattr(a, k, v)
    with redirect_stdout(io.StringIO()) as out:
        {"slack": pit.cmd_watch_slack, "doc": pit.cmd_watch_doc, "object": pit.cmd_watch_object}[kind](a)
    return json.loads(out.getvalue())["sub"]


def unwatch(sub):
    with redirect_stdout(io.StringIO()):
        pit.cmd_unwatch(argparse.Namespace(id=sub))


class OwnerTest(unittest.TestCase):
    def setUp(self):
        if os.path.exists(pit.DB_PATH):
            os.remove(pit.DB_PATH)
        self.conn = pit.db()

    def test_dm_stays_with_its_session_after_unwatch(self):
        sub = watch("slack", "S1", channel="D1")
        unwatch(sub)
        self.assertEqual(pit.object_session(pit.db(), "slack_dm:D1"), "S1")
        self.assertIsNone(pit.sub_session(pit.db(), "slack_dm:D1"))

    def test_thread_falls_back_to_channel_then_its_own(self):
        unwatch(watch("slack", "CH", channel="C1"))
        conn = pit.db()
        self.assertEqual(pit.object_session(conn, "slack_thread:C1/100.1"), "CH")
        unwatch(watch("slack", "TH", channel="C1", thread="100.1"))
        conn = pit.db()
        self.assertEqual(pit.object_session(conn, "slack_thread:C1/100.1"), "TH")
        self.assertEqual(pit.object_session(conn, "slack_thread:C1/200.2"), "CH")

    def test_doc_comment_goes_to_the_document_session(self):
        unwatch(watch("doc", "DOC", doc="https://x.larksuite.com/wiki/TOKEN123?from=a"))
        self.assertEqual(pit.object_session(pit.db(), "doc_comment:TOKEN123#c9"), "DOC")

    def test_auto_start_hands_back_instead_of_new_session(self):
        unwatch(watch("slack", "S1", channel="D1"))
        conn, started = pit.db(), []
        pit.emit_if_changed(conn, "slack", "slack_dm:D1", "new_message", "attention", "私聊 · 甲", "在吗", None)
        conn.commit()
        orig = (pit.launch_task, pit.launch_cli, pit.herdr_agents)
        pit.launch_task = lambda *a, **k: started.append("new") or "NEW"
        pit.launch_cli = lambda *a, **k: started.append("resume")
        pit.herdr_agents = lambda: {}
        try:
            r = pit.auto_start(conn, {"claude_open": "herdr"}, pit.object_row(conn, "slack_dm:D1"))
        finally:
            pit.launch_task, pit.launch_cli, pit.herdr_agents = orig
        self.assertEqual(r["sid"], "S1")
        self.assertEqual(started, ["resume"])
        self.assertEqual(pit.sub_session(conn, "slack_dm:D1"), "S1")
        n = conn.execute("SELECT COUNT(*) FROM deliveries WHERE session='S1' AND status='pending'").fetchone()[0]
        self.assertEqual(n, 1)

    def test_migration_gives_old_follows_their_owner(self):
        conn = pit.db()
        conn.execute("INSERT INTO subs(session,kind,match,note,created,active) VALUES('OLD','slack',?,'n',0,0)",
                     (json.dumps({"channel": "D7"}),))
        conn.execute("DELETE FROM cursors WHERE key='migrated:owners'")
        conn.commit()
        self.assertEqual(pit.object_session(pit.db(), "slack_dm:D7"), "OLD")


if __name__ == "__main__":
    unittest.main()
