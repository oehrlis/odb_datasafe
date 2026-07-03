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
Phase 0 (pre-Ferien, exa_ds.sh):        DataGuard-Fix in BuildExpectedTargetsByFilter
Phase 1 (post-Ferien, ab 2026-07-28):  Basis-Reconcile mit externem Expected Set
Phase 2 (Spezifikation nötig):         OCI-nativer DB-Discovery + Data Safe Coverage Gap
Phase 3 (optional):                    Integration / Automation (cron, Reporting)
```

---

## Phase 0: DataGuard-Fix in exa_ds.sh (dringend, pre-Ferien)

### Problem: Reconcile generiert 37 false-positive MISSING-Einträge

`BuildExpectedTargetsByFilter` iteriert alle Einträge in `databases.json`. Bei DataGuard
teilen sich Primary und Standby denselben `db-name`, liegen aber auf **verschiedenen
VM-Clustern**. Die Funktion generiert daher pro DG-Paar **zwei** Expected-Targets:

```
exa117r04c06_cdb03a06_ITLSAEP   ← Primary (registriert)
exa118r05c06_cdb03a06_ITLSAEP   ← Standby (nicht registriert → fälschlich MISSING)
```

Im VW-ExaCC-Environment: **37 DG-Paare** → 37 false-positive MISSING pro Reconcile-Lauf.
Reconcile ist ohne Fix für dieses Environment nicht verwendbar.

Entscheid (2026-07-03): **Nur Primary registrieren** (kein ADG-Workload, kein Peer-Link).

### Lösungsansatz: Primary-Erkennung + Dedup in BuildExpectedTargetsByFilter

Wenn `db-name` mehrere DB-unique-names hat → nur das Entry des Primary in den Expected Set.

**Primary-Erkennung (Priorität):**

| Option | Beschreibung | Aufwand |
|--------|-------------|---------|
| OCI DG API | `oci db data-guard-association list --database-id <ocid>` | mittel |
| SQL via SSH | `SELECT DATABASE_ROLE FROM V$DATABASE` auf DB-Node | einfach |
| Ignore-File | Standby-Cluster-Entries manuell in `reconcile_ignore.csv` | sofort |

Kurzfristig (pre-Ferien): **Ignore-File** — Standby-Cluster-Pattern für alle 37 Paare.
Mittelfristig (Phase 0 Implementierung): SQL-Abfrage via SSH (analog `ds_database_prereqs.sh`).

### Primary-Erkennung via SQL

```sql
SELECT DATABASE_ROLE FROM V$DATABASE;
-- PRIMARY oder PHYSICAL STANDBY
```

Implementierungsoptionen:

**Option A — Neue Funktion in `exa_ds.sh`:**
`GetDatabaseRole <identifier>` — SSH auf DB-Node, sqlplus ohne Passwort (OS-Auth),
gibt `PRIMARY` oder `STANDBY` zurück. Wird in `BuildExpectedTargetsByFilter` aufgerufen
wenn db-name mehrere Kandidaten hat.

**Option B — Erweiterung `ds_database_prereqs.sh`:**
`--check-role` Flag: Verbindung aufbauen, Rolle abfragen, als Exit-Code oder Output.
Nachteil: Prereqs-Script ist primär für Setup, nicht für Status-Abfragen.

**Option C — Neues Script `ds_db_role.sh`:**
Dediziertes Script für DB-Rollen-Abfrage. Sauberste Lösung, aber mehr Overhead.

Empfehlung: **Option A** (intern in `exa_ds.sh`, minimal invasiv).

### Failover-Prozedur (Dokumentation, kein Auto-Fix)

Bei DG-Failover (Standby wird Primary):

```bash
# 1. Altes Primary-Target löschen
exa_ds.sh --action delete --targets exa117r04c06_cdb03a06_ITLSAEP

# 2. Neues Primary registrieren (db-unique-name des neuen Primary)
exa_ds.sh --action register --sid cdb03a06_r05 --pdb ITLSAEP

# Target-Name bleibt gleich: exa118r05c06_cdb03a06_ITLSAEP
# → Policies und Assessments müssen auf neues Target übertragen werden
```

Hinweis: Data Safe-Policies und Security-Assessment-Konfigurationen sind Target-gebunden.
Nach Failover müssen diese manuell auf das neue Target übertragen oder neu angelegt werden.

### Implementierungsschritte Phase 0

- [ ] Ignore-File mit 37 Standby-Cluster-Patterns erstellen (sofort, pre-Ferien)
- [ ] `GetDatabaseRole` Funktion in `exa_ds.sh` implementieren
- [ ] `BuildExpectedTargetsByFilter`: bei DG-Konflikt Primary via `GetDatabaseRole` auflösen
- [ ] `ResolvePrereqsIdentifierBySid`: bei DG-Konflikt Primary-Only statt Error
- [ ] Failover-Prozedur in `doc/` dokumentieren
- [ ] shellcheck, Test mit `cdb03a06`-Szenario

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
| DataGuard | Caller-Responsibility: Expected Set enthält nur Primary-Targets |
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

- [ ] Phase 0: Ignore-File für 37 Standby-Cluster-Patterns erstellen (pre-Ferien Workaround)
- [ ] Phase 0: Primary-Erkennung implementieren (Option A: `GetDatabaseRole` in exa_ds.sh)
- [ ] F4 Naming-Konvention: `NormalizeTargetName` für generisches Script — optional oder nur case-folding?
- [ ] Phase 2 Spezifikation: SQ1-SQ6 beantworten (separates Spezifikations-Meeting)
- [ ] Cloud Guard Overlap beim Kunden prüfen (sind entsprechende Rules aktiv?)
