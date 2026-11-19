#!/usr/bin/env python3
import argparse
import os
import shlex
import signal
import socket
import subprocess
import sys
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LITERT_DEFAULT_CMD = ["litert-lm", "serve", "--host", "0.0.0.0", "--port", "1234"]
DEFAULT_UPSTREAM = "http://127.0.0.1:1234"
DEFAULT_PROXY_PORT = 8000


def log(msg: str):
    print(f"[litert-cors] {msg}")


class CORSProxyHandler(BaseHTTPRequestHandler):
    server_version = "litert-cors/1.0"

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        self._proxy_request()

    def do_POST(self):
        self._proxy_request()

    def do_PUT(self):
        self._proxy_request()

    def do_DELETE(self):
        self._proxy_request()

    def _proxy_request(self):
        parsed = urllib.parse.urlsplit(self.path)
        target_path = parsed.path or "/"
        target_query = parsed.query
        target_url = f"{DEFAULT_UPSTREAM}{target_path}"
        if target_query:
            target_url = f"{target_url}?{target_query}"

        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in {"host", "content-length", "connection", "origin"}:
                continue
            headers[key] = value

        if target_path in ("/health", "/v1/health"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status": "ok", "service": "litert-cors-proxy"}')
            return

        try:
            req = urllib.request.Request(target_url, data=body, headers=headers, method=self.command)
            with urllib.request.urlopen(req, timeout=120) as upstream:
                status = upstream.status
                content_type = upstream.headers.get("Content-Type", "")
                is_streaming = "text/event-stream" in content_type

                self.send_response(status)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")

                for key, value in upstream.headers.items():
                    key_lower = key.lower()
                    if key_lower in {"transfer-encoding", "connection", "content-length", "access-control-allow-origin", "access-control-allow-methods", "access-control-allow-headers"}:
                        continue
                    self.send_header(key, value)

                if is_streaming:
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("X-Accel-Buffering", "no")
                    self.end_headers()
                    while True:
                        chunk = upstream.read(512)
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        self.wfile.flush()
                else:
                    data = upstream.read()
                    if "Content-Length" not in upstream.headers:
                        self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    if data:
                        self.wfile.write(data)
                        self.wfile.flush()
        except Exception as exc:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            payload = (
                '{"error": "Proxy error", "detail": "' + str(exc).replace('"', '\\"') + '"}'
            ).encode("utf-8")
            self.wfile.write(payload)

    def log_message(self, format, *args):
        log(f"{self.address_string()} - {format % args}")


def start_litert_server(command):
    log(f"Starting: {' '.join(command)}")
    popen = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

    def stream_output():
        try:
            for line in iter(popen.stdout.readline, ""):
                if line:
                    print(line.rstrip())
        except Exception:
            pass

    import threading
    threading.Thread(target=stream_output, daemon=True).start()
    return popen


def find_free_port(start_port: int = DEFAULT_PROXY_PORT, max_tries: int = 20):
    for port in range(start_port, start_port + max_tries):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                sock.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"No free port found from {start_port} to {start_port + max_tries - 1}")


def start_proxy_server(port: int):
    try:
        server = ThreadingHTTPServer(("0.0.0.0", port), CORSProxyHandler)
    except OSError as exc:
        if exc.errno == 48:
            fallback_port = find_free_port(port + 1)
            log(f"Port {port} is busy, retrying on port {fallback_port}")
            server = ThreadingHTTPServer(("0.0.0.0", fallback_port), CORSProxyHandler)
            port = fallback_port
        else:
            raise

    log(f"CORS proxy listening on http://localhost:{port}")
    log(f"Use http://localhost:{port}/v1 as the browser-facing OpenAI-compatible endpoint")
    return server


def main():
    global DEFAULT_UPSTREAM

    parser = argparse.ArgumentParser(description="Run litert-lm and expose it with CORS-enabled proxy")
    parser.add_argument("--cmd", nargs="*", default=LITERT_DEFAULT_CMD, help="Command to start litert-lm serve")
    parser.add_argument("--proxy-port", type=int, default=DEFAULT_PROXY_PORT, help="Port for the CORS proxy")
    parser.add_argument("--upstream", default=DEFAULT_UPSTREAM, help="Upstream URL for litert-lm")
    args = parser.parse_args()

    DEFAULT_UPSTREAM = args.upstream.rstrip("/")
    requested_port = args.proxy_port if args.proxy_port else DEFAULT_PROXY_PORT

    try:
        litert = start_litert_server(args.cmd)
        proxy = start_proxy_server(requested_port)
    except RuntimeError as exc:
        print(f"[litert-cors] ERROR: {exc}")
        raise SystemExit(1)

    def shutdown(signum, frame):
        log("Shutting down...")
        try:
            if litert.poll() is None:
                litert.terminate()
                litert.wait(timeout=10)
        except Exception:
            try:
                litert.kill()
            except Exception:
                pass
        try:
            proxy.shutdown()
        except Exception:
            pass
        raise SystemExit(0)

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        proxy.serve_forever()
    except KeyboardInterrupt:
        shutdown(None, None)


if __name__ == "__main__":
    main()
