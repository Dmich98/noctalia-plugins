"""Exercise the installed websocat against a controlled lost connection."""

import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


def read_exact(client, count):
    result = b""
    while len(result) < count:
        chunk = client.recv(count - len(result))
        if not chunk:
            raise EOFError("WebSocket closed")
        result += chunk
    return result


def frame(client):
    first, second = read_exact(client, 2)
    length = second & 127
    if length == 126:
        length = struct.unpack("!H", read_exact(client, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", read_exact(client, 8))[0]
    if length > 65536:
        raise ValueError("Oversized test frame")
    mask = read_exact(client, 4) if second & 128 else b""
    payload = read_exact(client, length)
    if mask:
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    return first & 15, payload


def accept(listener, session):
    client, _ = listener.accept()
    client.settimeout(5)
    request = b""
    while b"\r\n\r\n" not in request:
        request += read_exact(client, 1)
        if len(request) > 16384:
            raise ValueError("Oversized handshake")
    key = re.search(br"(?im)^Sec-WebSocket-Key: ([^\r]+)", request)[1]
    digest = hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                   b"Connection: Upgrade\r\nSec-WebSocket-Accept: "
                   + base64.b64encode(digest.digest()) + b"\r\n\r\n")
    for kind, data in (("snapshot", {"threats": []}), ("alerts", {"raions": [], "oblasts": []})):
        payload = json.dumps({"type": kind, "ts": "2026-10-17T12:00:00Z",
                              "data": data, "testSession": session}).encode()
        header = bytes((0x81, len(payload))) if len(payload) < 126 else b"\x81\x7e" + struct.pack("!H", len(payload))
        client.sendall(header + payload)
    return client


@unittest.skipUnless(shutil.which("websocat"), "requires the real websocat executable")
class KeepaliveTests(unittest.TestCase):
    def test_lost_pongs_restart_child_and_deliver_new_baseline(self):
        command = re.search(r"local command = \[\[(.*?)\]\]",
                            (ROOT / "air-alert/alerts/transport.luau").read_text(), re.S)[1]
        # Exercise the actual flags with shorter deadlines; keep the real five-second retry.
        command = command.replace("--ping-interval 10", "--ping-interval 1")
        command = command.replace("--ping-timeout 30", "--ping-timeout 3")
        errors, receipts = [], []
        stopped = threading.Event()
        with socket.socket() as listener, tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(15)
            command = command.replace("wss://neptun.in.ua/api/v1/stream",
                                      f"ws://127.0.0.1:{listener.getsockname()[1]}/")

            def serve():
                try:
                    with accept(listener, 1) as client:
                        # Stay healthy beyond the accelerated timeout, then drop all traffic.
                        healthy_until = time.monotonic() + 4
                        while time.monotonic() < healthy_until:
                            opcode, payload = frame(client)
                            if opcode == 9:
                                client.sendall(bytes((0x8A, len(payload))) + payload)
                                receipts.append(time.monotonic())
                        lost_at = time.monotonic()
                        client.settimeout(7)
                        while True:
                            try:
                                frame(client)  # Consume but never answer further pings.
                            except EOFError:
                                break
                    with accept(listener, 2) as client:
                        receipts.append(time.monotonic() - lost_at)
                        stopped.wait(2)
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            process = subprocess.Popen(["/bin/sh", "-c", command], stdin=subprocess.DEVNULL,
                                       stdout=stdout, stderr=stderr, process_group=0)
            try:
                thread.join(timeout=20)
                self.assertFalse(thread.is_alive(), "lost connection did not reconnect")
                self.assertEqual(errors, [], "no ping/pong recovery from a lost connection")
                self.assertGreaterEqual(len(receipts), 4, "healthy connection must survive the timeout")
                self.assertGreaterEqual(receipts[-1], 4.9, "preserve the retry delay")
                stdout.seek(0)
                messages = [json.loads(line) for line in stdout.read().splitlines()]
                self.assertEqual([(m["testSession"], m["type"]) for m in messages],
                                 [(1, "snapshot"), (1, "alerts"), (2, "snapshot"), (2, "alerts")])
                self.assertIsNone(process.poll(), "same supervisor must remain alive")
            finally:
                stopped.set()
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)
                thread.join(timeout=2)
