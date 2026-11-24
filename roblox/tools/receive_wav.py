"""ブラウザで録音したオープニング曲(WAV)を1回だけ受け取って保存する、この PC の中だけの受け口。

  python -I roblox/tools/receive_wav.py 保存先.wav
(受け取ったら終わる。使い方は record-opening.js の先頭)

守り: この PC の中のページ(ファイルで開いた index.html か、localhost / 127.0.0.1 の配信)からだけ受け付ける。
ほかのサイトを開いていても、そのサイトからは送れない。中身が WAV でなければ保存しない。
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = sys.argv[1]
LOCAL_HOSTS = ("http://localhost", "http://127.0.0.1")


def local_origin(origin):
    """送ってきたページがこの PC の中の物か(ファイルで開いたページは "null")"""
    if origin is None or origin == "null":
        return True
    for host in LOCAL_HOSTS:
        if origin == host or origin.startswith(host + ":"):
            return True
    return False


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        origin = self.headers.get("Origin")
        if origin is not None and local_origin(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _refuse(self, code):
        self.send_response(code)
        self._cors()
        self.end_headers()

    def do_OPTIONS(self):
        if not local_origin(self.headers.get("Origin")):
            self._refuse(403)
            return
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_POST(self):
        if not local_origin(self.headers.get("Origin")):
            self._refuse(403)
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
        except ValueError:
            n = 0
        if n <= 0 or n > 40_000_000:
            self._refuse(400)
            return
        data = self.rfile.read(n)
        if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
            self._refuse(400)
            return
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
