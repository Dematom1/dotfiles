#!/usr/bin/env python3
"""Small, offline-testable Miniflux to Kindle pilot.

The only delivery transport here is Resend SMTP. Amazon is reached only by
sending mail to the approved Send-to-Kindle address.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import html
import json
import mimetypes
import os
import re
import smtplib
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from email.message import EmailMessage
from email.policy import SMTP
from html.parser import HTMLParser
from pathlib import Path
from typing import Callable, Iterable, Sequence

RESEND_SMTP_HOST = "smtp.resend.com"
RESEND_SMTP_PORT = 587
RESEND_MAX_MESSAGE_BYTES = 40 * 1024 * 1024
DEFAULT_RETRY_ATTEMPTS = 3
DEFAULT_MAX_ATTENDED_BATCHES = 1
MAX_ATTENDED_BATCHES = 4
DEFAULT_STATE_PATH = Path.home() / ".local" / "state" / "kindle-pilot" / "state.json"
CONFIRMATION_PHRASE = "SEND TO KINDLE"
ALLOWED_MEDIA_TYPES = {"application/epub+zip", "application/pdf"}
MACOS_F_FULLFSYNC = 51
MAX_IMAGE_BYTES = 5 * 1024 * 1024


class PilotError(Exception):
    """Expected, user-actionable pilot failure."""


class UnsupportedMediaType(PilotError):
    pass


class OversizedDocument(PilotError):
    pass


class PendingDelivery(PilotError):
    pass


class DeliveryError(PilotError):
    def __init__(self, message: str, *, uncertain: bool):
        super().__init__(message)
        self.uncertain = uncertain


@dataclass(frozen=True)
class Document:
    article_id: str
    filename: str
    media_type: str
    payload: bytes

    def __post_init__(self) -> None:
        if not self.article_id:
            raise PilotError("Miniflux entry has no stable ID")
        if self.media_type not in ALLOWED_MEDIA_TYPES:
            raise UnsupportedMediaType(self.media_type)
        if not self.payload:
            raise PilotError("empty document")


@dataclass(frozen=True)
class RuntimeConfig:
    miniflux_url: str
    miniflux_token: str
    resend_api_key: str | None = None
    kindle_to: str | None = None
    kindle_from: str | None = None
    state_path: Path = DEFAULT_STATE_PATH
    max_message_bytes: int = RESEND_MAX_MESSAGE_BYTES


def _fsync_directory(path: Path) -> None:
    directory_fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _fsync_file(fd: int) -> None:
    os.fsync(fd)
    if sys.platform == "darwin":
        fcntl.fcntl(fd, MACOS_F_FULLFSYNC)


def _ensure_durable_directory(path: Path) -> None:
    missing: list[Path] = []
    current = path
    while not current.exists():
        missing.append(current)
        current = current.parent
    for directory in reversed(missing):
        try:
            directory.mkdir()
        except FileExistsError:
            if not directory.is_dir():
                raise
        _fsync_directory(directory.parent)


class Ledger:
    """Atomic JSON ledger. Delivered IDs are the idempotency boundary."""

    def __init__(self, path: Path):
        self.path = path
        self.delivered: dict[str, str] = {}
        self.last_successful_id: str | None = None
        self.pending: dict[str, object] | None = None

    @classmethod
    def load(cls, path: Path) -> "Ledger":
        ledger = cls(path)
        if not path.exists():
            return ledger
        try:
            data = json.loads(path.read_text())
            ledger.delivered = {str(k): str(v) for k, v in data.get("delivered", {}).items()}
            value = data.get("last_successful_id")
            ledger.last_successful_id = None if value is None else str(value)
            pending = data.get("pending")
            ledger.pending = pending if isinstance(pending, dict) else None
        except (OSError, ValueError, TypeError) as exc:
            raise PilotError("ledger is unreadable; no delivery attempted") from exc
        return ledger

    def save(self) -> None:
        _ensure_durable_directory(self.path.parent)
        payload = {
            "version": 1,
            "delivered": self.delivered,
            "last_successful_id": self.last_successful_id,
            "pending": self.pending,
        }
        fd, temporary = tempfile.mkstemp(prefix=".state.", dir=self.path.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump(payload, stream, sort_keys=True)
                stream.write("\n")
                stream.flush()
                _fsync_file(stream.fileno())
            os.replace(temporary, self.path)
            _fsync_directory(self.path.parent)
        except OSError:
            try:
                os.unlink(temporary)
            except OSError:
                pass
            raise

    def new_documents(self, documents: Iterable[Document]) -> list[Document]:
        return [document for document in documents if document.article_id not in self.delivered]

    def prepare(self, batch: Sequence[Document]) -> None:
        if self.pending is not None:
            raise PendingDelivery("a previous batch needs attended reconciliation")
        self.pending = {
            "batch_id": batch_id(batch),
            "article_ids": [document.article_id for document in batch],
        }
        self.save()

    def clear_pending(self) -> None:
        self.pending = None
        self.save()

    def commit(self, batch: Sequence[Document]) -> None:
        now = str(int(time.time()))
        for document in batch:
            self.delivered[document.article_id] = now
        if batch:
            self.last_successful_id = batch[-1].article_id
        self.pending = None
        self.save()


class MinifluxClient:
    def __init__(self, base_url: str, token: str, opener: Callable[..., object] | None = None):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.opener = opener or urllib.request.urlopen

    def list_starred(self) -> list[dict[str, object]]:
        entries: list[dict[str, object]] = []
        offset = 0
        limit = 100
        while True:
            query = urllib.parse.urlencode({"starred": "true", "limit": limit, "offset": offset})
            request = urllib.request.Request(
                f"{self.base_url}/v1/entries?{query}",
                headers={"X-Auth-Token": self.token, "Accept": "application/json"},
            )
            try:
                with self.opener(request, timeout=30) as response:
                    body = json.loads(response.read())
            except (OSError, ValueError, urllib.error.URLError) as exc:
                raise PilotError("Miniflux request failed; no delivery attempted") from exc
            page = body.get("entries", [])
            if not isinstance(page, list):
                raise PilotError("Miniflux returned an invalid entries response")
            entries.extend(item for item in page if isinstance(item, dict))
            if len(page) < limit:
                return entries
            offset += len(page)


def _env(name: str, *, required: bool = True) -> str | None:
    value = os.environ.get(name)
    if required and not value:
        raise PilotError(f"required runtime setting is missing: {name}")
    return value


def runtime_config(*, require_delivery: bool) -> RuntimeConfig:
    try:
        max_message = int(os.environ.get("RESEND_MAX_MESSAGE_BYTES", RESEND_MAX_MESSAGE_BYTES))
    except ValueError as exc:
        raise PilotError("RESEND_MAX_MESSAGE_BYTES must be an integer") from exc
    if max_message <= 0:
        raise PilotError("RESEND_MAX_MESSAGE_BYTES must be positive")
    if max_message > RESEND_MAX_MESSAGE_BYTES:
        raise PilotError(f"RESEND_MAX_MESSAGE_BYTES must not exceed {RESEND_MAX_MESSAGE_BYTES}")
    config = RuntimeConfig(
        miniflux_url=_env("MINIFLUX_URL") or "",
        miniflux_token=_env("MINIFLUX_API_TOKEN") or "",
        state_path=Path(os.environ.get("KINDLE_PILOT_STATE", DEFAULT_STATE_PATH)),
        max_message_bytes=max_message,
    )
    if require_delivery:
        return RuntimeConfig(
            miniflux_url=config.miniflux_url,
            miniflux_token=config.miniflux_token,
            resend_api_key=_env("RESEND_API_KEY"),
            kindle_to=_env("KINDLE_TO_ADDRESS"),
            kindle_from=_env("KINDLE_FROM_ADDRESS"),
            state_path=config.state_path,
            max_message_bytes=config.max_message_bytes,
        )
    return config


def _validate_fetch_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise PilotError("remote document and image URLs must use HTTPS")


def _fetch_bytes(url: str, max_bytes: int = RESEND_MAX_MESSAGE_BYTES) -> bytes:
    _validate_fetch_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "kindle-pilot/1"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            _validate_fetch_url(response.geturl())
            payload = response.read(max_bytes + 1)
    except (OSError, urllib.error.URLError) as exc:
        raise PilotError("article or image fetch failed") from exc
    if len(payload) > max_bytes:
        raise PilotError("remote document or image exceeds the download limit")
    return payload


def _xml_safe(value: object) -> str:
    return "".join(
        character
        for character in str(value)
        if character in "\t\n\r"
        or "\x20" <= character <= "\ud7ff"
        or "\ue000" <= character <= "\ufffd"
        or "\U00010000" <= character <= "\U0010ffff"
    )


def _clean_text(value: object, fallback: str = "Untitled") -> str:
    text = re.sub(r"\s+", " ", _xml_safe(html.unescape(str(value or "")))).strip()
    return text or fallback


def _author(entry: dict[str, object]) -> str:
    value = entry.get("author") or entry.get("authors") or ""
    if isinstance(value, list):
        value = ", ".join(str(item.get("name", item)) if isinstance(item, dict) else str(item) for item in value)
    return _clean_text(value, "")


def _slug(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9]+", "-", value).strip("-").lower()
    return (slug[:80] or "article")


class _ArticleParser(HTMLParser):
    allowed = {"p", "div", "article", "section", "h1", "h2", "h3", "h4", "blockquote", "ul", "ol", "li", "strong", "b", "em", "i", "code", "pre", "br", "a"}
    block = {"p", "div", "article", "section", "h1", "h2", "h3", "h4", "blockquote", "ul", "ol", "li", "pre"}

    def __init__(self, base_url: str):
        super().__init__(convert_charrefs=True)
        self.base_url = base_url
        self.parts: list[str] = []
        self.images: list[tuple[str, str, str]] = []
        self.open_tags: list[str] = []
        self.skip_depth = 0

    def _close_through(self, tag: str) -> None:
        if tag not in self.open_tags:
            return
        while self.open_tags:
            closing = self.open_tags.pop()
            self.parts.append(f"</{closing}>")
            if closing in self.block:
                self.parts.append("\n")
            if closing == tag:
                return

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "iframe"}:
            self.skip_depth += 1
            return
        if self.skip_depth:
            return
        if tag in self.block and "p" in self.open_tags:
            self._close_through("p")
        if tag == "li" and "li" in self.open_tags:
            self._close_through("li")
        if tag in {"h1", "h2", "h3", "h4"}:
            for open_tag in reversed(self.open_tags):
                if open_tag in {"h1", "h2", "h3", "h4"}:
                    self._close_through(open_tag)
                    break
        attributes = dict(attrs)
        if tag == "img" and attributes.get("src"):
            source = urllib.parse.urljoin(self.base_url, _xml_safe(attributes["src"] or ""))
            marker = f"__KINDLE_IMAGE_{len(self.images)}__"
            alt = html.escape(_xml_safe(attributes.get("alt") or "image"), quote=True)
            self.images.append((marker, source, alt))
            self.parts.append(marker)
        elif tag == "br":
            self.parts.append("<br />")
        elif tag == "a" and attributes.get("href"):
            href = html.escape(urllib.parse.urljoin(self.base_url, _xml_safe(attributes["href"] or "")), quote=True)
            self.parts.append(f'<a href="{href}">')
        elif tag in self.allowed:
            self.parts.append(f"<{tag}>")
        if tag in self.allowed and tag != "br":
            self.open_tags.append(tag)
        if tag in self.block:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"script", "style", "noscript", "iframe"}:
            self.skip_depth = max(0, self.skip_depth - 1)
            return
        if self.skip_depth:
            return
        if tag in self.allowed and tag != "br":
            self._close_through(tag)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_data(self, data: str) -> None:
        if not self.skip_depth:
            self.parts.append(html.escape(_xml_safe(data)))

    @property
    def body(self) -> str:
        closing = [f"</{tag}>" for tag in reversed(self.open_tags)]
        return "".join(self.parts + closing).strip()


def _image_type(url: str, payload: bytes) -> tuple[str, str] | None:
    if payload.startswith(b"\x89PNG"):
        return "image/png", ".png"
    if payload.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", ".jpg"
    if payload.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif", ".gif"
    guessed = mimetypes.guess_type(urllib.parse.urlparse(url).path)[0]
    if guessed in {"image/png", "image/jpeg", "image/gif"}:
        return guessed, {"image/png": ".png", "image/jpeg": ".jpg", "image/gif": ".gif"}[guessed]
    return None


def article_to_epub(entry: dict[str, object], fetcher: Callable[[str], bytes] | None = None) -> Document:
    title = _clean_text(entry.get("title"))
    author = _author(entry)
    source_url = _xml_safe(entry.get("url") or "")
    language = _clean_text(entry.get("language"), "en")
    if not re.fullmatch(r"[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*", language):
        language = "en"
    content = entry.get("content", "")
    fetch = fetcher or _fetch_bytes
    parser = _ArticleParser(source_url)
    parser.feed(content.decode(errors="replace") if isinstance(content, bytes) else str(content))
    fallback_content = _clean_text(content, "No article content.")
    body = parser.body or f"<p>{html.escape(fallback_content)}</p>"
    image_files: list[tuple[str, str, bytes, str]] = []
    for marker, image_url, alt in parser.images:
        try:
            image = _fetch_bytes(image_url, MAX_IMAGE_BYTES) if fetcher is None else fetch(image_url)
            image_info = _image_type(image_url, image)
        except PilotError:
            image_info = None
            image = b""
        if image_info is None or len(image) > MAX_IMAGE_BYTES:
            body = body.replace(marker, "")
            continue
        media_type, extension = image_info
        filename = f"image-{len(image_files) + 1}{extension}"
        body = body.replace(marker, f'<img src="../images/{filename}" alt="{alt}" />')
        image_files.append((filename, media_type, image, image_url))

    escaped_title = html.escape(title)
    escaped_author = html.escape(author)
    source_link = html.escape(source_url, quote=True)
    creator = f'<dc:creator id="creator">{escaped_author}</dc:creator>' if author else ""
    source_meta = f'<dc:source>{source_link}</dc:source>' if source_url else ""
    modified = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    manifest_images = "".join(
        f'<item id="image-{index + 1}" href="../images/{html.escape(name, quote=True)}" media-type="{media}" />'
        for index, (name, media, _, _) in enumerate(image_files)
    )
    opf = f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="book-id" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:kindle-pilot:{hashlib.sha256(title.encode()).hexdigest()}</dc:identifier>
    <dc:title>{escaped_title}</dc:title>
    <dc:language>{html.escape(language)}</dc:language>
    {creator}
    {source_meta}
    <meta property="dcterms:modified">{modified}</meta>
  </metadata>
  <manifest>
    <item id="content" href="content.xhtml" media-type="application/xhtml+xml" />
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav" />
    <item id="styles" href="styles.css" media-type="text/css" />
    {manifest_images}
  </manifest>
  <spine><itemref idref="content" /></spine>
</package>'''
    nav = f'''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><h1>Contents</h1><ol><li><a href="content.xhtml">{escaped_title}</a></li></ol></nav></body></html>'''
    xhtml = f'''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{escaped_title}</title><link rel="stylesheet" type="text/css" href="styles.css" /></head>
<body><h1>{escaped_title}</h1>{f'<p class="author">{escaped_author}</p>' if author else ''}<p class="source">{f'<a href="{source_link}">Source</a>' if source_url else ''}</p>{body}</body></html>'''
    output = tempfile.SpooledTemporaryFile(max_size=8 * 1024 * 1024)
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr("META-INF/container.xml", '''<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml" /></rootfiles></container>''')
        archive.writestr("OEBPS/content.opf", opf)
        archive.writestr("OEBPS/nav.xhtml", nav)
        archive.writestr("OEBPS/content.xhtml", xhtml)
        archive.writestr("OEBPS/styles.css", "body { font-family: serif; line-height: 1.45; } img { max-width: 100%; } .source { font-size: .8em; }")
        for name, _, image, _ in image_files:
            archive.writestr(f"images/{name}", image)
    output.seek(0)
    return Document(str(entry.get("id", "")), f"{_slug(title)}.epub", "application/epub+zip", output.read())


def article_to_document(entry: dict[str, object], fetcher: Callable[[str], bytes] | None = None) -> Document:
    if not entry.get("id"):
        raise PilotError("Miniflux entry has no stable ID")
    media_type = str(entry.get("media_type") or entry.get("mime_type") or entry.get("content_type") or "").lower()
    url = str(entry.get("url") or "")
    path = urllib.parse.urlparse(url).path.lower()
    if media_type in {"application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/msword"} or path.endswith((".doc", ".docx")):
        raise UnsupportedMediaType("DOC/DOCX is outside the EPUB/PDF pilot boundary")
    content = entry.get("content", "")
    if media_type == "application/pdf" or path.endswith(".pdf") or (isinstance(content, bytes) and content.startswith(b"%PDF-")):
        if not isinstance(content, bytes) and not url:
            raise UnsupportedMediaType("PDF source has no URL or inline content")
        payload = content if isinstance(content, bytes) and content.startswith(b"%PDF-") else (fetcher(url) if fetcher else _fetch_bytes(url))
        if not payload.startswith(b"%PDF-"):
            raise UnsupportedMediaType("PDF source did not return a PDF")
        title = _slug(_clean_text(entry.get("title")))
        return Document(str(entry.get("id", "")), f"{title}.pdf", "application/pdf", payload)
    return article_to_epub(entry, fetcher)


def build_message(batch: Sequence[Document], sender: str, recipient: str, *, subject: str | None = None) -> EmailMessage:
    message = EmailMessage(policy=SMTP)
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = subject or f"Kindle digest ({len(batch)} item{'s' if len(batch) != 1 else ''})"
    message.set_content("Documents prepared by the local Kindle pilot.")
    for document in batch:
        subtype = document.media_type.split("/", 1)[1]
        message.add_attachment(document.payload, maintype="application", subtype=subtype, filename=document.filename)
    return message


def message_size(batch: Sequence[Document], sender: str = "sender", recipient: str = "recipient") -> int:
    return len(build_message(batch, sender, recipient).as_bytes())


def split_batches(documents: Sequence[Document], max_message_bytes: int, sender: str = "sender", recipient: str = "recipient") -> list[list[Document]]:
    if max_message_bytes <= 0:
        raise PilotError("message limit must be positive")
    batches: list[list[Document]] = []
    current: list[Document] = []
    for document in documents:
        if message_size([document], sender, recipient) > max_message_bytes:
            raise OversizedDocument(f"{document.filename} exceeds the configured email limit")
        candidate = current + [document]
        if current and message_size(candidate, sender, recipient) > max_message_bytes:
            batches.append(current)
            current = [document]
        else:
            current = candidate
    if current:
        batches.append(current)
    return batches


def batch_id(batch: Sequence[Document]) -> str:
    digest = hashlib.sha256()
    for document in batch:
        digest.update(document.article_id.encode())
        digest.update(hashlib.sha256(document.payload).digest())
    return digest.hexdigest()


class ResendSMTP:
    def __init__(self, api_key: str):
        self.api_key = api_key

    def send(self, message: EmailMessage) -> None:
        attempted = False
        smtp: smtplib.SMTP | None = None
        try:
            smtp = smtplib.SMTP(RESEND_SMTP_HOST, RESEND_SMTP_PORT, timeout=30)
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login("resend", self.api_key)
            attempted = True
            refused = smtp.send_message(message)
            if refused:
                raise DeliveryError("SMTP refused a recipient; pending batch preserved", uncertain=True)
        except DeliveryError:
            raise
        except smtplib.SMTPAuthenticationError as exc:
            raise DeliveryError("Resend SMTP authentication failed", uncertain=False) from exc
        except (OSError, smtplib.SMTPException) as exc:
            raise DeliveryError("Resend SMTP delivery failed", uncertain=attempted) from exc
        finally:
            if smtp is not None:
                try:
                    smtp.quit()
                except smtplib.SMTPException:
                    pass


def send_with_retries(sender: object, message: EmailMessage, attempts: int = DEFAULT_RETRY_ATTEMPTS, sleep: Callable[[float], None] = time.sleep) -> None:
    if attempts < 1:
        raise PilotError("retry attempts must be positive")
    for attempt in range(attempts):
        try:
            sender.send(message)
            return
        except DeliveryError as exc:
            if exc.uncertain or attempt == attempts - 1:
                raise
            sleep(min(2 ** attempt, 8))


def require_attended_confirmation(live_send: bool, confirmation: str | None, *, is_tty: bool | None = None) -> None:
    if not live_send:
        return
    if is_tty is None:
        is_tty = sys.stdin.isatty() and sys.stdout.isatty()
    if not is_tty:
        raise PilotError("live delivery requires an attended terminal")
    if confirmation != CONFIRMATION_PHRASE:
        raise PilotError("live delivery requires the exact confirmation phrase")


def deliver_batches(ledger: Ledger, batches: Sequence[Sequence[Document]], sender: object) -> int:
    sent = 0
    for batch in batches:
        message = sender.message(batch) if hasattr(sender, "message") else None
        if message is None:
            raise PilotError("sender must provide a message")
        ledger.prepare(batch)
        try:
            send_with_retries(sender, message)
        except DeliveryError as exc:
            if not exc.uncertain:
                ledger.clear_pending()
            raise
        ledger.commit(batch)
        sent += 1
    return sent


class SMTPBatchSender:
    def __init__(self, api_key: str, sender: str, recipient: str):
        self.transport = ResendSMTP(api_key)
        self.sender = sender
        self.recipient = recipient

    def message(self, batch: Sequence[Document]) -> EmailMessage:
        return build_message(batch, self.sender, self.recipient)

    def send(self, message: EmailMessage) -> None:
        self.transport.send(message)


@contextmanager
def ledger_lock(state_path: Path):
    lock_path = state_path.with_name(f"{state_path.name}.lock")
    _ensure_durable_directory(lock_path.parent)
    with lock_path.open("a+") as stream:
        os.chmod(lock_path, 0o600)
        fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def clear_pending_for_retry(batch_id_value: str, *, is_tty: bool | None = None) -> int:
    if is_tty is None:
        is_tty = sys.stdin.isatty() and sys.stdout.isatty()
    if not is_tty:
        raise PilotError("pending reconciliation requires an attended terminal")
    state_path = Path(os.environ.get("KINDLE_PILOT_STATE", DEFAULT_STATE_PATH))
    with ledger_lock(state_path):
        ledger = Ledger.load(state_path)
        if ledger.pending is None:
            raise PilotError("there is no pending batch to reconcile")
        pending_batch_id = ledger.pending.get("batch_id")
        if not isinstance(pending_batch_id, str) or batch_id_value != pending_batch_id:
            raise PilotError("pending batch ID does not match")
        ledger.clear_pending()
    print("kindle-pilot: pending batch cleared for retry; run a dry-run next")
    return 0


def run(*, live_send: bool, confirmation: str | None, max_batches: int = DEFAULT_MAX_ATTENDED_BATCHES, is_tty: bool | None = None) -> int:
    require_attended_confirmation(live_send, confirmation, is_tty=is_tty)
    if max_batches < 1 or max_batches > MAX_ATTENDED_BATCHES:
        raise PilotError(f"max attended batches must be between 1 and {MAX_ATTENDED_BATCHES}")
    config = runtime_config(require_delivery=live_send)
    with ledger_lock(config.state_path):
        ledger = Ledger.load(config.state_path)
        if ledger.pending is not None:
            raise PendingDelivery("a previous batch needs attended reconciliation")
        entries = MinifluxClient(config.miniflux_url, config.miniflux_token).list_starred()
        new_entries = [entry for entry in entries if str(entry.get("id", "")) not in ledger.delivered]
        documents = [article_to_document(entry) for entry in new_entries]
        if not documents:
            print("kindle-pilot: no new starred items")
            return 0
        sender_name = config.kindle_from or "dry-run sender"
        recipient = config.kindle_to or "dry-run recipient"
        batches = split_batches(documents, config.max_message_bytes, sender_name, recipient)
        if not live_send:
            print(f"kindle-pilot: prepared {len(documents)} item(s) in {len(batches)} batch(es); no send performed")
            return 0
        sender = SMTPBatchSender(config.resend_api_key or "", config.kindle_from or "", config.kindle_to or "")
        batches_to_send = batches[:max_batches]
        deliver_batches(ledger, batches_to_send, sender)
        delivered_documents = sum(len(batch) for batch in batches_to_send)
        deferred_documents = len(documents) - delivered_documents
        print(f"kindle-pilot: delivered {delivered_documents} item(s) in {len(batches_to_send)} batch(es)")
        if deferred_documents:
            print(f"kindle-pilot: deferred {deferred_documents} item(s); run another attended confirmation")
    return 0


def main(argv: Sequence[str] | None = None, *, is_tty: bool | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prepare starred Miniflux items for the approved Kindle address")
    parser.add_argument("--dry-run", action="store_true", help="prepare only; this is the default")
    parser.add_argument("--live-send", action="store_true", help="send one attended, explicitly confirmed pilot run")
    parser.add_argument("--confirm-send", help=f"must equal {CONFIRMATION_PHRASE!r} for live delivery")
    parser.add_argument("--clear-pending-for-retry", metavar="BATCH_ID", help="attended local-ledger reconciliation for an exact pending batch")
    parser.add_argument("--max-batches", type=int, default=DEFAULT_MAX_ATTENDED_BATCHES, help="live-send batch bound (1 by default, at most 4)")
    args = parser.parse_args(argv)
    selected_actions = sum((args.dry_run, args.live_send, args.clear_pending_for_retry is not None))
    if selected_actions > 1:
        parser.error("--dry-run, --live-send, and --clear-pending-for-retry cannot be combined")
    if args.max_batches < 1 or args.max_batches > MAX_ATTENDED_BATCHES:
        parser.error(f"--max-batches must be between 1 and {MAX_ATTENDED_BATCHES}")
    try:
        if args.clear_pending_for_retry is not None:
            return clear_pending_for_retry(args.clear_pending_for_retry, is_tty=is_tty)
        return run(live_send=args.live_send, confirmation=args.confirm_send, max_batches=args.max_batches, is_tty=is_tty)
    except PendingDelivery as exc:
        print(f"kindle-pilot: {exc}", file=sys.stderr)
        return 2
    except PilotError as exc:
        print(f"kindle-pilot: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
