# Clarifications - odb_datasafe v0.20.4 -> v1.0.0

This file collects ONLY genuine human-input items arising from the framework
review (Phases 1-4). Anything resolvable by repository analysis has been resolved
and is not listed. Decisions D-1 through D-5 are already made and recorded in
`doc/review/roadmap.md`; they are not repeated here.

## Open items

### ASSUMPTION - interim minor releases

The roadmap assumes interim minor tags (v0.21.0..v0.25.0) after each hardening
milestone for bisectable, releasable checkpoints. If a single v1.0.0 cut from
`main` after M5 (no interim public releases) is preferred, confirm - the
milestone sequencing is unaffected either way.

### DEPENDENCY - release-notes path for CHANGELOG backfill

D-4 backfills CHANGELOG entries for 0.19.2/0.19.3/0.19.4 from the existing
release-notes files. The roadmap assumes the layout used by the current
0.19.x/0.20.x notes. Confirm the canonical release-notes path if it differs from
`doc/releasenotes/`.

### DECISION-REQUIRED - ORA-001 Git history scrub

M1 rotates the credential and changes the SQL default to empty (fail-on-empty).
Removing the literal `DS_Admin.2025` from Git HISTORY (history rewrite) is
destructive and was not pre-decided. Decide: rewrite history, or accept rotation
plus removal-going-forward as sufficient.

### DECISION-REQUIRED - v1.1 deferrals (PERF-012, ARCH-013)

The roadmap defers PERF-012 (bounded parallelism for bulk ops, L) and ARCH-013
(move Data Safe domain logic out of `oci_helpers.sh`, L) to v1.1 so the v1.0.0
tag is not blocked. Confirm the deferral, or pull either into M4/M5 with the
corresponding effort increase.

### BLOCKER - autonomous agent definitions

No repo-local `.claude/agents/*` exist; only global `architect` and `reviewer`
agents are available. The automation design maps milestones to those plus named
role prompts (release-eng, security, oracle, test-qa, bash-robustness, docs).
Decide whether repo-specific agent definitions should be created, or whether the
global agents plus role prompts are sufficient for the autonomous driver loop.
