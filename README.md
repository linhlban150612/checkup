# Checkup Agent Skill

`checkup` audits a repository for stale code and files, duplicated or outdated agent instructions, potentially unused agent configuration, and expensive hooks. It reports evidence first and never changes files without explicit approval.

The skill follows the [Agent Skills specification](https://agentskills.io/specification) and lives at:

```text
.agents/skills/checkup/SKILL.md
```

Compatible agents discover it from that directory. Ask for a “project checkup,” “repository doctor,” “dead-code scan,” or “agent-configuration cleanup” to activate it.

## Modes

- `full` (default): audit code, files, and agent configuration
- `config`: audit agent instructions, skills, MCP servers, plugins, and hooks
- `code`: audit tracked project files and code
- `apply`: apply only findings the user explicitly approves after reviewing the report

## Validate

Use the official Agent Skills reference validator:

```sh
uvx --from skills-ref agentskills validate .agents/skills/checkup
```
