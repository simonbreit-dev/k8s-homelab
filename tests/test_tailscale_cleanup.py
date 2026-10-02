"""Run the real cleanup playbook against a local API, with fake credentials."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from threading import Thread
import unittest
from urllib.parse import parse_qs

ROOT = Path(__file__).resolve().parents[1]


class CleanupTests(unittest.TestCase):
    def cleanup(self, token_status=200, delete_status=200, device_id="nodeidTEST"):
        calls = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                calls.append(("POST", self.path, parse_qs(body.decode())))
                self.send_response(token_status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"access_token": "fake-access-token"}).encode())

            def do_DELETE(self):
                calls.append(("DELETE", self.path, self.headers.get("Authorization")))
                self.send_response(delete_status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                if delete_status != 204:
                    self.wfile.write(b'{}')

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as directory:
                variables = Path(directory) / "vars.json"
                variables.write_text(json.dumps({
                    "tailscale_device_id": device_id,
                    "tailscale_api_base_url": f"http://127.0.0.1:{server.server_port}",
                    "ansible_python_interpreter": sys.executable,
                }))
                result = subprocess.run([
                    str(ROOT / "ansible/.venv/bin/ansible-playbook"),
                    "-i", "localhost,", "-c", "local",
                    "playbooks/delete-tailnet-device.yml", "-e", "@" + str(variables),
                    "-vvv",
                ], cwd=ROOT / "ansible", env=dict(
                    os.environ,
                    TAILSCALE_OAUTH_CLIENT_ID="fake-client",
                    TAILSCALE_OAUTH_CLIENT_SECRET="fake-client-secret",
                ), capture_output=True, text=True, timeout=45)
                output = result.stdout + result.stderr
                self.assertNotIn("fake-client-secret", output)
                self.assertNotIn("fake-access-token", output)
                return result, calls
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_deletes_only_recorded_identity_and_requests_core_scope(self):
        result, calls = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(calls, [
            ("POST", "/api/v2/oauth/token", {
                "grant_type": ["client_credentials"], "client_id": ["fake-client"],
                "client_secret": ["fake-client-secret"], "scope": ["devices:core"],
            }),
            ("DELETE", "/api/v2/device/nodeidTEST", "Bearer fake-access-token"),
        ])

    def test_successful_and_already_absent_devices(self):
        for status in [204, 404]:
            with self.subTest(status=status):
                result, calls = self.cleanup(delete_status=status)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(len(calls), 2)

    def test_unauthorized_token_stops_before_deletion(self):
        result, calls = self.cleanup(token_status=403)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("HTTP 403", result.stdout)

    def test_deletion_errors_stop_destroy(self):
        for status in [403, 500]:
            with self.subTest(status=status):
                result, calls = self.cleanup(delete_status=status)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(calls), 2)
                self.assertIn(f"HTTP {status}", result.stdout)

    def test_invalid_identity_fails_before_api_access(self):
        for identity in ["", "../other-device", "name'; exit 0"]:
            with self.subTest(identity=identity):
                result, calls = self.cleanup(device_id=identity)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
