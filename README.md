# Checkup Agent Skill

`checkup` audits a repository for stale code and files, duplicated or outdated agent instructions, potentially unused agent configuration, expensive hooks, documentation that no longer matches the code, and test or gate machinery that protects no current risk. It reports evidence first and never changes files without explicit approval.

The skill follows the [Agent Skills specification](https://agentskills.io/specification) and lives at:

```text
.agents/skills/checkup/SKILL.md
```

Compatible agents discover it from that directory. Ask for a “project checkup,” “repository doctor,” “dead-code scan,” “docs consolidation review,” or “agent-configuration cleanup” to activate it.

The skill includes read-only Bash helpers under `scripts/` for repeatable repository inventory and reference evidence. It requires Bash 3.2+, Git, `find`, and standard Unix utilities; `jq` enables JSON configuration and opt-in Claude Code usage checks.

## Modes

- `full` (default): audit code, files, agent configuration, documentation, and proof routes
- `config`: audit agent instructions, skills, MCP servers, plugins, and hooks
- `code`: audit tracked project files and code
- `docs`: audit canonical documentation ownership, reference integrity, plans and trackers, and mandatory proof routes
- `apply`: apply only findings the user explicitly approves after reviewing the report

## Validate

Use the official Agent Skills reference validator:

```sh
uvx --from skills-ref agentskills validate .agents/skills/checkup
```
