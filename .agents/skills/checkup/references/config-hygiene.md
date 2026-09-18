# Configuration hygiene checks

Read this reference only in `full` or `config` mode.

## Inventory

Inventory project-local instructions and configuration that actually exists, including nested `AGENTS.md` and `CLAUDE.md` files, `CLAUDE.local.md`, `GEMINI.md`, `.agents/`, `.claude/`, `.codex/`, `.cursor/`, `.github/instructions/`, `.mcp.json`, and `.vscode/mcp.json`.

Check for:

1. Substantially duplicated instructions. Account for file scope and clients that do not share an instruction format.
2. Oversized always-loaded context that should use progressive disclosure.
3. Commands, paths, versions, architecture claims, or policies contradicted by current manifests, CI, or tracked files.
4. Skill frontmatter errors, name/directory mismatch, broad triggers, duplicated skills, missing referenced resources, and bundled executable or MCP behavior needing review.
5. Duplicate MCP definitions, missing tool filtering where supported, mutable remote package execution, missing paths, and broad exposure.
6. Hooks that synchronously perform network calls, dependency installation, broad scans, sleeps, or expensive work. Do not execute hooks in report-only mode.

Use `scan.sh` JSON results as evidence. It prints only MCP, hook-event, enabled-plugin, and permission keys; hook counts; validation status; and risk labels. It must not print command, argument, URL, environment, header, or OAuth values.

Token values from `scan.sh` are estimates based on characters divided by four. Use `/context` in Claude Code when an exact context measurement matters. Do not estimate deferred MCP tool schemas as always-loaded context.

## Optional Claude Code usage counters

Use `scan.sh --with-usage` only after the user explicitly agrees to reading the relevant keys from `~/.claude.json`. The helper reads only `skillUsage` and `pluginUsage`, then reports only counters for skills and plugins declared by the project. These counters are cumulative, not windowed, and no equivalent is guaranteed for other agents.

For a component type known to have counters, `usageCount = 0` can raise a static “no local evidence” lead to Medium confidence, or High only when ownership, entrypoint, dynamic-use, external-use, and verification evidence also agree. A zero counter is not evidence for passive plugin components such as themes or output styles that may not increment it.

Without authoritative usage evidence, report **“no repository-local usage evidence found”**, not **“unused.”** Do not recommend removing a compatibility file solely because another agent has an equivalent.
