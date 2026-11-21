"""Verify the real ObjectScript REST and production paths against a loopback Graph server."""
import json
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

from test_callback import call, envelope, text


class Capture(BaseHTTPRequestHandler):
    def do_POST(self):
        """Capture the request and return a synthetic Graph acknowledgement."""
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.server.captured.append((self.path, body))
        reply = b'{"messages":[{"id":"wamid.simulated.reply"}]}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)


def terminal(commands):
    """Use the isolated IRIS terminal for test observation and production lifecycle only."""
    result = subprocess.run(["iris", "session", "IRIS", "-U", "USER"],
                            input=commands + "\nhalt\n", text=True, capture_output=True, check=True)
    return result.stdout


def run():
    """Replay a signed batch, observe its receipts, then check the stopped-production response."""
    graph = HTTPServer(("127.0.0.1", 18652), Capture)
    graph.captured = []
    threading.Thread(target=graph.serve_forever, daemon=True).start()
    first, second, fence = ["wamid.local." + uuid.uuid4().hex for _ in range(3)]
    try:
        batch = envelope([{"type": "image"}, text(first), text(second)])
        for body in (batch, batch, envelope([text(fence)])):
            assert call(body) == (200, b"ok"), "IRIS did not acknowledge the callback"
        deadline = time.monotonic() + 20
        # A single queue worker processes both duplicate deliveries before the fence receipt.
        receipt = 'if ##class(WaTextCheck.Production).Sent("' + fence + '") write "RECEIPT-CONFIRMED",!'
        while "RECEIPT-CONFIRMED" not in terminal(receipt):
            assert time.monotonic() < deadline, "IRIS did not record the final receipt"
            time.sleep(0.1)
        stored = 'if ##class(WaTextCheck.Production).Received("' + fence + '",$char(20320,22909)) write "UNICODE-STORED",!'
        assert "UNICODE-STORED" in terminal(stored), "The original Unicode text did not reach the queue"
        assert len(graph.captured) == 3, graph.captured
        for path, body in graph.captured:
            assert path == "/v23.0/7123/messages", path
            assert body == {"messaging_product": "whatsapp", "to": "12345", "type": "text",
                            "text": {"body": "Thanks, your text reached IRIS."}}, body
        terminal("set sc=##class(Ens.Director).StopProduction(10,1) if $system.Status.IsError(sc) halt 1")
        assert call(envelope([text("wamid.offline")]))[0] == 503
        print("PASS: ObjectScript REST, 5 signed texts, 3 distinct Graph replies, stopped production -> 503")
    finally:
        graph.shutdown()
        graph.server_close()


if __name__ == "__main__":
    run()
