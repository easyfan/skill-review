# plugin.json & marketplace.json — Annotated Schema Notes

## plugin.json — valid example

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Does something useful",
  "install": "bash install.sh",
  "author": { "name": "Alice", "email": "alice@example.com" },
  "homepage": "https://github.com/alice/my-plugin",
  "repository": "https://github.com/alice/my-plugin",
  "license": "MIT",
  "keywords": ["claude-code", "productivity"]
}
```

Note: `commands`, `agents`, `skills` are **omitted** — CC auto-discovers from default dirs.

## plugin.json — invalid examples

```json
// ❌ commands/agents as plugin names (causes "Invalid input" on install)
{
  "commands": ["my-command"],
  "agents": ["my-agent", "other-agent"]
}

// ✓ correct if custom paths are needed
{
  "commands": ["./commands/"],
  "agents": ["./agents/reviewer.md", "./agents/helper.md"]
}

// ✓ also correct: omit entirely, let CC discover
{}
```

## marketplace.json — valid example

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "my-plugin",
  "description": "Top-level description",
  "owner": {
    "name": "alice",
    "email": "alice@example.com"
  },
  "plugins": [
    {
      "name": "my-plugin",
      "description": "What this plugin does",
      "category": "productivity",
      "source": {
        "source": "url",
        "url": "https://github.com/alice/my-plugin.git",
        "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
      },
      "homepage": "https://github.com/alice/my-plugin"
    }
  ]
}
```

## marketplace.json — invalid examples

```json
// ❌ source as relative path — causes install failure
{
  "plugins": [{ "source": "./", ... }]
}

// ❌ missing owner.email
{
  "owner": { "name": "alice" }
}

// ❌ extra fields inside plugins[] — not in schema, may warn
{
  "plugins": [{
    "version": "1.0.0",    // belongs in plugin.json
    "author": {...},        // belongs in plugin.json
    "tags": [...],          // not in schema
    "strict": false,        // not in schema
    ...
  }]
}

// ❌ top-level metadata field — not in schema
{
  "metadata": { "description": "..." }
}
```

## sha self-reference problem

The `sha` field in `marketplace.json` must match a **reachable** commit on the remote.

**Anti-pattern: post-commit --amend**
```
commit A created
→ post-commit hook amends A to A'
→ marketplace.json contains sha of A
→ A is now unreachable (not reachable from any ref)
→ /plugin install fails: "unable to read tree (sha-of-A)"
```

**Correct pattern: pre-push hook**
```
commit A created (marketplace.json has placeholder sha)
→ pre-push hook runs: reads HEAD (= A), writes A's sha into marketplace.json
→ creates new commit B (no amend)
→ pushes A + B
→ marketplace.json on remote contains sha of A, which is reachable via B's parent
```
