#!/usr/bin/env python3
"""Exercise both example SDKs through protocol v1 with synthetic data, without platform permissions."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time
import zipfile


class Peer:
    def __init__(self, executable, directory):
        self.process = subprocess.Popen(executable, cwd=directory, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        env={"PATH": os.defpath, "PYTHONDONTWRITEBYTECODE": "1"}, bufsize=0)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.buffer = b""

    def send(self, **message):
        self.process.stdin.write(json.dumps(dict(message, jsonrpc="2.0")).encode() + b"\n")
        self.process.stdin.flush()

    def receive(self):
        deadline = time.monotonic() + 5
        while b"\n" not in self.buffer:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                raise AssertionError("SDK response timed out")
            data = os.read(self.process.stdout.fileno(), 8192)
            if not data:
                raise AssertionError("SDK exited before completing the exchange")
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        result = json.loads(line)
        assert result["jsonrpc"] == "2.0"
        return result

    def event(self, method, event_id, **params):
        if event_id > 1:
            self.send(method="cancel", params={"eventID": event_id - 1})
        self.send(method=method, params=dict(params, eventID=event_id))

    def view(self, event_id):
        message = self.receive()
        assert message["method"] == "ui" and message["params"]["eventID"] == event_id
        return message["params"]["view"]

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait(timeout=3)
        self.selector.close()
        self.process.stdin.close()
        self.process.stdout.close()
        self.process.stderr.close()


def exercise(package, language):
    with tempfile.TemporaryDirectory(prefix="zbox-sdk-test-") as directory:
        # Only locally generated test packages are accepted by this test driver.
        with zipfile.ZipFile(package) as archive:
            archive.extractall(directory)
        root = Path(directory)
        manifest = json.loads((root / "manifest.json").read_text())
        entry = root / manifest["commands"][0]["entry"]
        if language == "swift":
            entry.chmod(0o700)
            executable = [str(entry)]
        else:
            executable = [sys.executable, str(entry)]
        peer = Peer(executable, root)
        try:
            peer.send(id="initialize", method="initialize", params={"protocolVersion": 1, "sessionID": "test"})
            assert peer.receive()["result"]["protocolVersion"] == 1
            peer.event("start", 1, commandID="convert", arguments=[])
            assert len(peer.view(1)["actions"]) == 2
            peer.event("query", 2, query="lower")
            assert peer.view(2)["items"] == [{"id": "lower", "title": "Lowercase"}]
            peer.event("action", 3, actionID="read", selectedID="upper", values={"prefix": "X:"})
            request = peer.receive()
            assert request["method"] == "selection.read" and request["params"]["eventID"] == 3
            peer.send(id=request["id"], result="MiXeD")
            assert peer.view(3)["detail"] == "X:MIXED"
            peer.event("action", 4, actionID="copy", values={})
            request = peer.receive()
            assert request["method"] == "clipboard.write" and request["params"]["text"] == "X:MIXED"
            peer.send(id=request["id"], result=None)
            peer.view(4)
            peer.event("action", 5, actionID="read", values={})
            request = peer.receive()
            peer.send(id=request["id"], error={"code": -32000, "message": "Permission denied"})
            view = peer.view(5)
            assert view["error"] == "Permission denied" and len(view["actions"]) == 2
            peer.event("action", 6, actionID="read", values={})
            old_request = peer.receive()
            peer.event("query", 7, query="upper")
            peer.view(7)
            peer.send(id=old_request["id"], result="obsolete")
            assert not peer.buffer and not peer.selector.select(0.15), "Cancelled event emitted a late response"
            peer.send(method="stop")
            assert peer.process.wait(timeout=3) == 0
        finally:
            peer.close()
    print(language + ": handshake, UI, host calls, denial, cancellation and shutdown passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--python-package", type=Path, required=True)
    parser.add_argument("--swift-package", type=Path, required=True)
    args = parser.parse_args()
    exercise(args.python_package, "python")
    exercise(args.swift_package, "swift")
