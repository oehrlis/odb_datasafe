# Lessons Learned - odb_datasafe

Self-improvement log per `~/.claude/CLAUDE.md`: every correction or
non-obvious validated approach gets a one-paragraph entry so the same
mistake does not recur.

## 2026-07-10 - VERSION and .extension must be bumped together

**Context.** v1.0.10 CI failed with all `--version` BATS tests reporting `not ok`.
Scripts read `SCRIPT_VERSION` from `.extension`; tests compare against `VERSION`.
The version bump was done by editing `VERSION` directly, leaving `.extension` at `1.0.9`.

**Rule.** Always use `make version-bump-patch` (or `-minor`, `-major`) to bump versions.
Never edit `VERSION` manually — the Makefile target updates both `VERSION` and `.extension`
atomically in a single commit.

**How to apply.** If a manual edit to `VERSION` is ever necessary, immediately run
`perl -pi -e "s/^version:.*/version: $(cat VERSION)/" .extension` and commit both files together.
Pre-release checklist: `make lint && make format-check && make test` catches the mismatch.

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

[promoted → rule: .claude/rules/shell-scripts.md § Makefile Workflow]

---

## 2026-07-03 - OCI JSON --database-details: Patch Keys müssen kebab-case sein

**Context.** `ds_target_reregister.sh --from-oci --apply` schlug mit OCI exit 1 fehl.
Der `--database-details` JSON enthielt doppelte, widersprüchliche Keys: `vm-cluster-id`
(alter Wert, kebab-case aus OCI GET) und `vmClusterId` (neuer Wert, camelCase aus Patch).
OCI CLI lehnte das ambige JSON ab.

**Root cause.** `compute_new_db_details()` baute den Patch mit camelCase-Keys
(`vmClusterId`, `serviceName`, `listenerPort`). OCI CLI gibt `database-details` aber
in kebab-case zurück. `jq '. + $patch'` überschreibt nur Keys mit identischem Namen —
unterschiedliche Schreibweise → beide Varianten koexistieren.

**Nebenbefund.** `show_reregister_plan()` las `."vm-cluster-id" // .vmClusterId` und
wertete den kebab-case Key zuerst aus, zeigte also den alten Cluster-Wert. Der Dry-run-
Output sah korrekt aus, obwohl das JSON schon fehlerhaft war.

**Rule.** Wenn OCI GET-Responses via `jq '. + $patch'` gepatcht werden: Patch-Keys
immer in kebab-case bauen — identisch zum Format der OCI-Antwort.

**verify.** `grep 'vmClusterId\|serviceName\|listenerPort' bin/ds_target_reregister.sh`
→ 0 Treffer in `compute_new_db_details()`.

---

## 2026-07-03 - validate_inputs(): required params vor require_oci_cli

**Context.** BATS-Tests für fehlende Pflichtparameter (z.B. `--target`, `-D`)
schlugen in CI fehl, weil `require_oci_cli` zuerst aufrief und mit
"Missing required commands: oci" abbrach — der test-spezifische Fehlertext war nie sichtbar.

**Rule.** In jeder `validate_inputs()`-Funktion: alle Pflichtparameter-Checks
(`[[ -n "$VAR" ]] || die`) ZUERST, `require_oci_cli` ZULETZT.

**verify.** `grep -n "require_oci_cli" bin/ds_target_reregister.sh` → muss nach
allen required-param `die`-Zeilen erscheinen.

[promoted → rule: .claude/rules/shell-scripts.md § validate_inputs() Ordering]

---

## 2026-08-23 - OCI Audit Trail: lifecycle-state und status sind zwei Felder

**Context.** `ds_target_audit_trail.sh --list` konnte `NOT_STARTED` nie anzeigen,
und `start_audit_trails()` schickte bei jedem Lauf einen Start an bereits
sammelnde Trails. Ursache: das Skript las ausschliesslich `lifecycle-state`.

Ein OCI Audit Trail traegt zwei unabhaengige Zustandsfelder:

- `lifecycle-state`: `ACTIVE`, `NEEDS_ATTENTION`, `FAILED`, `DELETING`, ...
  (ist das Trail-Objekt gesund?)
- `status`: `NOT_STARTED`, `COLLECTING`, `IDLE`, `STOPPED`, `RECOVERING`,
  `STOPPED_NEEDS_ATTN`, `STOPPED_FAILED`, ... (laeuft die Sammlung?)

`COLLECTING` ist ein `status`-Wert und erscheint nie in `lifecycle-state` - der
Vergleich `case "${trail_state^^}" in COLLECTING)` konnte also nie greifen.

**Rule.** Bei jedem OCI-Ressourcentyp mit `--lifecycle-state` UND `--status` als
getrennten CLI-Filtern: beide Felder auswerten. Die CLI-Filteroptionen von
`oci <service> <resource> list --help` sind die verlaessliche Quelle dafuer,
welche Zustandsfelder existieren - nicht das erste Feld in der JSON-Antwort.

**verify.** `oci data-safe audit-trail list --help | grep -E '^\s+--(status|lifecycle-state)'`
→ beide muessen als eigenstaendige Optionen erscheinen.

---

## 2026-08-23 - Shared Budget nie in einer Command Substitution veraendern

**Context.** In `ds_audit_reconcile.sh` verteilte `take_budget()` das gemeinsame
`--limit`-Kontingent ueber drei Phasen. Aufgerufen wurde sie als
`granted=$(take_budget "$count")`. Die Zuweisung an `BUDGET_LEFT` lief damit in
einer Subshell und war nach der Rueckkehr weg - jede Phase bekam das volle
Kontingent. Bei `--limit 1` haette der Lauf 4 statt 1 Aenderung gemacht.

**Rule.** Funktionen, die gemeinsamen Zustand mutieren, geben ihr Ergebnis ueber
eine globale Variable zurueck, nicht ueber stdout. Wer stdout nutzt, wird per
`$(...)` aufgerufen, und `$(...)` ist eine Subshell.

**verify.** Jede Funktion, die eine globale Zaehl- oder Budget-Variable
zuweist, darf nicht in `$(...)` aufgerufen werden:
`grep -n '=\$(\(take_\|consume_\|reserve_\)' bin/*.sh` → 0 Treffer.

---

## 2026-08-23 - jq: `@csv` nicht erneut durch jq pipen

**Context.** `ds_find_untagged_targets.sh -o csv` brach mit
"jq: parse error: Expected value before ','" ab, sobald ein untagged Target
gefunden wurde. Die Pipeline endete auf `... | @csv' | jq -r '.'`. `jq -r`
liefert bei `@csv` bereits rohen CSV-Text; der zweite `jq` versucht dann, eine
CSV-Zeile als JSON zu parsen.

**Rule.** `jq -r '... | @csv'` ist der Endpunkt der Pipeline. Kein weiteres
`jq -r '.'` dahinter. Gleiches gilt fuer `@tsv`, `@text` und `@base64d`.

**verify.** `grep -n "@csv'\s*|\s*jq\|@tsv'\s*|\s*jq" bin/*.sh lib/*.sh` → 0 Treffer.
