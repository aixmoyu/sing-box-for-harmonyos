#!/usr/bin/env python3
"""Exercise the support-page probe without making an external network request."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys


class FakeConnection:
    def close(self) -> None:
        return None


class FakeResponse:
    def __init__(self, status: int, headers: dict[str, str], body: bytes) -> None:
        self.status = status
        self.headers = headers
        self.body = body
        self.offset = 0

    def getheader(self, name: str) -> str | None:
        return self.headers.get(name)

    def read(self, size: int) -> bytes:
        if self.offset >= len(self.body):
            return b""
        chunk = self.body[self.offset:self.offset + size]
        self.offset += len(chunk)
        return chunk

    def close(self) -> None:
        return None


def load_gate(path: pathlib.Path):
    spec = importlib.util.spec_from_file_location("release_content_gate", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("release content gate could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: release_content_probe_fixture.py GATE SCENARIO")
    gate = load_gate(pathlib.Path(sys.argv[1]).resolve())
    scenario = sys.argv[2]
    headers = {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Length": "28",
        "Content-Encoding": "identity",
    }
    status = 201
    body = b"<html>Support is here</html>"

    if scenario == "bad-mime":
        headers["Content-Type"] = "application/octet-stream"
    elif scenario == "oversized-header":
        headers["Content-Length"] = str(gate.SUPPORT_PAGE_MAX_BYTES + 1)
    elif scenario == "compressed":
        headers["Content-Encoding"] = "gzip"
    elif scenario == "empty":
        status = 204
        headers.pop("Content-Length")
        body = b""
    elif scenario == "redirect-private":
        status = 302
        headers = {"Location": "https://127.0.0.1/private-support"}
        body = b""
    elif scenario != "success":
        raise SystemExit("unknown scenario")

    def fake_request(url: str):
        return FakeConnection(), FakeResponse(status, headers, body), url

    gate._request = fake_request
    try:
        result = gate.probe_url("https://support.harmonynet.app/help")
    except gate.GateError as exc:
        print(f"RELEASE_CONTENT_BLOCKED: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
