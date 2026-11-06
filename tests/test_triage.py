"""日清 follows how the person opens Claude, and carries the whole prompt every time.

Run: python3 -m unittest discover -s tests"""
import argparse
import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

HOME = tempfile.mkdtemp(prefix="pit-test-triage-")
os.environ["PIT_HOME"] = HOME
_spec = importlib.util.spec_from_file_location("pit_triage", os.path.join(os.path.dirname(__file__), "..", "pit", "pit.py"))
pit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pit)


class TriageTest(unittest.TestCase):
    def setUp(self):
        if os.path.exists(pit.DB_PATH):
            os.remove(pit.DB_PATH)
        self.conn = pit.db()
        self.launched, self.prompted = [], []
        pit.launch_cli = lambda sid, prompt=None, resume=False: self.launched.append((sid, prompt, resume))
        pit.herdr_agents = lambda: {"pit-agent": {"agent_status": "idle"}}
        pit.herdr = lambda *a, **k: self.prompted.append(a) or {}
        pit.subprocess = argparse.Namespace(run=lambda *a, **k: None)  # no Ghostty brought forward in a test

    def triage(self, mode, group="mine"):
        pit.load_config = lambda: {"claude_open": mode}
        out = io.StringIO()
        with redirect_stdout(out):
            pit.cmd_triage(argparse.Namespace(group=group))
        return out.getvalue().strip()

    def test_desktop_starts_a_session_with_the_prompt(self):
        pit.set_cursor(self.conn, pit.triage_key("mine"), "local_x")
        self.conn.commit()
        self.assertTrue(self.triage("desktop").startswith("claude://code/new?"))

    def test_desktop_session_makes_way_in_terminal(self):
        pit.set_cursor(self.conn, pit.triage_key("mine"), "local_x")
        self.conn.commit()
        self.assertEqual(self.triage("terminal"), "")
        sid, prompt, resume = self.launched[-1]
        self.assertFalse(resume)
        self.assertIn("日清", prompt)
        self.assertEqual(pit.get_cursor(pit.db(), pit.triage_key("mine")), sid)

    def test_running_herdr_session_gets_the_prompt_again(self):
        pit.set_cursor(self.conn, pit.triage_key("mine"), "abc")
        pit.set_cursor(self.conn, "herdr:abc", "pit-agent")
        self.conn.commit()
        self.triage("herdr")
        self.assertEqual(self.prompted[0][:3], ("agent", "prompt", "pit-agent"))
        self.assertIn("日清", self.prompted[0][3])
        self.assertEqual(self.launched, [])

    def test_ended_session_is_resumed_with_the_prompt_the_current_way(self):
        pit.set_cursor(self.conn, pit.triage_key("fyi"), "abc")
        pit.set_cursor(self.conn, "open:abc", json.dumps({"mode": "terminal", "title": "日清"}))
        self.conn.commit()
        self.triage("herdr", "fyi")
        sid, prompt, resume = self.launched[-1]
        self.assertEqual((sid, resume), ("abc", True))
        self.assertIn("新消息", prompt)
        self.assertEqual(json.loads(pit.get_cursor(pit.db(), "open:abc"))["mode"], "herdr")


if __name__ == "__main__":
    unittest.main()
