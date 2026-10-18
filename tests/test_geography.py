"""Validate the bundled geographic asset and its independent recorded parent keys."""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCATIONS = ROOT / "air-alert/locations"


class GeographyTests(unittest.TestCase):
    def test_boundaries_are_closed_and_keep_holes_and_multipolygons(self):
        source = (LOCATIONS / "boundaries.luau").read_text()
        records = re.findall(
            r'\{ key = "([^"]+)", bounds = (\{[^}]+\}), polygons = (.+) \},', source
        )
        self.assertEqual(len(records), 27 + 136)
        self.assertEqual(len({key for key, _, _ in records}), len(records))
        self.assertEqual(sum(key.startswith("raion:") for key, _, _ in records), 136)
        multipolygons = holes = 0
        for key, bounds, polygons in records:
            bounds = json.loads(bounds.replace("{", "[").replace("}", "]"))
            polygons = json.loads(polygons.replace("{", "[").replace("}", "]"))
            multipolygons += len(polygons) > 1
            points = []
            for polygon in polygons:
                self.assertGreater(len(polygon), 0, key)
                holes += len(polygon) > 1
                for ring in polygon:
                    ring = [list(map(float, point.split(","))) for point in ring.split(";")]
                    self.assertGreaterEqual(len(ring), 4, key)
                    self.assertEqual(ring[0], ring[-1], key)
                    for longitude, latitude in ring:
                        self.assertTrue(-180 <= longitude <= 180 and -90 <= latitude <= 90, key)
                    points.extend(ring)
            xs, ys = zip(*points)
            self.assertEqual(bounds, [min(xs), min(ys), max(xs), max(ys)], key)
        self.assertGreater(multipolygons, 0)
        self.assertGreater(holes, 0)

    def test_catalog_matches_boundaries_and_recorded_alert_parents(self):
        source = (LOCATIONS / "raions.luau").read_text()
        rows = re.findall(
            r'key = "([^"]+)".*?sourceKey = "([^"]+)".*?oblastKey = "([^"]+)"',
            source, re.S,
        )
        self.assertEqual(len(rows), 136)
        parents = {source_key: parent for _, source_key, parent in rows}
        self.assertEqual(len(parents), 136)
        self.assertTrue(all(key == "raion:" + source_key for key, source_key, _ in rows))
        boundaries = (LOCATIONS / "boundaries.luau").read_text()
        keys = set(re.findall(r'key = "([^"]+)"', boundaries))
        self.assertTrue(all(key in keys and parent in keys for key, _, parent in rows))
        regions = dict(re.findall(
            r'key = "([^"]+)",\s*name = "([^"]+)"',
            (LOCATIONS / "catalog.luau").read_text(),
        ))
        region_keys = {name: key for key, name in regions.items()}
        for line in (ROOT / "tests/fixtures/neptun-ws/session-1.jsonl").read_text().splitlines():
            event = json.loads(line)
            if event["type"] == "alerts":
                for alert in event["data"]["raions"]:
                    self.assertEqual(parents[alert["key"]], region_keys[alert["oblast"]])


if __name__ == "__main__":
    unittest.main()
