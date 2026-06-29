# Lessons Learned - odb_datasafe

Self-improvement log per `~/.claude/CLAUDE.md`: every correction or
non-obvious validated approach gets a one-paragraph entry so the same
mistake does not recur.

## 2026-05-26 - Never merge stderr into stdout when stdout is data

**Context.** `ds_target_list.sh -C -v` started failing after the system
oci-cli was upgraded to 3.83 on Python 3.14. The compartment-name resolver
returned a string composed of a `urllib3` `FutureWarning` plus the actual
OCID, which then poisoned a downstream `--query data[?name=='...']` lookup
and tripped `set -e` on "Compartment not found".

**Root cause.** `oci_exec` / `oci_exec_ro` in `lib/oci_helpers.sh` captured
the OCI CLI via `output=$("${cmd[@]}" 2>&1)` and echoed `$output` back to
the caller. Any stderr noise (deprecation warnings, TLS notices,
file-permission warnings) becomes part of the "data" stream that way.

**Rule.** When a wrapper exists to return a value (JSON, OCID, name), capture
stdout and stderr separately. Use `2>&1` only when the output is consumed
as a single human-readable log blob (error pattern matching, UI output),
and only after the caller is documented to not parse it.

**How to apply.**

- New OCI / external-command wrappers in this repo route through
  `_oci_run_capture` in `lib/oci_helpers.sh`.
- Defense-in-depth: `lib/common.sh` exports `PYTHONWARNINGS=ignore` and
  `OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING=True` at load time, so a single
  forgotten `2>&1` does not immediately break parsing. Treat this as
  belt-and-braces, not as a substitute for stream separation.
- When triaging similar "garbled output" issues, run the failing command
  with `2>/dev/null` to confirm whether stderr noise is the culprit before
  changing the parser.

**Blast radius observed.** All 17 `bin/ds_*.sh` scripts route through
`oci_exec` / `oci_exec_ro`, so the wrapper fix covers them en bloc. The
sibling `oci-datasafe-siem` repo was not affected because its scripts
already use `2>/dev/null` on every command substitution.

---

## Always use `make format` before commit/tag, not bare `shfmt -w`

**What happened.** `shfmt -w` applied tab indentation (default), but the
Makefile's `format-check` target runs `shfmt -i 4 -bn -ci -sr -d` (4-space
indent). Tag `v1.0.1` was created and pushed, CI failed on format-check,
tag had to be deleted, fix committed, tag recreated.

**Rule.** Never run `shfmt -w` directly. Always use `make format` so the
project-specific flags (`-i 4 -bn -ci -sr`) are applied. Verify with
`make format-check` before tagging.

**How to apply.** The pre-release checklist is: `make lint && make format-check
&& make test` — all three must be green before `git tag`.
