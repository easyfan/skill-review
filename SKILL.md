---
name: skill-review
description: Skills/Agents Design Committee — multi-dimensional quality review for Claude Code skill/agent files. Includes a coordinator command and six specialist agents (S1/S2/S3/S4/Challenger/Reporter). Installs to ~/.claude/commands/ and ~/.claude/agents/.
---

# skill-review package

## Files

### Commands (coordinator)
- `commands/skill-review.md` → `~/.claude/commands/skill-review.md`

### Agents (committee members)
- `agents/skill-reviewer-s1.md` → `~/.claude/agents/skill-reviewer-s1.md` (definition quality)
- `agents/skill-reviewer-s2.md` → `~/.claude/agents/skill-reviewer-s2.md` (interaction chain)
- `agents/skill-researcher.md` → `~/.claude/agents/skill-researcher.md` (external research)
- `agents/skill-reviewer-s4.md` → `~/.claude/agents/skill-reviewer-s4.md` (usability)
- `agents/skill-challenger.md` → `~/.claude/agents/skill-challenger.md` (Challenger, opus)
- `agents/skill-reporter.md` → `~/.claude/agents/skill-reporter.md` (Reporter, with Edit)

## Pipeline structure

```
/skill-review <target>
        │
Stage 1 │  ┌──────────────────────────────────────────────────────┐
(par.)  │  │  S1 Definition  S2 Chain  S3 Research  S4 Usability  │
        │  └──────────────────────────────────────────────────────┘
        │                    ↓ summarize ↓
Stage 1 │  Present findings summary, wait for user to confirm Stage 2
midpoint│
        │
Stage 2 │  Challenger (opus) — adversarial verification of P0/P1 findings
(ser.)  │        ↓
        │  Reporter (sonnet + Edit) — consolidated report + direct fixes
        │
Stage 3 │  Grader (optional) — assertion design (triggered on description change)
(cond.) │
```

## Model assignments

| Member | Model | Reason |
|--------|-------|--------|
| S1/S2/S4 | sonnet | Document analysis; no high-cost reasoning needed |
| S3 | sonnet | External search research; sonnet is sufficient |
| Challenger | sonnet | Adversarial verification; opus was over-budget for this task |
| Reporter | sonnet | Consolidated report + file Edit; primarily coordination |

> **Note**: Challenger's `description` still says "opus model" for historical reasons, but the agent frontmatter uses `model: sonnet`. The description is intentionally not updated to avoid triggering Stage 3 assertion regeneration on every review.

## Prerequisites

No external tool dependencies. S3 researcher works better with WebSearch/Jina MCP available, but it is not required.

## Permission model

- **Regular project** (`.claude/user-level-write` absent): review targets project-level files only; findings for user-level files (`~/.claude/`) are written to `~/.claude/proposals/` and not directly modified
- **Meta-project** (`.claude/user-level-write` present): Reporter may directly edit skill/agent files under `~/.claude/`

## Self-referential mode

When review targets include committee files themselves (skill-review, skill-reviewer-s*, skill-researcher, skill-challenger, skill-reporter):
- Reporter generates suggestions only — **direct Edit is prohibited**
- Project CLAUDE.md is not passed in (prevents project bias from affecting review of general-purpose tools)

## Gotcha mechanism (v1.7+)

Coordinator can pass a `gotcha_context.md` to Challenger, containing known failure patterns with historical priority floors. When a finding matches a gotcha:

- Challenger **may not DISPUTE below the gotcha's recorded priority** (e.g., a P0 gotcha cannot be downgraded)
- DISPUTE requires "structural elimination" proof: the root cause must be architecturally impossible in the current skill, not merely absent from the current file
- DISPUTE of a gotcha must be annotated with `[GOTCHA OVERRIDE: <gotcha_id>]` and cite specific line evidence

This prevents recurrence of previously-confirmed failure modes being silently cleared in future reviews.

## File write discipline (v1.7+)

Both Challenger and Reporter use `Bash` heredoc writes instead of the `Write` tool. Reason: `Write` tool may produce an empty `{}` when output token budget is exhausted in large contexts, resulting in silent data loss. The heredoc pattern (`cat > file << 'EOF' ... EOF`) is immune to this failure mode.

For content >2000 characters, agents split into multiple `cat >>` appends.

## Purpose

Systematic quality assessment of installed skill/agent files, producing:
- Stage 1: four-dimensional parallel findings (definition quality / chain audit / external benchmarking / usability)
- Stage 2: Challenger adversarial verification + Reporter consolidated report + direct fixes
- Quality grade: 🔴 Unusable / 🟡 Usable with defects / 🟢 Production-ready / ⭐ Excellent
- Gotcha protection: known failure modes maintain historical priority floors across reviews
