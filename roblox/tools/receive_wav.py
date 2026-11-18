"""ブラウザで録音したオープニング曲(WAV)を1回だけ受け取って保存する、この PC の中だけの受け口。

  python -I roblox/tools/receive_wav.py 保存先.wav
(受け取ったら終わる。使い方は record-opening.js の先頭)
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = sys.argv[1]


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        if n <= 0 or n > 40_000_000:
            self.send_response(400)
            self._cors()
            self.end_headers()
            return
        data = self.rfile.read(n)
        with open(OUT, "wb") as f:
            f.write(data)
        self.send_response(200)
        self._cors()
        self.end_headers()
        self.wfile.write(b"ok")
        print("saved", n, flush=True)
        self.server.done = True


srv = HTTPServer(("127.0.0.1", 8766), Handler)
srv.done = False
while not srv.done:
    srv.handle_request()
