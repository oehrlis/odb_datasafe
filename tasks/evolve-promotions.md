# Evolve Promotions — odb_datasafe → ai-toolkit

Erstellt: 2026-08-24 | Quelle: `/evolve` in `~/Repos/own/oehrlis/odb_datasafe`

---

## Prompt für ai-toolkit-Session

Ich komme aus einem `/evolve`-Lauf im Repo `odb_datasafe` (v1.1.2).
Alle verify:-Checks haben bestanden. Drei Lessons sollen in ai-toolkit promotiert werden.
Bitte schreibe die Regeln direkt in die genannten Zieldateien und bumpe die Versionen.

---

## P1 — Bash: Shared State nie per Command Substitution mutieren

**Woher:** `tasks/lessons.md` § "Shared Budget nie in einer Command Substitution veraendern"

**Regeltext (in die Zieldatei aufnehmen):**

```
## Shared State nie in Command Substitution mutieren

Funktionen, die globale Zähler- oder Budget-Variablen setzen, dürfen
nicht per `$(...)` aufgerufen werden. `$(...)` öffnet eine Subshell —
Assignments in der Subshell gehen beim Return verloren; der Aufrufer
sieht den alten Wert.

Pattern FALSCH:
  granted=$(take_budget "$count")   # BUDGET_LEFT-Änderung geht verloren

Pattern RICHTIG:
  take_budget "$count"              # setzt GRANTED global, kein stdout
  granted="$GRANTED"

verify: grep -n '=\$(take_\|=\$(consume_\|=\$(reserve_' bin/*.sh → 0 Treffer
```

**Zieldatei:** `claude/rules/bash-performance.md` — als neuen Abschnitt anhängen
**Version-Bump:** minor (neuer Abschnitt)

---

## P2 — jq: `@csv` / `@tsv` ist Endpunkt der Pipeline

**Woher:** `tasks/lessons.md` § "jq: @csv nicht erneut durch jq pipen"

**Regeltext:**

```
## jq @csv / @tsv ist Endpunkt — nie nochmals durch jq pipen

`jq -r '... | @csv'` liefert rohen CSV-Text, keinen JSON-Wert.
Ein nachgelagertes `| jq -r '.'` versucht diese CSV-Zeile als JSON zu
parsen und schlägt mit "parse error: Expected value before ','" fehl.

Gilt gleichermassen für @tsv, @text, @base64d.

FALSCH: jq -r '.[] | @csv' | jq -r '.'
RICHTIG: jq -r '.[] | @csv'

verify: grep -En "@csv'[[:space:]]*\|[[:space:]]*jq|@tsv'[[:space:]]*\|[[:space:]]*jq" bin/*.sh lib/*.sh → 0 Treffer
```

**Zieldatei:** `claude/rules/bash-performance.md` — als neuen Abschnitt anhängen (direkt nach P1)
**Version-Bump:** minor (same file, second new section — one bump covers both P1+P2)

---

## P3 — OCI Data Safe: Audit Trail hat zwei unabhängige Zustandsfelder

**Woher:** `tasks/lessons.md` § "OCI Audit Trail: lifecycle-state und status sind zwei Felder"

**Regeltext:**

```
## OCI Data Safe Audit Trail: lifecycle-state ≠ status

Ein Audit Trail trägt zwei unabhängige Zustandsfelder:

- `lifecycle-state`: Objekt-Gesundheit — ACTIVE, NEEDS_ATTENTION, FAILED, DELETING
- `status`: Collection-Betrieb — NOT_STARTED, COLLECTING, IDLE, STOPPED,
  STOPPED_NEEDS_ATTN, STOPPED_FAILED, RECOVERING

`COLLECTING` erscheint ausschliesslich in `status`, nie in `lifecycle-state`.
Code, der nur `lifecycle-state` auswertet, kann NOT_STARTED nie erkennen
und startet bereits laufende Trails erneut.

Effektiver State (Vorbild ds_trail_effective_state()):
  lifecycle NEEDS_ATTENTION/FAILED         → NEEDS_ATTENTION
  status STOPPED_NEEDS_ATTN/STOPPED_FAILED → NEEDS_ATTENTION
  sonst                                    → status (primär) oder lifecycle-state

verify: oci data-safe audit-trail list --help | grep -E '^  --(status|lifecycle-state)'
        → beide müssen als eigenständige Optionen erscheinen
```

**Zieldatei:** `claude/rules/oracle-datasafe.md` — neues File anlegen (falls nicht vorhanden)
  oder als Abschnitt in `claude/rules/oracle-security.md` einfügen
**Version-Bump:** minor (neuer Abschnitt / neues File)

---

## Nach dem Schreiben

1. `aitk status` — geänderte Dateien müssen als OUTDATED erscheinen
2. `aitk deploy --update` — in alle Repos deployen
3. Lesson-Einträge in `~/Repos/own/oehrlis/odb_datasafe/tasks/lessons.md`
   für P1, P2, P3 mit `[promoted → rule: <filename>]` markieren
