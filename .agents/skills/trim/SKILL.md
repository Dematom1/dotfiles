---
name: trim
description: Trim the ship - improve how firstmate runs for this captain. Audit opt-in settings and recent work against what actually happened here, find where firstmate itself lost time, and recommend flags to toggle or firstmate improvements. Use on /trim, /trim 24h, "trim the ship", or after /updatefirstmate. Read-only until the captain picks.
---

# trim

Trim improves firstmate itself for this captain. Firstmate ships most new behavior as opt-in, so a home can miss settings that would have prevented its own problems. Trim compares what is available with what this home runs and what actually went wrong here, then recommends a short list of flags to toggle and firstmate improvements.

Nothing changes until the captain picks. Every suggestion needs evidence from this home.

## Steps

1. **Inventory.** Read `docs/configuration.md` from this home's code root, the source of truth, so the skill stays current on its own. List each setting, its file or variable, its default, and what it changes. Never work from memory or a hardcoded list.
2. **Current state.** List `config/` for this home and each registered second mate in `data/secondmates.md`. Report names only: never print a config value that could hold a credential. Note settings inherited from the primary, per `fm_config_inherit_items` in `bin/fm-config-inherit-lib.sh`.
3. **Evidence.** Look for what really happened here in the last 14 days: `state/*.status`, `bin/fm-branch-outcome.sh list`, `data/learnings.md`, `data/captain.md`, `data/captain-shared.md`, and recent reports under `data/`. Count stalls, missed comments, stale workers, overload, failed checks, and manual steps repeated by hand.
4. **Match.** Pair each unused setting with evidence it would have helped. Drop anything with no evidence, or that repeats a choice the captain already made in `data/captain.md` or `data/captain-shared.md`. Also flag settings that are on and did nothing.
5. **Look forward.** Search this home's history for patterns worth changing in how work is done, not only in settings: `data/*/report.md`, `state/*.status`, `bin/fm-branch-outcome.sh list`, the backlog, and session transcripts when readable. Look for corrections the captain repeated, the same failure in different places, decisions made twice, and manual steps done again and again. Recommend updates for work going forward, such as a rule, a check, or a tool. Count how often each pattern occurred.
6. **Rank and report.** At most eight, highest impact first, settings and work-going-forward updates together. For each give: the recommendation, what it does in plain words, your reasoning (why this home, why now, and what would happen without it), the evidence with dates, PR links and file:line citations a reader can open, the cost or risk, exactly how to turn it on, and how to undo it. Say how strong the evidence is, and never recommend from a single unverified event. Then list what you considered and dropped, with the reason, in one line each.
7. **Wait for the captain's picks.** Apply only those, through the documented path for that setting, then verify the effect and say what you verified. `bin/fm-config-push.sh` carries inherited settings to second mates.

## Velocity audit

`/trim 24h`, or any window such as `/trim 7d`, audits recent development work instead of every setting: identify where firstmate itself slowed the captain's velocity in that window, and propose flags to toggle or firstmate improvements.

- Stay on firstmate: how it dispatched, supervised, routed, escalated and recovered. A slow test suite in a project or a hard product decision is out of scope unless firstmate made it worse.
- Measure where firstmate lost time: unread instructions, stalled second mates or workers, notifications that needed no one, decisions asked twice, work with no owner, rework caused by supervision, queues behind a busy mate, and captain time spent on things firstmate could have done. Build the timeline from status timestamps and PR history, and quote real durations.
- Rank by time lost, not by count. Name the biggest three, then what would have shortened each: first a flag to toggle, then a rule in the captain's preferences, then a firstmate improvement to propose.
- A firstmate improvement is a short local draft: the gap, the evidence, and the smallest change. Publishing it upstream needs the captain's word for that one contribution.
- Reasoning and evidence rules are the same as the full run. Same read-only boundary.

At the end of every run, and after `/updatefirstmate`, offer this exact next step: "Want me to audit your development work in the last 24h, identify firstmate bottlenecks or improvements that slowed your velocity, and propose suggestions or flags to toggle?"

## Boundaries

- Read-only by default. Never change a setting because it seems obviously good.
- Anything touching credentials, account pins, spend, merge authority or security is called out as such, and account pins are always the captain's own edit.
- Do not make firstmate code changes here. A gap no setting covers is a work-going-forward recommendation, not a change.
- Record what the captain declined in `data/captain.md` with the reason, so the next run does not ask again.
