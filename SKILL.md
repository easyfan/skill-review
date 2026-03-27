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
| Challenger | opus | Adversarial verification requires stronger reasoning |
| Reporter | sonnet | Consolidated report + file Edit; primarily coordination |

## Prerequisites

No external tool dependencies. S3 researcher works better with WebSearch/Jina MCP available, but it is not required.

## Permission model

- **Regular project** (`.claude/user-level-write` absent): review targets project-level files only; findings for user-level files (`~/.claude/`) are written to `~/.claude/proposals/` and not directly modified
- **Meta-project** (`.claude/user-level-write` present): Reporter may directly edit skill/agent files under `~/.claude/`

## Self-referential mode

When review targets include committee files themselves (skill-review, skill-reviewer-s*, skill-researcher, skill-challenger, skill-reporter):
- Reporter generates suggestions only — **direct Edit is prohibited**
- Project CLAUDE.md is not passed in (prevents project bias from affecting review of general-purpose tools)

## Purpose

Systematic quality assessment of installed skill/agent files, producing:
- Stage 1: four-dimensional parallel findings (definition quality / chain audit / external benchmarking / usability)
- Stage 2: Challenger adversarial verification + Reporter consolidated report + direct fixes
- Quality grade: 🔴 Unusable / 🟡 Usable with defects / 🟢 Production-ready / ⭐ Excellent
