---
name: validate-plugin-manifest
description: >
  Validate Claude Code plugin manifest files and installer completeness. Checks plugin.json and
  marketplace.json against strict schemas with type checking, AND checks install.sh interface
  compliance, installed file completeness, and package.json files field coverage. Use whenever
  the user wants to validate a plugin before publishing, after editing .claude-plugin/ files,
  after cloning a plugin repo, or when /plugin install fails. Also trigger proactively after
  any edit to .claude-plugin/, install.sh, or package.json.
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

4. Run the installer completeness checks below.

5. Report results using the output format at the end of this file.

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

## Installer completeness checks

These checks validate that the plugin can be installed correctly via both the CC UI (`/plugin install`)
and the manual `bash install.sh` path. They are based on real installation failures observed in
production (see cases below).

### install.sh interface compliance

Read `install.sh`. Verify it handles all of the following:

- **No-arg install** — running `bash install.sh` with no arguments must install files to
  `${CLAUDE_DIR:-$HOME/.claude}`. This is how CC UI calls it.
- **`--dry-run`** — must preview without writing any files. Missing this blocks safe pre-flight
  testing.
- **`--uninstall`** — must remove installed files. Without this, users cannot cleanly uninstall
  via script (the CC UI Remove button relies on `installed_plugins.json`, which only exists after
  a successful UI install; manual installs have no other removal path).
- **`--target=<path>` or `CLAUDE_DIR=<path>`** — must accept a custom install directory (at least
  one form). Required by packer test pipelines.

> **Case:** skill-review's original install.sh only had `--target`, missing `--dry-run` and
> `--uninstall`. Users who installed manually had no way to uninstall via script.

### Installed file completeness

1. Read all `cp` / `mkdir` / file-write operations in `install.sh` to determine the set of files
   it installs.
2. Also scan the repo for installable directories: `commands/`, `agents/`, `skills/`. For each,
   list the `.md` files found.
3. Compare: every `.md` file in `commands/`, `agents/`, and every `SKILL.md` under `skills/`
   **must** appear in an install operation. Report any that are missing.

> **Case:** skill-review had `skills/validate-plugin-manifest/SKILL.md` in the repo but install.sh
> never copied it to `~/.claude/skills/`. The skill was invisible to users after installation.

### package.json `files` field coverage

Read `package.json`. If a `files` array is present, verify it covers every directory/file that
`install.sh` installs. Common omissions:

- A `skills/` directory added to install.sh but not added to `files`
- `AGENTS.md` present but not listed
- `evals/` directory not listed (low severity — does not affect install, but breaks `npm publish`)

> **Case:** skill-review `package.json` listed `commands/`, `agents/`, `SKILL.md` in `files`,
> but omitted `skills/` after the validate-plugin-manifest skill was added. This means
> `npm publish` would silently exclude the new skill.

### Cache directory structure (post-install check)

This check is relevant when diagnosing a failed `/plugin install` in another project.

If `~/.claude/plugins/cache/{marketplaceName}/` exists AND contains both:
- A `.git` directory at the top level (i.e., a full git clone at the root), AND
- A `{pluginName}/` subdirectory (the versioned plugin cache)

then the cache is **corrupt**: the marketplace clone and the plugin versioned cache share a
parent-child path. Any subsequent install attempt that copies from the versioned cache will
recurse into itself, producing `ENAMETOOLONG: name too long` errors with infinitely nested paths.

**Fix:** Delete all files and `.git` at the top level of `cache/{marketplaceName}/`, leaving only
the `{pluginName}/` subdirectory.

> **Case:** `~/.claude/plugins/cache/news-digest/` contained a full git clone (with `.git`,
> `install.sh`, `package.json`, etc.) at the root, alongside `news-digest/1.1.0/` as the
> versioned plugin cache. Installing news-digest from any other project triggered recursive
> path nesting: `news-digest/1.1.0/news-digest/1.1.0/news-digest/1.1.0/...` until the OS
> path length limit was hit. Same issue affected `readme-i18n`. `skill-review` was not affected
> because its cache was initialized correctly.

---

## Output format

```
## Plugin Manifest Validation: <path>

### plugin.json — [PASS ✓ | FAIL ✗ | MISSING]
<errors, one per line, each with: field path → what was found → what is required>

### marketplace.json — [PASS ✓ | FAIL ✗ | MISSING]
<errors, one per line>

### install.sh interface — [PASS ✓ | FAIL ✗ | MISSING]
- --dry-run: [present / MISSING]
- --uninstall: [present / MISSING]
- --target / CLAUDE_DIR: [present / MISSING]

### Installed file completeness — [PASS ✓ | FAIL ✗]
<list any .md files in commands/, agents/, skills/ that install.sh does NOT install>

### package.json files field — [PASS ✓ | WARN ⚠ | MISSING]
<list any directories/files installed by install.sh that are absent from files[]>

### Summary
- Errors: N   (block install or uninstall)
- Warnings: N (won't block install, but affect publish or usability)

<If all PASS>: Ready to publish. Run /plugin marketplace update + /plugin install to verify.
<If any FAIL>: Fix the above errors before pushing.
```

---

## Reference

See `references/schema-notes.md` for annotated examples of valid and invalid manifests.
