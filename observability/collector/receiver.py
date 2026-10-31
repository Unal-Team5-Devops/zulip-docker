import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

class Receiver(BaseHTTPRequestHandler):
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        event = {'received_at': datetime.now(timezone.utc).isoformat(), 'payload': payload}
        with Path('/events/alerts.jsonl').open('a') as stream:
            stream.write(json.dumps(event) + '\n')
        print(json.dumps(event), flush=True)
        self.send_response(200)
        self.end_headers()

HTTPServer(('0.0.0.0', 8080), Receiver).serve_forever()
