---
name: trim
description: Trim the ship - audit Firstmate settings and recent work against what happened here, then recommend toggles or improvements. Use only on an explicit trim request such as /trim, /trim 24h, or "trim the ship". Read-only except trim records until the captain picks.
---

# trim

Trim improves Firstmate for this captain. Compare the complete configuration reference with this home's settings and verified incidents. Every suggestion needs evidence from this home.

Invoke only on an explicit trim request. Never run or offer trim after unrelated commands, including `/updatefirstmate`. Hand the report to the operator or supervisor when finished. Do not poll or wait for picks.

## Audit steps

1. **Read history and verify applied toggles first.** Use the active Firstmate home's `$FM_HOME/data/trim/`, not the project's data directory. Read all of `history.jsonl` before collecting new recommendations. A missing file means the first run. Resolve picks against their run and recommendation IDs. Re-run the recorded check for every applied toggle and record pass or fail with the check time and exit code. Review commands for safety before execution. Checks must be read-only, deterministic, and names-only. If a check is missing, unsafe, or cannot run, report fail with that reason, not an inferred pass. Never execute apply or undo commands during an audit. A failing applied toggle is a verification finding, not a new recommendation. Preserve prior decisions even when a check fails.
2. **Inventory the reference.** Read this home's complete `docs/configuration.md`, including every truncated continuation. List every setting, its file or variable, default, and effect in an appendix. Separate default-on, opt-in, inherited, generated, and internal or test-only controls. Do not hardcode an inventory or repeat the reference prose in the ranked findings.
3. **Snapshot current names.** List names in this home's `config/` and each authorized registered second mate's `config/`, using `data/secondmates.md`. Note inheritance per `fm_config_inherit_items` in `bin/fm-config-inherit-lib.sh`. Record each inventoried setting as present, absent, or unknown, separately from configured, armed, effective, or unknown activation status. Only documented presence flags turn on through presence. Filenames do not establish scalar values, valid allowlists, or environment overrides. Inspect documented activation-artifact names only. Mark credential-dependent and environment-dependent state unknown. Never probe the environment or read, print, or store config values.
4. **Freeze the evidence window.** Record one UTC cutoff and window start before collecting events. The default window is 14 days. Count dated events only within that fixed window. Label undated and cleaned-up evidence separately. Label live inventories as later snapshots with their observation times.
5. **Collect verified evidence.** Read live `state/*.status` and archived `data/<task>/status.log` and `status.<N>.log`, following the status-archive owner's layout and retention. Distinguish task incarnations. Do not count the source, parent mirror, and branch outcome as separate incidents. Use the documented `bin/fm-branch-outcome.sh list` with enough `--recent` rows to cover the window. Validate the oldest returned boundary and filter numeric epochs. The default 20 rows are not window-complete. Never mark outcomes read or processed. Also read `data/learnings.md`, `data/captain.md`, `data/captain-shared.md`, recent reports, the backlog's recorded answers, and readable session transcripts. Verify incidents case by case. Outcome rows are not failures, and repeated notifications are not separate incidents.
6. **Match and check prior decisions.** Pair unused settings with evidence they would have helped. Flag enabled settings that did nothing. Read earlier trim reports, history picks, captain preferences, and backlog answers. Never re-recommend a declined or applied item, even under a new ID or wording. An already-adopted suggestion is an outcome to verify. Re-list current names before ranking. Never overwrite an existing file using an old suggested command.
7. **Find improvements separately.** Look for repeated corrections, decisions asked twice, and recurring manual work. Before proposing a rule, check whether it already exists. If it does, propose a small executable check at its existing owner, or point to the already-owned repair. Do not propose the same policy again. A gap no setting covers is an improvement, not a toggle.
8. **Write the report and history.** Follow the report layout and record formats below. Rank at most eight new recommendations total, highest impact first within each section. Do not fill the limit without evidence. Give each recommendation a stable ID. Use the same ID for the same setting and proposed transition, or the same improvement, across runs. Compare substance as well as IDs when suppressing duplicates. Save the report, append one run JSON line, and hand off its path. Do not apply recommendations during the audit.

## Report layout

Open `report.md` with `## Toggles` and this table, one row per setting proposed for change. If none qualify, keep the header and say there are no new toggles. Put no code or workflow improvements in this table.

| ID | Setting | File or variable | Current state (present/absent/unknown) | Proposed state | Exact apply command | Exact undo command | Deterministic check |
| --- | --- | --- | --- | --- | --- | --- | --- |

Directly after the table, report **Prior applied-toggle checks**, before any new recommendation rationale. List every applied toggle with its ID, check command, check time, pass or fail, exit code, and safe failure reason. On the first run, say there are no applied toggles to check. Then give the run ID, UTC window boundaries, and snapshot times.

Follow with these sections:

- **Toggle evidence.** For each table row, explain what it does, why this home needs it now, what happens without it, evidence strength, and cost or risk. Include dates, full PR URLs, and file:line references. Never recommend from a single unverified event.
- **Improvements.** Keep code and workflow proposals here, with their IDs, evidence, reasoning, cost, smallest change, and apply, undo, and check commands. If an improvement needs design or approval before commands exist, record those commands as null and state why. Never present it as an actionable toggle.
- **Considered and dropped.** Give one line per item and the reason, including prior decisions and already-owned repairs.
- **Inventory appendix.** Include the exhaustive reference inventory and names-only snapshot, with presence and activation status kept separate. List missing evidence and audit completion calls here too.

For each toggle, provide copyable commands scoped to the correct home and an explicit expected check result. A check must prove the documented effect, not merely that the apply command exited successfully. Presence alone proves effect only for a documented presence flag. Commands must not contain or reveal config values. If safe exact apply, undo, or effect-check commands cannot be supplied without values or an environment probe, do not propose that toggle. Record the limitation under considered and dropped. Do not guess unknown state or replace existing scalar files.

## Trim records

The audit may create only `$FM_HOME/data/trim/<run-id>/report.md` and append to `$FM_HOME/data/trim/history.jsonl`, creating their parent directories if absent. Use a unique UTC-based run ID, including a collision suffix if needed. Never replace a report or rewrite history. Append each JSON object as one complete line with a JSON serializer, not interpolated shell text. Serialize appends if another trim session is writing. Invalid or incomplete history is a blocking error to report, not permission to discard prior decisions.

Each run line contains:

- `type: "run"`, `run_id`, `window_start_utc`, `cutoff_utc`, and `report`.
- `snapshot_at_utc` and a `snapshot` entry for every inventoried setting in each audited home: home name, setting name, file or variable name, presence (`present`, `absent`, or `unknown`), and activation (`configured`, `armed`, `effective`, or `unknown`). No values.
- `verifications` for every previously applied toggle: original run ID, recommendation ID, check command, checked-at UTC, and check result with pass or fail, exit code (null if not run), and a safe reason when needed.
- `recommendations`, each with `id`, `kind` (`toggle` or `improvement`), `setting` (null for improvements without a setting), `apply`, `undo`, `check`, `expected_result`, and `evidence_refs`. Toggle commands must be non-null. Improvements can use null as described above.

The later applying session appends a `type: "picks"` line linked to the original `run_id`. Each pick records `recommendation_id`, `decision` (`applied`, `declined`, or `deferred`), `applied_at_utc` (null unless applied), `check`, and `check_result`. Use pass or fail and an exit code, never raw command output. A failed application check still counts as an applied decision and must be rechecked on future runs. Deferred items are not approved. Record decline reasons here, not in captain preferences.

This short example uses a fictional documented presence flag, not a real recommendation. For that flag only, a zero-byte file enables it. All paths are names. The check's expected result is exit code 0 with no output.

```jsonl
{"type":"run","run_id":"20260717T120000Z","window_start_utc":"2026-07-03T12:00:00Z","cutoff_utc":"2026-07-17T12:00:00Z","report":"20260717T120000Z/report.md","snapshot_at_utc":"2026-07-17T12:01:00Z","snapshot":[{"home":"primary","setting":"example-flag","file_or_variable":"config/example-flag","presence":"absent","activation":"unknown"}],"verifications":[],"recommendations":[{"id":"example-flag-enable","kind":"toggle","setting":"example-flag","apply":"test ! -e \"$FM_HOME/config/example-flag\" && (set -C; : > \"$FM_HOME/config/example-flag\")","undo":"rm -- \"$FM_HOME/config/example-flag\"","check":"test -f \"$FM_HOME/config/example-flag\"","expected_result":"exit 0; no output","evidence_refs":["data/example/status.log:12"]}]}
{"type":"picks","run_id":"20260717T120000Z","picks":[{"recommendation_id":"example-flag-enable","decision":"applied","applied_at_utc":"2026-07-17T12:10:00Z","check":"test -f \"$FM_HOME/config/example-flag\"","check_result":{"status":"pass","exit_code":0}}]}
```

Never store config values in reports, snapshots, commands, reasons, check results, or evidence excerpts. Store only setting and artifact names, state labels, and evidence references. Do not capture raw environment listings or command output that could reveal values.

## Authorized picks, in a later session

When the captain picks, the applying session reads the saved run and current names again. Apply only selected items through the documented path, then run the saved effect check and append the picks line. Do not overwrite changed state using stale commands. Resolve any ambiguity with the captain before applying. `bin/fm-config-push.sh` carries inherited settings to second mates only when that propagation is authorized. Account pins remain the captain's own edit. The audit itself never applies settings or records preferences.

## Velocity audit

`/trim 24h`, or any explicit window such as `/trim 7d`, focuses on where Firstmate slowed development in that window. Keep the same history verification, names-only inventory, report layout, and read-only boundary.

- Stay on Firstmate's dispatch, supervision, routing, escalation, and recovery. A project's slow test suite or hard product decision is out of scope unless Firstmate made it worse.
- Build timelines from status timestamps and PR history. Quote real durations for unread instructions, stalled workers, unnecessary notifications, duplicate decisions, unowned work, supervision rework, busy-mate queues, and captain work Firstmate could have handled.
- Rank by time lost, not count. Name the biggest three bottlenecks, when evidence supports three. For each, consider an existing toggle before a missing rule, then a Firstmate improvement. Keep toggle and improvement recommendations in their separate report sections.
- Draft improvements locally as the gap, evidence, and smallest change. Publishing upstream requires the captain's approval for that contribution.

## Boundaries

- Read-only except the trim report and append-only history. Never change settings or preferences because a recommendation seems obviously good.
- Call out anything touching credentials, account pins, spend, merge authority, or security. Do not inspect secrets or probe environment values.
- Do not change Firstmate code here. Propose improvements separately.
- A read-only scout lists completion calls in its report and runs only read-only verification. Its supervising Firstmate performs any required captain-hold attestation. Recommendations alone need no held task. Do not call completion commands that write origin metadata during the audit.
