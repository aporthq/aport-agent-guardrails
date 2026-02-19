"""
Minimal mock APort verify API for performance tests.
Responds to POST /api/verify/policy/:id with 200 and OAP decision.
Run: python tests/performance/mock_api_server.py [port]
"""

import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9876


class MockVerifyHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.startswith("/api/verify/policy/"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            body = json.dumps({
                "decision_id": "perf-mock-1",
                "allow": True,
                "reasons": [{"message": "OK"}],
                "policy_id": "system.command.execute.v1",
            }).encode()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # quiet


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), MockVerifyHandler)
    print(PORT, flush=True)
    server.serve_forever()
