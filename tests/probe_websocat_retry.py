"""Opt-in loopback probe: exit nonzero if websocat retries established sessions too fast."""

import base64
import hashlib
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time


def retry_gap(executable, accept_handshake):
    times, errors = [], []
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        listener.settimeout(12)

        def serve():
            try:
                for _ in range(2):
                    client, _ = listener.accept()
                    times.append(time.monotonic())
                    with client:
                        client.settimeout(3)
                        request = b""
                        while b"\r\n\r\n" not in request:
                            data = client.recv(4096)
                            if not data or len(request) + len(data) > 16384:
                                raise ValueError("Invalid test handshake")
                            request += data
                        if accept_handshake:
                            key = re.search(br"(?im)^Sec-WebSocket-Key: ([^\r]+)", request)[1]
                            digest = hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
                            client.sendall(
                                b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                                b"Connection: Upgrade\r\nSec-WebSocket-Accept: "
                                + base64.b64encode(digest.digest()) + b"\r\n\r\n"
                            )
                            time.sleep(0.05)
                        else:
                            client.sendall(
                                b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n"
                            )
            except Exception as error:
                errors.append(error)

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        with tempfile.TemporaryFile() as diagnostics:
            process = subprocess.Popen(
                [executable, "-t", "-u", "-n", "--autoreconnect-delay-millis", "5000",
                 f"autoreconnect:ws://127.0.0.1:{listener.getsockname()[1]}/", "-"],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=diagnostics,
            )
            try:
                thread.join(timeout=12)
                if thread.is_alive() or errors or len(times) != 2:
                    diagnostics.seek(0)
                    raise RuntimeError(
                        f"Probe incomplete: {errors}; {diagnostics.read().decode(errors='replace')}"
                    )
            finally:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        return times[1] - times[0]


if __name__ == "__main__":
    executable = sys.argv[1] if len(sys.argv) > 1 else "websocat"
    closed = retry_gap(executable, True)
    rejected = retry_gap(executable, False)
    print(f"Established connection closed: {closed:.3f}s between attempts")
    print(f"Handshake rejected: {rejected:.3f}s between attempts")
    if closed < 4.8 or rejected < 4.8:
        sys.exit("BLOCKED: --autoreconnect-delay-millis 5000 does not bound both retry paths")
