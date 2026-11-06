"""Noise rules: notices settled as FYI before the model, and bots kept from waking a waiting session.

Run: python3 -m unittest discover -s tests
Each test runs against a fresh pit home in a temporary folder; nothing touches the real database."""
import importlib.util
import json
import os
import tempfile
import time
import unittest

HOME = tempfile.mkdtemp(prefix="pit-test-")
os.environ["PIT_HOME"] = HOME
_spec = importlib.util.spec_from_file_location("pit", os.path.join(os.path.dirname(__file__), "..", "pit", "pit.py"))
pit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pit)

ME = "U0000000001"
OFF = {"classifier": {"backend": "off"}}  # no model: whatever is not a noise rule keeps the rule's baseline


class Base(unittest.TestCase):
    def setUp(self):
        if os.path.exists(pit.DB_PATH):
            os.remove(pit.DB_PATH)
        self.conn = pit.db()
        # known senders, so no test calls slackctl
        for uid, bot in (("UPERSON", "0"), ("UBOT", "1")):
            pit.set_cursor(self.conn, "slack_bot:%s" % uid, bot)
            pit.set_cursor(self.conn, "slack_user:%s" % uid, uid)


class AckTest(unittest.TestCase):
    def test_acknowledgments(self):
        for text in ["好的", "好的～", "收到！", "感谢", "谢谢", "Thanks!", "thank you", "OK", "ok 收到",
                     "辛苦了", "我去私聊下", "明白了", ":+1:", "👍", "<@U0000000001> 收到", "嗯嗯", "好的，感谢"]:
            self.assertTrue(pit.is_ack(text), text)

    def test_not_acknowledgments(self):
        for text in ["好的？", "可以吗", "好的 这个比较贴切", "我去私聊下，你看要不要拉上 Alex", "<@U0000000001> 这里",
                     "<@U0000000001>", "", "这个怎么说", "收到，明天给我结论", "有一些ai的也要看下",
                     "<@U0000000001> 一起吧", "大佬，这个怎么说？:face_holding_back_tears:"]:
            self.assertFalse(pit.is_ack(text), text)


class DecideTest(Base):
    def test_fyi_channel(self):
        got = pit.decide(self.conn, dict(OFF, noise={"fyi_channels": ["D0000000001"]}), "slack_dm:D0000000001",
                         "1.0", "ctx", "decide", "D0000000001",
                         ":clipboard: New approval task")
        self.assertEqual(got, ("fyi", None, "rule"))

    def test_fyi_channels_from_config(self):
        cfg = dict(OFF, noise={"fyi_channels": ["DOTHER"]})
        self.assertEqual(pit.decide(self.conn, cfg, "slack_dm:DOTHER", "1.0", "ctx", "reply", "DOTHER", "在吗")[0], "fyi")
        # the default list is replaced, not added to
        self.assertEqual(pit.decide(self.conn, cfg, "slack_dm:D0000000001", "1.0", "ctx", "reply", "D0000000001",
                                    "New approval task")[0], "reply")

    def test_ack_is_fyi(self):
        self.assertEqual(pit.decide(self.conn, OFF, "slack_dm:D1", "1.0", "ctx", "reply", "D1", "好的，感谢"),
                         ("fyi", None, "rule"))

    def test_question_keeps_baseline(self):
        self.assertEqual(pit.decide(self.conn, OFF, "slack_dm:D1", "1.0", "ctx", "reply", "D1", "好的，那明天能给吗"),
                         ("reply", None, "rule"))

    def test_without_text_rules_do_not_apply(self):
        # Lark comments call decide without channel or text
        self.assertEqual(pit.decide(self.conn, OFF, "doc_comment:x", "1", "好的", "reply")[0], "reply")

    def test_person_label_wins(self):
        pit.set_cursor(self.conn, "label:slack_dm:D1", "1.0|reply")
        self.assertEqual(pit.decide(self.conn, OFF, "slack_dm:D1", "1.0", "ctx", "fyi", "D1", "好的"),
                         ("reply", None, "person"))


class SubBotTest(Base):
    def sub(self, match):
        self.conn.execute("INSERT INTO subs(session,kind,match,note,created,deadline) VALUES(?,?,?,?,?,?)",
                          ("local_test", "slack", json.dumps(match), "test", time.time() - 60, time.time() + 3600))
        return self.conn.execute("SELECT max(id) FROM subs").fetchone()[0]

    def post(self, user=None, ts=None, **extra):
        ts = ts or "%.6f" % time.time()
        msg = dict({"ts": ts, "thread_ts": "100.000001", "text": "hi", "permalink": "https://x/p1"}, **extra)
        if user:
            msg["user"] = user
        pit.record_slack(self.conn, OFF, "C1", msg)

    def delivered(self, sub):
        return self.conn.execute("SELECT count(*) FROM deliveries WHERE sub_id=?", (sub,)).fetchone()[0]

    def test_person_wakes(self):
        s = self.sub({"channel": "C1", "thread_ts": "100.000001"})
        self.post("UPERSON")
        self.assertEqual(self.delivered(s), 1)

    def test_bot_does_not_wake(self):
        s = self.sub({"channel": "C1", "thread_ts": "100.000001"})
        self.post("UBOT")
        self.post(None, bot_id="B1")
        self.post("UPERSON", subtype="bot_message")
        self.assertEqual(self.delivered(s), 0)
        # the message is still recorded: the object shows it, only the wake-up is skipped
        self.assertEqual(self.conn.execute("SELECT count(*) FROM events WHERE source='slack'").fetchone()[0], 3)

    def test_unknown_sender_wakes(self):
        s = self.sub({"channel": "C1", "thread_ts": "100.000001"})
        self.post(None)
        self.assertEqual(self.delivered(s), 1)

    def test_waiting_on_a_bot_by_name(self):
        s = self.sub({"channel": "C1", "from": "UBOT"})
        self.post("UBOT")
        self.assertEqual(self.delivered(s), 1)

    def test_switch_off(self):
        s = self.sub({"channel": "C1"})
        pit.save_config({"noise": {"subs_ignore_bots": False}})
        try:
            pit.record_slack(self.conn, pit.load_config(), "C1",
                             {"ts": "%.6f" % time.time(), "user": "UBOT", "text": "alert", "permalink": "https://x/p2"})
        finally:
            os.remove(pit.CONFIG_PATH)
        self.assertEqual(self.delivered(s), 1)

    def test_timeout_still_fires_after_bot_posts(self):
        s = self.sub({"channel": "C1", "thread_ts": "100.000001"})
        self.post("UBOT")
        self.conn.execute("UPDATE subs SET deadline=? WHERE id=?", (time.time() - 1, s))
        pit.fire_clock(self.conn)
        row = self.conn.execute("SELECT e.payload FROM deliveries d JOIN events e ON e.id=d.event_id "
                                "WHERE d.sub_id=?", (s,)).fetchone()
        self.assertEqual(json.loads(row[0])["kind"], "timeout")


if __name__ == "__main__":
    unittest.main()
