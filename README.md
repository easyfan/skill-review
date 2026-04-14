# skill-review

Skills/Agents Design Committee — systematic multi-dimensional quality review for Claude Code skill, agent, command, and SKILL.md files.

## What it does

`/skill-review` launches a three-stage review pipeline:

**Stage 1 (parallel)**: 4 specialist reviewers analyze target files simultaneously
- S1 Definition Quality: prompt clarity, model selection, tool set fit, description accuracy
- S2 Interaction Chain: orchestration patterns, data contracts, parallel/serial correctness
- S3 External Research: benchmarking against industry best practices (includes WebSearch)
- S4 Usability: UX, output format, error handling, progress feedback

**Stage 2 (serial)**:
- Challenger (opus): issues CONFIRM / DISPUTE / UNVERIFIABLE verdicts on P0/P1 findings
- Reporter: consolidated report + direct fixes for confirmed issues

**Stage 3 (conditional)**:
- Grader: auto-generates should-trigger / should-not-trigger assertions after description changes

Quality grades: 🔴 Unusable / 🟡 Usable with defects / 🟢 Production-ready / ⭐ Excellent

## Prerequisites

| Dependency | Required | Purpose |
|------------|----------|---------|
| [skill-shrinker](https://github.com/easyfan/skill-shrinker) | **Required** for files >400 lines | skill-review gates review entry at 400 lines and instructs users to run `/skill-shrink` first. Without skill-shrink installed, files >400 lines cannot be reviewed. |

Install skill-shrink before (or alongside) skill-review:

```bash
# Option A — marketplace
/plugin marketplace add easyfan/skill-shrinker
/plugin install skill-shrinker@latest

# Option B — script
git clone https://github.com/easyfan/skill-shrinker.git
bash skill-shrinker/install.sh
```

## Install

<!--
### Option A — npm (not yet published)

```bash
npm install -g skill-review
npx skill-review
```

### Option B — npx one-shot (not yet published)

```bash
npx skill-review
```
-->

### Option A — Claude Code plugin marketplace

Run inside a Claude Code session:

```
/plugin marketplace add easyfan/skill-review
/plugin install skill-review@skill-review
```

> ⚠️ **Partially covered by automated tests**: The underlying `claude plugin install` CLI path is verified by looper T2b (Plan B). The `/plugin` REPL entry point (interactive UI) cannot be tested via `claude -p` and must be verified manually in a Claude Code session.

### Option B — install script

```bash
git clone https://github.com/easyfan/skill-review.git
cd skill-review
bash install.sh
```

Install to a specific directory (`CLAUDE_DIR` takes priority over `--target=`):

```bash
CLAUDE_DIR=~/.claude bash install.sh
# or
bash install.sh --target=~/.claude
```

> ✅ **Verified**: covered by the skill-test pipeline (looper Stage 5).

### Option C — manual

```bash
cp commands/skill-review.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

Restart your Claude Code session after installation for agents to take effect.

> ✅ **Verified**: covered by the skill-test pipeline (looper Stage 5).

## Usage

```
/skill-review [target_list|all|all-commands|all-agents|all-skills]
```

**Examples:**

```bash
# Review all commands, agents, and skills
/skill-review all

# Review agents only
/skill-review all-agents

# Review skills only (~/.claude/skills/*/SKILL.md)
/skill-review all-skills

# Review a specific skill by name
/skill-review readme-i18n

# Review specific targets (comma-separated, no spaces)
/skill-review looper,patterns

# Lightweight quick-check (enter "stop" after Stage 1 to skip Challenger)
/skill-review looper
# → enter "stop" after Stage 1 completes
```

> **Skills** are identified by their directory name under `~/.claude/skills/` (e.g. `readme-i18n` maps to `~/.claude/skills/readme-i18n/SKILL.md`). The `model` and `tools` YAML fields are not required for SKILL.md files — the review adapts its criteria accordingly.

## Files installed

| File | Install path | Description |
|------|-------------|-------------|
| `commands/skill-review.md` | `~/.claude/commands/` | Coordinator command, triggered via `/skill-review` |
| `agents/skill-reviewer-s1.md` | `~/.claude/agents/` | S1 definition quality auditor (sonnet) |
| `agents/skill-reviewer-s2.md` | `~/.claude/agents/` | S2 interaction chain auditor (sonnet) |
| `agents/skill-researcher.md` | `~/.claude/agents/` | S3 external research specialist (sonnet + WebSearch) |
| `agents/skill-reviewer-s4.md` | `~/.claude/agents/` | S4 usability auditor (sonnet) |
| `agents/skill-challenger.md` | `~/.claude/agents/` | Challenger (**opus**) |
| `agents/skill-reporter.md` | `~/.claude/agents/` | Reporter — consolidated report + direct edits (sonnet + **Edit**) |
| `skills/validate-plugin-manifest/` | `~/.claude/skills/` | Skill for validating plugin manifests and install.sh compliance |

## Permission model

| Context | Behavior |
|---------|----------|
| Meta-project (`user-level-write` found at or above `PROJECT_ROOT`) | Reporter may directly edit files under `~/.claude/` |
| Regular project | Findings for user-level files written to `~/.claude/proposals/`; no direct edits |
| Self-referential mode (reviewing the committee itself) | Reporter generates suggestions only; Edit is prohibited |

`user-level-write` detection walks upward from the current `PROJECT_ROOT` to `CLAUDE_CWD`
(the directory where Claude was launched; defaults to `$HOME` if unset). This means a
meta-project marker at a workspace root (e.g. `cc_manager/.claude/user-level-write`) is
correctly detected even when `/skill-review` is run from a sub-directory (e.g.
`packer/readme-i18n`). Set `CLAUDE_CWD` explicitly to restrict the search boundary.

## Cost

- Stage 1: 4 sonnet agents in parallel — roughly $0.1–0.5 USD
- Stage 2 Challenger: **opus model** — roughly $0.5–2 USD (~5× sonnet cost)
- For a low-cost quick-check: enter "stop" after Stage 1 completes to skip Challenger
- A cost warning is shown when target file count exceeds 15; batch execution is suggested

## Data & Privacy

| Data | Sent to |
|------|---------|
| Target skill/agent file contents | Claude API (S1–S4, Challenger, Reporter — 6 calls total) |
| First section of `CLAUDE.md` (project context) | Claude API (all 4 Stage 1 agents) |
| Pending proposals in `~/.claude/proposals/` | Claude API (as historical context) |
| S3 search keywords | **External search service** (WebSearch / Jina) — file contents are not included |

**Recommended: use inside a git repository** so Reporter's automatic edits can be reviewed and reverted:

```bash
git diff .claude/   # review all Reporter changes
git checkout .claude/commands/my-skill.md  # revert a specific file
```

Intermediate files are written to `.claude/agent_scratch/skill_review_committee/` and `.claude/reports/`. Recommended `.gitignore` entries:

```
.claude/agent_scratch/
.claude/reports/
```

**CLAUDE.md credential detection**: if `CLAUDE.md` contains keywords such as `api_key`, `token`, `password`, or `secret`, a confirmation prompt is shown before sending (Step 0e.5).

## Notes

- Concurrent runs are not supported (lockfile protection; a second instance will error out)
- Reporter outputs a preview of each change before editing; use `git diff` to review or revert
- Semantic rewrites of `description` fields require human confirmation; Reporter outputs suggestions only, never rewrites directly
- Arguments do not accept path traversal characters (`../`, absolute paths, etc.) — skill names only

## Development

```bash
# Install locally to the default ~/.claude/
bash install.sh

# Install to a custom directory (for testing)
bash install.sh --target /tmp/test-claude
```

### Evals

`evals/evals.json` contains 15 test cases covering the main branches of coordinator logic:

| ID | Scenario | What is verified |
|----|----------|-----------------|
| 1 | No-argument call | Outputs usage guide; no agents started |
| 2 | Non-existent target name | Outputs "not found" error and available name list |
| 3 | `skill-review` (self) | Enters self-referential mode; Reporter generates suggestions only |
| 4 | `all-commands` | Dynamically discovers commands directory; launches Stage 1 four-dimensional review |
| 5 | Single target (`looper`) | Resolves mapping table, format quick-check, starts Stage 1 |
| 6 | `all,looper` (mixed args) | Rejects mixed arguments, outputs error and exits |
| 7 | `looper, patterns` (comma + space) | Auto-corrects format and continues |
| 8 | `all-agents` | Dynamically discovers agents directory; includes name kebab-case check |
| 9 | Concurrent lock protection | Detects live process holding `lock.pid`; rejects second instance |
| 10 | Cost warning gate | Outputs warning when file count > 15; waits for confirm or split |
| 11 | Zero-findings fast path | Skips Challenger; Reporter outputs ⭐ grade |
| 12 | Meta-project mode (ELEVATED) | `user-level-write` found at or above `PROJECT_ROOT` → Reporter authorized to directly edit |
| 13 | Non-meta-project mode | User-level file findings written to `proposals/` instead of direct edits |
| 14 | Challenger failure | Outputs options A/B, waits for user choice; does not auto-skip |
| 15 | Stage 3 auto-trigger | `modification_log.md` contains description change → assertion design triggered |

Each test case consists of a `prompt` (trigger input), `expected_output` (behavioral description), and `assertions` (specific verifiable checkpoints). Some cases include `files` preconditions (written to the scratch directory before execution).

Manual testing (in a Claude Code session):
```bash
/skill-review looper        # eval 5
/skill-review all-agents    # eval 8
```

Run all evals using skill-creator's eval loop (if installed):
```bash
python ~/.claude/skills/skill-creator/scripts/run_loop.py \
  --skill-path ~/.claude/commands/skill-review.md \
  --evals-path evals/evals.json
```

## Changelog

### v1.6.0 (2026-04-14)

Quality and robustness improvements — all findings from the self-referential committee review (self-ref mode CONFIRMED P1 × 4, P2 × 10, P3 × 7):

| Item | Change |
|------|--------|
| Parallel constraint | Stage 1 launch now explicitly requires all 4 Agent calls in a single `function_calls` array within one response turn — prevents accidental serial execution |
| Challenger failure branch | Step 2b: explicit condition for `CHALLENGER_FAILED` status — skips `challenger_response.md` preread, inlines status string, removes the file from Reporter params |
| Placeholder write subject | Placeholder write on missing `sN_findings.md` changed from passive to active: coordinator checks after all 4 Agents return and writes via Write tool |
| Mid-point summary template | Structured markdown template added: auditor status row, P0/P1/P2/P3 layered list, confirmation prompt. Marked as "required interactive node — no unattended mode" |
| description | Extended to intent-based phrasing covering "review 一下", "检查", "帮我看看" etc.; cost note updated to "$0.5-2+ USD depending on target count" |
| Dead code removed | `TOTAL_LINES` variable in Step 0c-1 removed; threshold constants annotated with rationale |
| grep fallback | Step 2b grep: `-B1` → `-B3`; empty-match fallback to full first-200-line read added |
| A/B/C/D strategies | Step 2a-pre overload strategies now inline-defined (A: slim P0/P1 only, B: batch 5 files, C: skip Challenger, D: terminate) |
| Self-ref detection | Path-based detection added: any target under `~/.claude/skills/skill-review/` also triggers self-ref mode; user-visible notice added |
| Lockfile trap | `trap 'rm -f lock.pid' EXIT` registered in Step 0b — covers credential-check abort, user "stop" exit, and all other exit paths |
| Stage 3 budget | Coordinator now verifies ≥3 tool call budget before Stage 3; skips with note if insufficient |
| Reporter next steps | Format spec added: ≤5 items, priority-sorted, each with corresponding skill command |
| S3 table note | S3 WebSearch annotation clarified; `skill-researcher` subagent_type exception documented |
| Constraint log comment | Self-ref constraint log line annotated: "audit log only — constraint is in Reporter prompt" |

### v1.5.0 (2026-04-14)

Hard gate on oversized targets — skill-shrink is now a required companion:

| Item | Change |
|------|--------|
| 400-line gate | Step 0c-1 upgraded: any target file >400 lines triggers a hard exit with instructions to run `/skill-shrink` first. Previously only a soft warning at >440 lines. |
| 221–400 line range | Continues with a ⚠️ quality warning (no change to flow). |
| install.sh | Post-install check detects whether skill-shrink is installed; warns if missing. |
| Prerequisite | skill-shrinker (`easyfan/skill-shrinker`) is now a required dependency for reviewing files >400 lines. |

### v1.4.1 (2026-03-31)

Permission model fix — ELEVATED detection now walks up the directory tree:

| Item | Change |
|------|--------|
| ELEVATED detection | Changed from exact `$PROJECT_ROOT/.claude/user-level-write` check to upward walk from `PROJECT_ROOT` to `CLAUDE_CWD` (env var, default `$HOME`) — fixes false-negative when running from a sub-directory of a meta-project |

### v1.4.0 (2026-03-31)

Skills support — `~/.claude/skills/*/SKILL.md` files are now first-class review targets:

| Item | Change |
|------|--------|
| Discovery | `~/.claude/skills/*/SKILL.md` scanned alongside commands/agents |
| Selector | `all-skills` added; `all` now includes skills |
| Format quick-check | Skips `model`/`tools` field checks for SKILL.md; validates `name` matches directory name |
| Proposal routing | `~/.claude/proposals/skills/` added as a proposals subdirectory |
| Stage 1 prompts | S1/S2 criteria adjusted for SKILL.md (no model selection / orchestration audit; focus on instruction clarity, edge-case coverage, description triggering) |

### v1.3.0 (2026-03-27)

Security hardening — 3 P1 fixes from S2 committee supplemental review:

| ID | Item | Change |
|----|------|--------|
| SEC-05 | ARGUMENTS whitelist | Upgraded SEC-01 blacklist to whitelist: `^(all\|all-commands\|all-agents\|[a-z][a-z0-9_-]+...)$` — fully prevents path traversal |
| SEC-06 | Confirmation gate TTY detection | Step 0e.5: replaced `read -r` with `[ ! -t 0 ]` non-interactive check; CI/Agent calls auto-abort |
| SEC-07 | Credential regex expansion | CLAUDE.md detection regex extended with value-side patterns: Bearer / ghp_ / sk- / eyJ (JWT) |
| SEC-08 | Self-referential mode skip | Step 0e.5 automatically skipped in self-referential mode (no CLAUDE.md passed = no detection needed) |

### v1.2.0 (2026-03-26)

Security and privacy hardening:

| ID | Item | Change |
|----|------|--------|
| SEC-01 | ARGUMENTS path injection | Pre-filter rejects `../`, absolute paths, and other illegal characters |
| SEC-02 | CLAUDE.md credential detection | Step 0e.5: detects api_key/token/password/secret before reading; shows confirmation prompt on match |
| SEC-03 | Data disclosure | README: added Data & Privacy section documenting what is sent to Claude API vs. external search |
| SEC-04 | .gitignore guidance | README: recommended excluding `agent_scratch/` and `reports/` |

### v1.1.0 (2026-03-26)

Bug fix batch applied after skill-test pipeline passed all 5 stages (sources: Stage 4 regression review S1/S2/S4 findings + Stage 5 looper known issues):

| ID | Priority | Issue | Fix |
|----|----------|-------|-----|
| FIX-01 | P1 | `grep -lLE` mutually exclusive flags (undefined behavior on macOS BSD grep) | Changed to `-LE` |
| FIX-02 | P2 | Cost warning lacked quantified range | Added rough USD estimate |
| FIX-03 | P2 | `PROPOSAL_SUBDIR` missing explicit `/commands/` branch; unknown paths silently skipped | Added elif branch + warning |
| FIX-04 | P2 | `grep -A 20` truncated long findings; `sed` prefix polluted Markdown structure | Changed to `-A 50`; prefix title lines only; full `cat` as authoritative content |
| FIX-05 | P2 | Challenger startup lacked estimated-time notice for user | Added "estimated 1–5 minutes" notice before launch |
| FIX-06 | P2 | Challenger failure option A wording was ambiguous, amplifying perceived risk | Simplified wording, removed parenthetical trigger explanation |
| FIX-07 | P3 | Normal path did not write `pipeline_status.md`; Reporter used mixed judgment | Stage 2 entry now writes `STATUS: NORMAL` |
| FIX-08 | P3 | Stage 3 self-referential mode `HAS_DESC_CHANGE` lacked explicit branch; `grep` matched too broadly | Added self-ref / non-self-ref routing; changed to `grep -q '^description'` |
