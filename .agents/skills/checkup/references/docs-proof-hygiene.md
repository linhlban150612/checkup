# Documentation and proof hygiene checks

Read this reference only in `full` or `docs` mode.

This phase asks whether a document still describes the current system and whether a retained test, gate, or validator still protects a current risk. It does not ask whether a file is old, large, or ugly. Age, folder name, and tracker state are discovery signals only.

Report findings as evidence with confidence. Do not assign dispositions such as "delete" or "merge" on your own authority; the user approves named finding IDs.

## Canonical ownership

A contract has one canonical owner. Other documents should link to it rather than restate it.

Look for:

1. Two or more tracked documents that describe the same contract in substance, not merely in topic. Quote the overlapping claims from each.
2. A document whose commands, paths, versions, interfaces, or policies are contradicted by current manifests, CI, tracked files, or code. Name the contradicting source.
3. Generated documents presented as independent truth. Identify the producer and whether the tracked copy matches it.
4. Index files that only list other index files.

Do not propose a documentation layout. A repository's existing structure is not a finding. Parallel trees matter only when two of them own the same contract.

Duplicated *agent instructions* stay in `references/config-hygiene.md`; this section covers project documentation generally.

## Reference integrity

`scan.sh --mode docs` reports `dead-link`, `link-escapes-root`, and `unresolved-path-mention` for tracked Markdown.

A dead link proves a broken reference. It never proves that the linking document is obsolete, and the correct action is often to fix the link. `unresolved-path-mention` is prose, and the text may legitimately describe a path in another repository, a planned path, or an example.

## Plans and trackers

Treat these with the weakest claims in the audit. "Completed" is a judgement about human intent, not evidence from code.

Report only what is verifiable:

- a plan or issue that references a path, command, issue ID, or owner that no longer exists;
- a tracker record that fails its own configured schema;
- a generated roadmap that disagrees with the records it is generated from.

Do not conclude that a plan is finished, superseded, or disposable from its age, its folder, or its own status field. Say "references material that no longer exists" and let the user decide.

## Proof routes

For each mandatory gate, test suite, benchmark, validator, or CI job that the project treats as acceptance, try to name all six:

1. the current risk it addresses;
2. the production behavior or machine contract it protects;
3. the current consumer of that behavior;
4. an observation that would actually fail if the behavior disappeared;
5. an oracle independent enough not to reproduce the implementation;
6. the reason ordinary cheaper testing is insufficient.

Record which of the six you could establish and from where. A gap is a finding; a gap is not a deletion instruction.

Additionally flag proof machinery that:

- asserts on source text, metadata, filenames, or artifact presence as a proxy for runtime behavior;
- pins a retired value for the sole purpose of proving its retirement;
- reproduces production logic inside a mock, simulator, or validator and therefore proves only the replica;
- runs a broad expensive workflow for a narrow local risk;
- duplicates a guarantee the compiler, type system, linter, or framework already provides;
- cannot fail under a credible removal of the behavior it claims to protect;
- produces large retained reports with no current consumer.

Keep historical compatibility vectors when the old value is still a current public, security, wire, storage, migration, or machine contract. Verify that claim before treating the vector as stale.

Do not execute tests or gates to evaluate them in report-only mode. Read them.

## Confidence for this phase

- **High** — a proof route lacks a current consumer *and* cannot fail under a credible removal of the claimed behavior, confirmed by reading the oracle and its assertions.
- **Medium** — a document contradicts current manifests, CI, or code; or two documents claim the same contract with quoted overlap.
- **Low** — an old plan or tracker record, an archive-style folder, a single dead link, or an unresolved path mention.

A document being old, a folder being named `archive/`, or a test having low coverage never reaches Medium on its own.
