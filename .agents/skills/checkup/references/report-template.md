# Reporting and approved cleanup

Read this reference when preparing the report or applying an approved batch.

## Report

Include scope, selected mode, baseline worktree state, exclusions, available tools, limitations, and later verification commands with their side-effect classification.

Use stable IDs such as `CFG-01`, `FILE-01`, and `CODE-01`.

| ID | Confidence | Category | Path/item | Evidence | Counter-evidence or uncertainty | Suggested action |
|----|------------|----------|-----------|----------|---------------------------------|------------------|

“Keep” and “investigate” are valid actions. Summarize safe candidates, items needing human confirmation, low-confidence leads, and unaudited areas. Ask the user to approve exact finding IDs, a clearly named category, or no changes. Do not interpret “looks good” as cleanup approval.

## Apply an approved batch

1. Re-check `git status --short --branch` against the baseline. If a target changed, pause and re-audit it.
2. Restate the exact files and actions.
3. Make the smallest changes satisfying only the approved findings.
4. Preserve unrelated baseline and concurrent changes.
5. Show the diff and confirm no unexpected paths changed. Do not commit unless asked.

## Verify

Run the cheapest meaningful project-native checks, escalating only as justified: syntax/configuration validation, targeted lint/type/test checks, then broader build/test checks.

Ask before checks that use credentials, network services, paid quotas, production data, browsers, deployment tools, or irreversible/shared state. Compare status before and after checks and report generated side effects rather than deleting them without approval.

Report checks run, outcomes, skipped checks and reasons, side effects, remaining uncertainty, and exact changed paths. If verification fails, stop. Reverse only this checkup's edits and only when doing so cannot overwrite concurrent or pre-existing work.
