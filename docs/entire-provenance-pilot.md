# Entire provenance pilot

This repository keeps the local task database as the source of outcome and cost metrics. Entire is provenance-only: it records agent sessions and links them to commits.

## Pilot setup

Enable Entire only in a local checkout with the Pi integration and telemetry disabled:

```sh
ENTIRE_TELEMETRY_OPTOUT=1 entire enable --agent pi --local --telemetry=false
entire status
```

The local settings file is ignored. No checkpoint remote is configured, and this pilot does not push checkpoint data or expand to another repository.

## Verification

Use a new Pi session after enabling Entire. For the redaction check, put synthetic credential-like values only in the session prompt, then make and commit a harmless documentation change. Inspect the resulting checkpoint metadata and transcript:

```sh
entire checkpoint list
entire checkpoint explain CHECKPOINT_ID

git show-ref | grep 'entire/checkpoints' || true
git show ENTIRE_CHECKPOINT_REF:path/to/metadata.json
```

The synthetic token, password, and credentialed URI must be replaced by `REDACTED`; do not use real credentials. The normal commit must contain an `Entire-Checkpoint` trailer and the checkpoint must identify the session:

```sh
git show -s --format=%B HEAD
git show -s --format='%H %s' HEAD
```

Record repository growth before and after the pilot with the same commands. Entire checkpoint growth is Git data, not a task outcome or cost metric:

```sh
du -sk . "$(git rev-parse --git-common-dir)"
git count-objects -vH
git for-each-ref --format='%(refname) %(objectname)' 'refs/entire' 'refs/heads/entire'
```

The completed pilot was measured from clean baseline commit `62909dfb96c75599650e34da3e1afd46898815e2` to pilot commit `814b52bc487d81361644eb5ccb8214392705ba36`. The deterministic reachable-object comparison reported 0 pilot-only objects at baseline and 10 at the pilot commit: 1 commit, 6 trees, and 3 blobs, totaling 9,018 logical bytes and 5,992 loose-object bytes on disk. The latter is Git's local object encoding, so it can change after repacking even though the logical total does not.

Checkpoint discovery reported 0 checkpoints at both commits and therefore 0 bytes of retained checkpoint growth. The pilot commit retains the verified `Entire-Checkpoint: 01M0R8220JGCDCFHZHCMFE22J2` linkage, but after the required non-destructive disable the local CLI reports that Entire is not set up and no checkpoint ref is discoverable. The measurement therefore covers retained Git data only; it does not reconstruct or estimate transient session data. The redaction verification used synthetic credential-like values only.

## Disable and rollback

Normal disable stops new capture and preserves existing session data:

```sh
entire disable --local
```

A clean rollback is destructive because it removes Entire settings, hooks, agent hooks, session state, and shadow branches. Run it only after explicitly deciding that the captured pilot data is no longer needed:

```sh
entire disable --local --uninstall --force
```

Do not manually edit Git hooks or delete checkpoint refs. Re-enable the local pilot with the documented `entire enable` command above if the rollback is reversed.
