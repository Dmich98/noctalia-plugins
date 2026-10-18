"""Exercise the production shell command with a controlled child executable."""

import contextlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parent.parent
COMMAND = re.search(
    r"local command = \[\[(.*?)\]\]",
    (ROOT / "air-alert/alerts/transport.luau").read_text(), re.S,
)[1]
CHILD = """
import json, os, signal, sys, time
print('{"type":"heartbeat"}', flush=True)
print('test diagnostic', file=sys.stderr, flush=True)
with open(os.environ['AIR_ALERT_TEST_LOG'], 'a') as log:
    log.write(json.dumps({'pid': os.getpid(), 'time': time.monotonic()}) + '\\n')
if os.environ['AIR_ALERT_TEST_MODE'] == 'hold':
    signal.pause()
else:
    sys.exit(int(os.environ['AIR_ALERT_TEST_MODE']))
"""


def wait_for(read, matches):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        value = read()
        if matches(value):
            return value
        time.sleep(0.02)
    raise AssertionError("Timed out waiting for test child")


def running(pid):
    try:
        return Path(f"/proc/{pid}/stat").read_text().split()[2] != "Z"
    except FileNotFoundError:
        return False


@contextlib.contextmanager
def supervisor(mode):
    with tempfile.TemporaryDirectory(prefix="air-alert-transport-") as directory:
        folder = Path(directory)
        child = folder / "websocat"
        child.write_text(f"#!{sys.executable}\n" + CHILD)
        child.chmod(0o755)
        log = folder / "starts.jsonl"
        log.touch()
        env = dict(os.environ, PATH=f"{folder}:/usr/bin:/bin",
                   AIR_ALERT_TEST_LOG=str(log), AIR_ALERT_TEST_MODE=mode)
        process = subprocess.Popen(
            ["/bin/sh", "-c", COMMAND], stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, process_group=0,
        )
        try:
            yield process, lambda: [json.loads(line) for line in log.read_text().splitlines()]
        finally:
            # Match Noctalia's process-group cancellation, even if an assertion fails.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=2)


@unittest.skipUnless(sys.platform == "linux", "Noctalia process-group checks use Linux /proc")
class TransportProcessTests(unittest.TestCase):
    def test_retry_waits_and_stderr_stays_separate(self):
        for code in ("0", "1"):
            with self.subTest(code=code), supervisor(code) as (process, starts):
                records = wait_for(starts, lambda rows: len(rows) >= 2)
                self.assertEqual(len(records), 2)
                self.assertGreaterEqual(records[1]["time"] - records[0]["time"], 4.9)
                self.assertFalse(running(records[0]["pid"]))
                os.killpg(process.pid, signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=2)
                self.assertEqual([json.loads(line) for line in stdout.splitlines()],
                                 [{"type": "heartbeat"}, {"type": "heartbeat"}])
                self.assertIn(b"test diagnostic", stderr)

    def test_cancel_during_connection_stops_child(self):
        with supervisor("hold") as (process, starts):
            child = wait_for(starts, bool)[0]["pid"]
            self.assertEqual(os.getpgid(child), process.pid)
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=2)
            wait_for(lambda: running(child), lambda active: not active)
            self.assertEqual(len(starts()), 1)

    def test_cancel_during_retry_stops_sleep(self):
        with supervisor("1") as (process, starts):
            wait_for(starts, bool)

            def sleeper():
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text()
                for pid in children.split():
                    try:
                        if Path(f"/proc/{pid}/comm").read_text().strip() == "sleep":
                            return int(pid)
                    except FileNotFoundError:
                        pass
                return None

            child = wait_for(sleeper, bool)
            self.assertEqual(os.getpgid(child), process.pid)
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=2)
            wait_for(lambda: running(child), lambda active: not active)
            self.assertEqual(len(starts()), 1)

    def test_missing_or_unexecutable_child_stops_supervisor(self):
        for code in (126, 127):
            with self.subTest(code=code), supervisor(str(code)) as (process, starts):
                process.communicate(timeout=2)
                self.assertEqual(process.returncode, code)
                self.assertEqual(len(starts()), 1)


if __name__ == "__main__":
    unittest.main()
