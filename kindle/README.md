# Local Kindle pilot

This pilot is for the newest Amazon Kindle Colorsoft (16 GB) on the `amazon.ca`
marketplace. It sends only to the approved Send-to-Kindle email address. It
never calls an Amazon endpoint.

## What is managed

- Miniflux is the feed intake. Star an item to flag it.
- `kindle-pilot` reads starred entries and keeps an atomic JSON ledger at
  `~/.local/state/kindle-pilot/state.json` (or `KINDLE_PILOT_STATE`). A delivered
  Miniflux entry is not delivered again, even if it remains starred.
- HTML entries become EPUB 3 documents with title, author, source link, and
  available PNG/JPEG/GIF images. PDF entries remain PDF. DOC/DOCX and other
  document lanes are rejected.
- Delivery uses Resend SMTP (`smtp.resend.com:587`) with one dedicated,
  authenticated sender. There is no Amazon integration and no Calibre-Web.
- The Nix/Home Manager launchd job runs dry-run preparation only. A live send
  always needs an attended terminal and the exact confirmation phrase.

## Miniflux setup

1. Run the existing Miniflux instance and create an API token with permission
   to read entries.
2. Set `MINIFLUX_URL` in the runtime environment to the instance URL.
3. Inject `MINIFLUX_API_TOKEN` from Automic Vault by name. Do not put its value
   in this repository, Nix, shell history, or logs.
4. Star one small article for the first dry run. The pilot does not unstar
   entries automatically, so the ledger remains the source of truth.

## Books and lawful catalogs

Keep the local Calibre library as the only book/document library for this
pilot. Use Calibre OPDS Client for authorized catalogs such as Standard Ebooks,
Project Gutenberg, OAPEN, DOAB, and other catalogs whose terms authorize the
access and download. Configure those catalogs in the client, not in this repo.
Keep imports to EPUB and PDF. Do not add Calibre-Web, a second library, or a
DOCX conversion lane.

## Resend and Amazon approval

1. In Resend, verify the sending domain and create one dedicated sender for
   this pilot. Use the Resend SMTP credentials, not an ad hoc mail server.
2. In the Amazon account for the `amazon.ca` marketplace, find Personal
   Document Settings, copy the device's Send-to-Kindle email address into the
   account's approved runtime secret, and add the dedicated Resend sender to
   the approved personal-document email list.
3. Keep both addresses in Automic Vault only:
   `KINDLE_TO_ADDRESS` is the approved device address and
   `KINDLE_FROM_ADDRESS` is the dedicated verified sender. Never commit or
   print their values.

Resend limits each email to 40 MB including attachment Base64 encoding. The
pilot measures the complete MIME message, splits batches before sending, and
rejects a single oversized document. It never silently drops an item or marks
an unsent item delivered.

## Nix and launchd operation

`home.nix` owns the executable link and the macOS launchd agent. The agent uses
Automic Vault names only and runs an hourly dry run. It does not send mail:

```text
av inject +MINIFLUX_URL +MINIFLUX_API_TOKEN -- kindle-pilot
```

The Nix launchd declaration supplies `--dry-run` and does not inject delivery
credentials. The command's default is also dry-run. Check the
prepared-item count in the launchd log or run manually:

```text
av inject +MINIFLUX_URL +MINIFLUX_API_TOKEN -- ~/.local/bin/kindle-pilot
```

No credential or address should appear in the output. The first validation is
complete when the command reports a prepared count and the ledger is unchanged.

## Attended live send

Do not run this from launchd, CI, or another unattended process. First inspect
the dry-run result and the starred items, then run one bounded batch from an
interactive terminal:

```text
av inject +MINIFLUX_URL +MINIFLUX_API_TOKEN +RESEND_API_KEY +KINDLE_TO_ADDRESS +KINDLE_FROM_ADDRESS -- \
  ~/.local/bin/kindle-pilot --live-send --confirm-send "SEND TO KINDLE"
```

The exact phrase, a TTY, and all three delivery settings are required. A live
run sends one batch by default and supports at most four explicitly requested
batches, so a confirmation cannot authorize an unbounded queue. It commits each
batch to the ledger only after Resend SMTP accepts it. A
transport error known to occur before transmission gets up to three total
attempts with bounded 1/2 second backoff between attempts. An uncertain SMTP
outcome leaves a pending batch in the ledger and stops future delivery until
it is checked by an attendee; it is never automatically resent and therefore
cannot silently create duplicate deliveries.

After confirming that Amazon did not receive the pending batch, copy its exact
`batch_id` from the local state file and clear it from an attended terminal:

```sh
KINDLE_PILOT_STATE="$HOME/.local/state/kindle-pilot/state.json" \
  "$HOME/.local/bin/kindle-pilot" --clear-pending-for-retry EXACT_BATCH_ID
```

This only clears the matching local pending marker. Run the normal dry-run next.
Any later live retry still requires a separate attended `--live-send` invocation
with the exact `SEND TO KINDLE` confirmation.

## Disable and rollback

- To disable scheduled preparation, remove the `launchd.agents.kindlePilot`
  declaration from `home.nix` and rebuild, or unload the generated user agent
  with the normal Home Manager launchd ownership flow. Do not create a second
  ad hoc daemon.
- To stop intake, remove the Miniflux token from Automic Vault and unstar the
  pilot entries. Keep the ledger if the pilot will resume; delete only after
  confirming that re-delivery is wanted.
- To roll back the code, revert the pilot commit and rebuild the previous Nix
  generation. Do not delete a pending ledger entry until the matching message
  outcome has been checked manually.
- Revoke the dedicated Resend API key and sender approval in Resend and Amazon
  if the pilot is retired.
