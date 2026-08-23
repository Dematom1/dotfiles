#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
PYTHONPATH="$repo" python3 - <<'PY'
from contextlib import redirect_stderr, redirect_stdout
from io import BytesIO, StringIO
from pathlib import Path
import os
import tempfile
import zipfile

from kindle import kindle_pilot as pilot


def expect(condition, message):
    if not condition:
        raise AssertionError(message)


# EPUB manifest and useful metadata stay intact, with image fetching fully offline.
image = b"\x89PNG\r\n\x1a\n" + b"image"
entry = {
    "id": 101,
    "title": "An Article",
    "author": "An Author",
    "url": "https://feed.invalid/article",
    "content": '<p>Useful text</p><img src="/cover.png" alt="Cover">',
}
document = pilot.article_to_document(entry, lambda url: image)
expect(document.media_type == "application/epub+zip", "HTML was not converted to EPUB")
with zipfile.ZipFile(BytesIO(document.payload)) as archive:
    names = set(archive.namelist())
    expect("mimetype" in names and "OEBPS/content.opf" in names, "EPUB manifest is incomplete")
    expect("images/image-1.png" in names, "available image was not included")
    body = archive.read("OEBPS/content.xhtml")
    expect(b"An Article" in body and b"An Author" in body, "EPUB metadata was not preserved")

# PDFs pass through unchanged; DOCX is deliberately outside the pilot boundary.
pdf = b"%PDF-1.7\ncontent"
pdf_document = pilot.article_to_document(
    {"id": 102, "title": "A PDF", "url": "https://feed.invalid/a.pdf"}, lambda url: pdf
)
expect(pdf_document.media_type == "application/pdf" and pdf_document.payload == pdf, "PDF was converted")
try:
    pilot.article_to_document({"id": 103, "title": "A Word file", "url": "https://feed.invalid/a.docx"})
except pilot.UnsupportedMediaType:
    pass
else:
    raise AssertionError("DOCX was accepted")

# MIME-size splitting never emits an oversized batch or silently drops a document.
documents = [pilot.Document(str(index), f"{index}.epub", "application/epub+zip", bytes([index]) * 100) for index in range(3)]
limit = pilot.message_size([documents[0]]) + 5
batches = pilot.split_batches(documents, limit)
expect([doc.article_id for batch in batches for doc in batch] == ["0", "1", "2"], "size split dropped or reordered documents")
expect(all(pilot.message_size(batch) <= limit for batch in batches), "size split exceeded the limit")
try:
    pilot.split_batches(documents, pilot.message_size([documents[0]]) - 1)
except pilot.OversizedDocument:
    pass
else:
    raise AssertionError("single oversized document was accepted")

# Successful retries commit once; a second run sees the durable ledger and sends nothing.
class Sender:
    def __init__(self):
        self.calls = 0

    def message(self, batch):
        return batch

    def send(self, message):
        self.calls += 1


with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "state.json"
    ledger = pilot.Ledger(path)
    sender = Sender()
    pilot.deliver_batches(ledger, [documents[:2]], sender)
    expect(sender.calls == 1 and ledger.pending is None, "successful delivery did not commit")
    retry_ledger = pilot.Ledger.load(path)
    remaining = retry_ledger.new_documents(documents[:2])
    expect(remaining == [], "delivered items were not idempotent")
    expect(sender.calls == 1, "retry duplicated a delivered batch")

# A known pre-transmission failure uses bounded backoff and commits nothing until success.
class FlakySender:
    def __init__(self):
        self.calls = 0

    def send(self, message):
        self.calls += 1
        if self.calls == 1:
            raise pilot.DeliveryError("not sent", uncertain=False)


flaky = FlakySender()
sleeps = []
pilot.send_with_retries(flaky, object(), attempts=3, sleep=sleeps.append)
expect(flaky.calls == 2 and sleeps == [1], "retry/backoff behavior changed")

# An uncertain SMTP outcome remains pending and is never automatically resent.
class UncertainSender(Sender):
    def send(self, message):
        self.calls += 1
        raise pilot.DeliveryError("uncertain", uncertain=True)


with tempfile.TemporaryDirectory() as directory:
    ledger = pilot.Ledger(Path(directory) / "state.json")
    uncertain = UncertainSender()
    try:
        pilot.deliver_batches(ledger, [documents[:1]], uncertain)
    except pilot.DeliveryError:
        pass
    else:
        raise AssertionError("uncertain delivery did not fail")
    expect(ledger.pending is not None, "uncertain delivery was not retained")
    try:
        pilot.deliver_batches(pilot.Ledger.load(ledger.path), [documents[:1]], uncertain)
    except pilot.PendingDelivery:
        pass
    else:
        raise AssertionError("pending delivery was retried automatically")
    expect(uncertain.calls == 1, "uncertain delivery duplicated")

# Runtime secret/address values do not leak through the public dry-run command.
secret = "re_" + "runtime-only"
address = "kindle" + "@" + "example.invalid"
with tempfile.TemporaryDirectory() as directory:
    original_environment = os.environ.copy()
    original_list_starred = pilot.MinifluxClient.list_starred
    os.environ.update({
        "MINIFLUX_URL": "https://miniflux.invalid/" + secret,
        "MINIFLUX_API_TOKEN": secret,
        "RESEND_API_KEY": secret,
        "KINDLE_TO_ADDRESS": address,
        "KINDLE_FROM_ADDRESS": "sender@example.invalid",
        "KINDLE_PILOT_STATE": str(Path(directory) / "state.json"),
    })
    pilot.MinifluxClient.list_starred = lambda self: []
    output = StringIO()
    try:
        with redirect_stdout(output), redirect_stderr(output):
            exit_code = pilot.main(["--dry-run"])
    finally:
        pilot.MinifluxClient.list_starred = original_list_starred
        os.environ.clear()
        os.environ.update(original_environment)
    expect(exit_code == 0 and "no new starred items" in output.getvalue(), "public dry-run failed")
    expect(secret not in output.getvalue() and address not in output.getvalue(), "dry-run output leaked runtime values")
    expect(not (Path(directory) / "state.json").exists(), "dry-run persisted delivery state")

# Delivered entries are filtered before conversion or remote asset fetching.
with tempfile.TemporaryDirectory() as directory:
    state_path = Path(directory) / "state.json"
    ledger = pilot.Ledger(state_path)
    ledger.delivered["old"] = "1"
    ledger.save()
    original_environment = os.environ.copy()
    original_list_starred = pilot.MinifluxClient.list_starred
    os.environ.update({
        "MINIFLUX_URL": "https://miniflux.invalid",
        "MINIFLUX_API_TOKEN": "token",
        "KINDLE_PILOT_STATE": str(state_path),
    })
    pilot.MinifluxClient.list_starred = lambda self: [
        {"id": "old", "title": "Unavailable PDF", "url": "https://feed.invalid/gone.pdf"},
        {"id": "new", "title": "New article", "content": "available"},
    ]
    output = StringIO()
    try:
        with redirect_stdout(output), redirect_stderr(output):
            exit_code = pilot.main(["--dry-run"])
    finally:
        pilot.MinifluxClient.list_starred = original_list_starred
        os.environ.clear()
        os.environ.update(original_environment)
    expect(exit_code == 0 and "prepared 1 item(s)" in output.getvalue(), "delivered entry was converted again")

# Invalid overrides cannot raise Resend's fixed request ceiling.
original_limit = os.environ.get("RESEND_MAX_MESSAGE_BYTES")
os.environ.update({"MINIFLUX_URL": "https://miniflux.invalid", "MINIFLUX_API_TOKEN": "token"})
os.environ["RESEND_MAX_MESSAGE_BYTES"] = str(pilot.RESEND_MAX_MESSAGE_BYTES + 1)
try:
    pilot.runtime_config(require_delivery=False)
except pilot.PilotError:
    pass
else:
    raise AssertionError("Resend request ceiling was overridden")
if original_limit is None:
    os.environ.pop("RESEND_MAX_MESSAGE_BYTES", None)
else:
    os.environ["RESEND_MAX_MESSAGE_BYTES"] = original_limit

# The live-send guard requires both an attended terminal and the exact phrase.
pilot.require_attended_confirmation(True, pilot.CONFIRMATION_PHRASE, is_tty=True)
try:
    pilot.run(live_send=False, confirmation=None, max_batches=pilot.MAX_ATTENDED_BATCHES + 1)
except pilot.PilotError:
    pass
else:
    raise AssertionError("live-send batch bound was not enforced")
for tty, phrase in ((False, pilot.CONFIRMATION_PHRASE), (True, "wrong")):
    try:
        pilot.require_attended_confirmation(True, phrase, is_tty=tty)
    except pilot.PilotError:
        pass
    else:
        raise AssertionError("live-send guard accepted an unsafe invocation")

print("kindle pilot tests: ok")
PY
