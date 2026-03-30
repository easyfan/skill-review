---
name: validate-plugin-manifest
description: >
  Validate Claude Code plugin manifest files (plugin.json and marketplace.json) against their
  strict schemas with type checking. Use this skill whenever the user wants to validate a plugin
  before publishing, after editing plugin.json or marketplace.json, after cloning a plugin repo,
  or when a /plugin install fails with schema/validation errors. Also trigger proactively after
  any edit to .claude-plugin/ files.
---

# validate-plugin-manifest

Validate `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` against the strict
CC plugin schemas. The built-in `plugin-validator` agent only checks file structure; this skill
adds **type-level** validation of every field value.

## Steps

1. Locate `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` relative to the
   given path (default: current directory). If either file is missing, note it and skip its checks.

2. Parse each file as JSON. If parsing fails, report the syntax error immediately and stop.

3. Run the field-level checks below. Collect ALL errors before reporting — do not stop at the
   first error.

4. Report results using the output format at the end of this file.

---

## plugin.json checks

### Required fields
- `name` — must be a non-empty string, kebab-case (`[a-z0-9-]+`), no spaces or slashes.

### Path-typed fields (the most common source of breakage)
These fields, **if present**, must be either:
- a single string starting with `./`, OR
- an array where every element is a string starting with `./`

Anything else (e.g. plugin names like `"skill-review"`, bare directory names like `"commands"`,
absolute paths) is **invalid** and will cause `/plugin install` to fail with
`"commands: Invalid input"` or `"agents: Invalid input"`.

Affected fields: `commands`, `agents`, `skills`, `hooks`, `mcpServers`, `outputStyles`, `lspServers`

> If these fields are absent, CC auto-discovers components from the default directories
> (`commands/`, `agents/`, `skills/`, etc.).  Omitting them is usually correct.

### Other field types
- `version` — if present, must match `^\d+\.\d+\.\d+$` (semver).
- `description` — if present, must be a non-empty string.
- `install` — if present, must be a non-empty string (shell command).
- `author` — if present, must be an object with at least a `name` string.
- `homepage`, `repository`, `license` — if present, must be non-empty strings.
- `keywords` — if present, must be an array of strings.

---

## marketplace.json checks

### Required fields
- `name` — non-empty string, no slashes.
- `owner` — object with `name` (string) and `email` (string). Both required.
- `plugins` — non-empty array.

### Per-plugin entry checks
Each entry in `plugins[]`:
- `name` — required, non-empty string.
- `description` — required, non-empty string.
- `category` — required, one of: `productivity`, `workflow`, `development`, `content`, `integration`, `utility`.
- `source` — required object with exactly:
  - `source`: string value `"url"` or `"github"`
  - `url`: non-empty string (required when `source` is `"url"`)
  - `sha`: 40-char hex string (required; must be a reachable commit on the remote)
  - ❌ **NOT** `"source": "./"` — this is invalid and causes install failure
- `homepage` — required, non-empty string.

### Invalid/unknown fields that cause breakage
Fields that look plausible but are **not** in the schema and will fail validation:
- `metadata` (top-level)
- `source: "./"` (wrong source format — must be `{source, url, sha}` object)
- `version`, `author`, `repository`, `license`, `keywords`, `tags`, `strict` inside `plugins[]`
  entries (these belong in `plugin.json`, not `marketplace.json`)

---

## Output format

```
## Plugin Manifest Validation: <path>

### plugin.json — [PASS ✓ | FAIL ✗ | MISSING]
<errors, one per line, each with: field path → what was found → what is required>

### marketplace.json — [PASS ✓ | FAIL ✗ | MISSING]
<errors, one per line>

### Summary
- Errors: N
- Warnings: N (fields present but not in schema — won't block install)

<If PASS on both>: Ready to publish. Run /plugin marketplace update + /plugin install to verify.
<If any FAIL>: Fix the above errors before pushing.
```

---

## Reference

See `references/schema-notes.md` for annotated examples of valid and invalid manifests.
