"""Check the A01 corpus itself; event decoding belongs to A03."""

import json
import unittest
from pathlib import Path


FIXTURES = Path(__file__).parent / "fixtures/neptun-ws"


def session(number):
    return [
        json.loads(line)
        for line in (FIXTURES / f"session-{number}.jsonl").read_text().splitlines()
    ]


class WebSocketFixtures(unittest.TestCase):
    def test_observed_event_coverage(self):
        events = session(1) + session(2)
        self.assertEqual(
            {event["type"] for event in events},
            {"snapshot", "alerts", "upsert", "remove", "heartbeat"},
        )
        for event in events:
            self.assertIsInstance(event["ts"], str)
            if event["type"] == "heartbeat":
                self.assertNotIn("data", event)

    def test_reopened_connection_has_unchanged_alert_baseline(self):
        first, second = session(1), session(2)
        for events in (first, second):
            self.assertEqual([e["type"] for e in events[:2]], ["snapshot", "alerts"])
            self.assertNotIn("raions", events[0]["data"])
            self.assertEqual(len(events[1]["data"]["raions"]), 69)
            self.assertEqual(len(events[1]["data"]["oblasts"]), 4)
        self.assertNotEqual(first[0]["ts"], second[0]["ts"])
        self.assertEqual(first[1]["data"], second[1]["data"])

    def test_threat_identifiers_and_positions_are_sanitized(self):
        def check(value):
            if isinstance(value, list):
                for item in value:
                    check(item)
            elif isinstance(value, dict):
                for key, item in value.items():
                    if key == "id":
                        self.assertRegex(item, r"^fixture-track-\d{3}$")
                    elif key in ("lat", "lon"):
                        self.assertEqual(item, 50.0 if key == "lat" else 30.0)
                    else:
                        check(item)

        check(session(1) + session(2))

    def test_synthetic_case_manifest(self):
        cases = json.loads((FIXTURES / "synthetic-cases.json").read_text())
        cases += json.loads((FIXTURES / "validation-cases.json").read_text())
        self.assertEqual(len({case["name"] for case in cases}), len(cases))
        self.assertEqual({case["expected"] for case in cases}, {"accept", "reject", "ignore"})
        for case in cases:
            if case["name"] == "malformed-json":
                with self.assertRaises(json.JSONDecodeError):
                    json.loads(case["raw"])
            else:
                json.loads(case["raw"])


if __name__ == "__main__":
    unittest.main()
