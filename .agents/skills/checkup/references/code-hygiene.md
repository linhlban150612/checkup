# Code and file hygiene checks

Read this reference only in `full` or `code` mode.

Use tracked files as the default candidate set. Modification times, size, naming, and Git last-touch are discovery signals, not deletion evidence. If the repository is shallow, disregard all age values marked `age-unreliable`.

For each plausible candidate:

1. Establish its intended role from nearby manifests, imports, docs, CI, naming conventions, and ownership boundaries.
2. Run `references.sh`. Review exact-path, path-suffix, relative-path, basename, filename-stem, and explicitly requested symbol matches. Matches are filenames only and exclude the target and sensitive tracked paths.
3. Check manifests, scripts, CI, docs, tests, templates, configuration, and deployment definitions—not only source imports.
4. Use Git history metadata when useful, without exposing historical secret contents. Last-touch follows the current path, not renames.
5. Check command-line entrypoints, reflection, runtime string construction, naming-based discovery, external callers, generated inputs, fixtures, migrations, and operational runbooks.
6. Prefer file-level findings. Literal symbol search is language-independent but too weak to establish symbol-level dead code by itself.

A self-reference-only file may be a standalone executable. A frequently referenced file may still be obsolete as a whole. No textual matches never prove that a target is unused.

Identify project-native verification commands and classify each before execution:

- read-only
- writes only documented disposable caches or build outputs
- changes tracked or project data
- unknown side effects

Only read-only commands belong in a report-only audit. Builds and tests commonly write files, so do not assume they are read-only.
