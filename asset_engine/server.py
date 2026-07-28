#!/usr/bin/env python3
"""Loopback HTTP server for NAZA Asset Foundry reviewed codecells."""
from __future__ import annotations

import argparse
import hmac
import ipaddress
import json
import os
import sys
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

try:
    from .policy import PolicyError
    from .runner import ExecutionRejected, execute
except ImportError:  # direct script execution
    from policy import PolicyError
    from runner import ExecutionRejected, execute


MAX_REQUEST_BYTES = 96 * 1024 * 1024


def default_root() -> Path:
    override = os.environ.get("ASSET_FOUNDRY_RUN_ROOT")
    if override:
        return Path(override).expanduser().resolve()
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home()))
        return base / "NazaAssetFoundry" / "runs"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "NazaAssetFoundry" / "runs"
    return Path.home() / ".local" / "share" / "naza_asset_foundry" / "runs"


class AssetServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], root: Path, token: str):
        super().__init__(address, Handler)
        self.root = root
        self.token = token


class Handler(BaseHTTPRequestHandler):
    server: AssetServer

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write("[asset-engine] " + (fmt % args) + "\n")

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self) -> bool:
        expected = self.server.token
        if not expected:
            return True
        supplied = self.headers.get("Authorization", "")
        if not supplied.startswith("Bearer "):
            return False
        return hmac.compare_digest(supplied[7:], expected)

    def _payload(self) -> dict[str, Any]:
        length_text = self.headers.get("Content-Length")
        if length_text is None:
            raise ExecutionRejected("Content-Length is required.")
        length = int(length_text)
        if length < 0 or length > MAX_REQUEST_BYTES:
            raise ExecutionRejected("Request body is too large.")
        raw = self.rfile.read(length)
        value = json.loads(raw.decode("utf-8"))
        if not isinstance(value, dict):
            raise ExecutionRejected("Request JSON must be an object.")
        return value

    def do_GET(self) -> None:
        if self.path == "/health":
            self._json(
                HTTPStatus.OK,
                {
                    "ok": True,
                    "service": "naza-asset-foundry-engine",
                    "version": 1,
                    "root": str(self.server.root),
                    "authenticationRequired": bool(self.server.token),
                },
            )
            return
        self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:
        if self.path != "/v1/execute":
            self._json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})
            return
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"ok": False, "error": "Unauthorized"})
            return
        try:
            result = execute(self._payload(), self.server.root)
            self._json(HTTPStatus.OK, result.to_dict())
        except PolicyError as exc:
            self._json(
                HTTPStatus.UNPROCESSABLE_ENTITY,
                {
                    "ok": False,
                    "error": "The reviewed cell violates the execution policy.",
                    "findings": [finding.to_dict() for finding in exc.findings],
                },
            )
        except (ExecutionRejected, ValueError, json.JSONDecodeError) as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
        except Exception as exc:  # The traceback stays local for diagnostics.
            traceback.print_exc()
            self._json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"ok": False, "error": f"Engine failure: {type(exc).__name__}: {exc}"},
            )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=47896)
    parser.add_argument("--root", type=Path, default=default_root())
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    address = ipaddress.ip_address(args.host)
    if not address.is_loopback:
        raise SystemExit("The asset engine refuses to bind to a non-loopback address.")
    root = args.root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    token = os.environ.get("ASSET_FOUNDRY_ENGINE_TOKEN", "")
    server = AssetServer((args.host, args.port), root, token)
    print(f"NAZA Asset Foundry engine listening on http://{args.host}:{args.port}", flush=True)
    print(f"Run root: {root}", flush=True)
    print("Human approval hash enforcement: enabled", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
