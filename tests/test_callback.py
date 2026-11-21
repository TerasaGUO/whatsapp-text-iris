"""Run protocol tests through the isolated container's actual IRIS Web Gateway."""
import hashlib
import hmac
import json
import unittest
import urllib.error
import urllib.parse
import urllib.request

URL = "http://127.0.0.1:52773/wa-text/webhook"


def call(body=None, *, signature=None, query=None, method=None, url=URL):
    """Issue a real HTTP request and preserve the status and raw response bytes."""
    headers = {"Content-Type": "application/json"}
    if body is not None:
        digest = hmac.new(b"local-app-secret", body, hashlib.sha256).hexdigest()
        headers["X-Hub-Signature-256"] = signature if signature is not None else "sha256=" + digest
    if query:
        url += "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        response = urllib.request.urlopen(request, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read()


def envelope(messages, phone="7123"):
    """Build a signed-notification payload with independent test metadata."""
    data = {"object": "whatsapp_business_account", "entry": [{"changes": [{
        "field": "messages", "value": {"metadata": {"phone_number_id": phone}, "messages": messages}}]}]}
    return json.dumps(data, ensure_ascii=False).encode()


def text(message_id):
    """Include non-ASCII text to check byte-exact signing and decoding."""
    return {"type": "text", "id": message_id, "from": "12345", "text": {"body": "你好"}}


class CallbackTest(unittest.TestCase):
    def test_challenge(self):
        """Echo the exact subscription challenge with a valid verification token."""
        self.assertEqual(call(query={"hub.mode": "subscribe", "hub.verify_token": "local-verify",
                                     "hub.challenge": "004381"}), (200, b"004381"))

    def test_bad_challenge(self):
        """Reject incorrect subscription tokens."""
        self.assertEqual(call(query={"hub.mode": "subscribe", "hub.verify_token": "wrong",
                                     "hub.challenge": "004381"})[0], 403)

    def test_invalid_signature(self):
        """Reject modified UTF-8 bytes and missing signatures before parsing."""
        body = envelope([text("invalid")])
        sig = "sha256=" + hmac.new(b"local-app-secret", body, hashlib.sha256).hexdigest()
        self.assertEqual(call(body + b" ", signature=sig)[0], 403)
        self.assertEqual(call(body, signature="")[0], 403)

    def test_malformed(self):
        """Reject malformed JSON and invalid message bodies or entry arrays."""
        for body in [b"{", b'{"object":"whatsapp_business_account","entry":4}',
                     envelope([{**text("broken"), "text": {"body": 12}}])]:
            with self.subTest(body=body):
                self.assertEqual(call(body)[0], 400)

    def test_other_phone(self):
        """An event for another configured business number is acknowledged and skipped."""
        self.assertEqual(call(envelope([text("ignored")], phone="99")), (200, b"ok"))

    def test_non_text_event(self):
        """Acknowledge media and status notifications without queuing text."""
        self.assertEqual(call(envelope([{"type": "image"}])), (200, b"ok"))
        data = json.loads(envelope([]))
        value = data["entry"][0]["changes"][0]["value"]
        del value["messages"]
        value["statuses"] = [{"status": "delivered"}]
        self.assertEqual(call(json.dumps(data).encode()), (200, b"ok"))

    def test_request_size(self):
        """Reject empty input and payloads above the 3 MiB limit."""
        self.assertEqual(call(method="PATCH")[0], 405)
        self.assertEqual(call(url=URL + "/missing")[0], 404)
        self.assertEqual(call(b"")[0], 400)
        self.assertEqual(call(b"x" * (3 * 1024 * 1024 + 1))[0], 413)
