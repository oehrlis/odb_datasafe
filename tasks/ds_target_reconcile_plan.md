# Plan: ds_target_reconcile.sh — Generic Reconcile für odb_datasafe

Status: draft
Created: 2026-07-03
Author: Stefan Oehrli

---

## Vision (überarbeitet 2026-07-03)

Das ursprüngliche Ziel war ein generisches Pendant zur `exa_ds.sh reconcile` Action.
Die eigentliche Vision ist grösser:

> **`ds_target_reconcile.sh` soll OCI-weit nach Oracle-Datenbanken suchen, die NICHT
> in Data Safe registriert sind — über alle DB-Typen: ADB, DB Systems, ExaCC, Exadata.**

Das ist ein Coverage-Gap-Tool: "Was sollte in Data Safe sein, ist es aber nicht?"

Überlappung mit Cloud Guard: Cloud Guard kann "unmonitored database"-Regeln auslösen,
aber ohne filterbare, skriptbasierte Aktionsliste. Dieses Tool ist actionable.

---

## Phasenplan

```
Phase 1 (post-Ferien, ab 2026-07-28):  Basis-Reconcile mit externem Expected Set
Phase 2 (Spezifikation nötig):         OCI-nativer DB-Discovery + Data Safe Coverage Gap
Phase 3 (optional):                    Integration / Automation (cron, Reporting)
```

---

## Phase 1: Basis-Reconcile (implementierbar)

### Zweck

Vergleicht eine **extern gelieferte** Liste erwarteter Targets mit dem tatsächlichen
Data Safe Inventar. Identifiziert fehlende, verwaiste und verschobene Targets.
Generiert Delete-Plan-Skripte.

### Entscheidungen (geklärt 2026-07-03)

| Frage | Entscheid |
|---|---|
| Input-Format | Alle drei: `--expected-file FILE`, `--expected-list "t1,t2"`, stdin |
| Register-Plan | Report-only (Ausgabe fehlender Target-Namen) - kein Auto-Plan |
| Move-Detection | Ja, mit Warning (pattern-only, keine Metadata-Validation) |
| Naming-Konvention | Noch offen — NormalizeTargetName optional oder nur case-folding |
| exa_ds.sh Integration | Nein — komplett unabhängig |
| Timeline | Post-Ferien (ab 2026-07-28) |

### CLI-Interface

```text
ds_target_reconcile.sh [OPTIONS]

Input (einer davon erforderlich):
  --expected-file FILE     Datei: eine Target-Name pro Zeile, # Kommentare ok, - für stdin
  --expected-list "t1,..."  Komma-separierte Target-Liste

Filter / Scope:
  --filter REGEX           Regex auf expected set (default: .)
  --ignore-file FILE       Ignore-Liste CSV (cluster,sid,pdb; * Wildcard)
                           Default: ${DATASAFE_BASE}/etc/reconcile_ignore.csv

Ausgabe:
  --plan-delete            ds_target_delete.sh-Kommandos für Orphans
  --plan-script [FILE]     Delete-Plan als Shell-Skript schreiben
                           Default: /tmp/ds_reconcile_<DATUM>.sh
  --report-missing         Fehlende Targets ausgeben (kein Register-Auto-Plan)
  --no-move-detection      Move-Detection überspringen

Standard:
  --dry-run / --verbose / --debug / -h
```

### Analyse: ExaCC-spezifisch vs. generisch

**Direkt übernehmen (minimal anpassen):**

| Funktion (aus exa_ds.sh) | Portierbarkeit |
|---|---|
| `GetCurrentTargetsFromDataSafe` | 1:1 — ruft bereits `ds_target_list.sh` auf |
| `ExtractCurrentTargetNamesFromJson` | 1:1 — generisches JSON-Parsing |
| `FilterIgnoredTargets` | 1:1 — Ignore-List-Logik mit Wildcards |
| `DetectMovedTargets` | Ohne `ValidatePdbMoveInMetadata` — pattern-only |

**Neu schreiben (generisch):**

| Funktion | Beschreibung |
|---|---|
| `RunReconcile` | Hauptfunktion ohne ExaCC-Scope-Logik |
| `LoadExpectedTargets` | Liest File / CSV / stdin → normalisierte Liste |
| `PrintMissingReport` | Gibt fehlende Targets aus (statt Register-Plan) |
| `PrintDeletePlan` | `ds_target_delete.sh`-Kommandos |
| `WritePlanScript` | Delete-only Plan-Skript |

**Nicht übernehmen (ExaCC-spezifisch):**

- `BuildExpectedTargetsByFilter` / `BuildTargetsForSidScope` (OCI-Metadata)
- `ValidatePdbMoveInMetadata` (dat/pdbs.json)
- `FilterCurrentTargetsForReconcile` Family-Scope (ExaCC-Naming)
- `ResolveDbUniqueKey` (ExaCC-Metadata)
- `ValidateReconcileParameters` (ExaCC-Scope-Flags)

### Implementierungsschritte Phase 1

- [ ] Interface finalisieren (Naming-Frage F4 klären)
- [ ] Skeleton `ds_target_reconcile.sh` mit OraDBA-Header erstellen
- [ ] Generische Funktionen portieren
- [ ] `RunReconcile` neu schreiben
- [ ] Delete-Plan + Missing-Report implementieren
- [ ] Move-Detection ohne Metadata-Validation (mit Warning)
- [ ] shellcheck, manuelle Tests
- [ ] `doc/quickref.md` ergänzen

---

## Phase 2: OCI-nativer DB-Discovery (Spezifikation ausstehend)

### Vision

`ds_target_reconcile.sh --discover-oci` (oder separates Script `ds_oci_coverage.sh`)
fragt OCI direkt nach allen Oracle-Datenbankressourcen und vergleicht mit Data Safe.

### Unterstützte DB-Typen (geplant)

| DB-Typ | OCI-API | Besonderheit |
|---|---|---|
| Autonomous Database (ADB) | `oci db autonomous-database list` | ATP / ADW / AJD / APEX |
| DB Systems (DBCS) | `oci db system list` + `oci db database list` | bare metal / VM |
| ExaCC VM-Cluster DBs | `oci db vm-cluster list` + `oci db database list` | bereits in exa_ds.sh |
| Exadata Cloud@Customer | `oci db exadata-infrastructure list` | on-prem + OCI control plane |
| Base Database Service | Überschneidung mit DB Systems | je nach Tenancy-Setup |

### Abgrenzung zu Cloud Guard

| Aspekt | Cloud Guard | ds_oci_coverage.sh |
|---|---|---|
| Reaktion | Alert / Problem-Record | Skript-Output + Aktionsplan |
| Filterbarkeit | Rule-basiert | Compartment / DB-Typ / Tag / Regex |
| Aktionsplan | Nein | `ds_target_register.sh`-Template |
| Scheduling | OCI-native | Cron / OCI Functions |
| Komplexität | Kein Kundenzugriff nötig | OCI CLI / DATASAFE_BASE erforderlich |

### Offene Fragen für Spezifikation Phase 2

**SQ1 — Scope:** Compartment-weit oder Tenancy-weit?
Tenancy-Scan braucht `DATASAFE_BASE` und OCI-IAM mit entsprechenden Berechtigungen.

**SQ2 — Target-Name-Ableitung:** Wie wird aus einem OCI-DB-Objekt ein Data Safe Target-Name abgeleitet?
- ADB: `display-name` → direkt als Target-Name?
- DBCS: `db-name` + Service-Name + Hostname?
- ExaCC: bereits bekannt (cluster_sid_pdb)
- Pro DB-Typ braucht es eine Ableitungsregel oder einen Lookup gegen existierende Targets.

**SQ3 — Naming-Normalisierung:** Verschiedene DB-Typen haben verschiedene Naming-Konventionen.
Wie soll der Vergleich funktionieren wenn Data Safe Target-Names nicht deterministisch ableitbar sind?
Option: fuzzy matching (enthält `db-name`) oder exakter Match auf `display-name`.

**SQ4 — Cloud Guard:** Welche Cloud Guard Rules sind beim Kunden aktiv?
"Data Safe not enabled" o.ä.? Würde bestimmen ob Phase 2 redundant ist.

**SQ5 — Register-Template:** Für ADB und DBCS kann ein `ds_target_register.sh`-Aufruf
halb-automatisch generiert werden (Hostname aus OCI-API ableitbar).
Soll Phase 2 Register-Templates ausgeben?

**SQ6 — Separate Script oder Erweiterung?**
- Option A: `ds_target_reconcile.sh` bekommt `--discover-oci [DB-TYP]` Flag
- Option B: Separates `ds_oci_coverage.sh` — klarer, kein Mixed-Concern
Empfehlung: Option B (separates Script)

### Vorgeschlagene Roadmap Phase 2

```
M1 — Spezifikation (1-2 PT):
     - DB-Typen definieren (scope: welche OCI-Typen)
     - Target-Name-Ableitungsregeln je DB-Typ
     - Cloud Guard Overlap klären
     - Interface-Design ds_oci_coverage.sh

M2 — Discovery-Core (2-3 PT):
     - OCI-Queries je DB-Typ (ADB, DBCS, ExaCC)
     - Target-Name-Ableitung implementieren
     - Normalisierung / fuzzy match

M3 — Gap-Report + Aktionsplan (1-2 PT):
     - Missing-Report (in OCI, nicht in Data Safe)
     - Register-Template je DB-Typ
     - Orphan-Report (in Data Safe, nicht mehr in OCI)
     - Plan-Script-Output

M4 — Tests + Doku (1 PT):
     - Tests mit bekannten OCI-Umgebungen
     - quickref.md + doc/
```

---

## Offene Punkte (vor Implementierung klären)

- [ ] F4 Naming-Konvention: `NormalizeTargetName` für generisches Script — optional oder nur case-folding?
- [ ] Phase 2 Spezifikation: SQ1-SQ6 beantworten (separates Spezifikations-Meeting)
- [ ] Cloud Guard Overlap beim Kunden prüfen (sind entsprechende Rules aktiv?)
