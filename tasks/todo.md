# PDB-Move Detection in exa_ds.sh

## Ziel

Reconcile soll PDB-Moves (PDB von einer Oracle SID / einem Cluster auf eine andere verschoben)
erkennen, aus den Missing/Orphan-Listen herausnehmen und `ds_target_reregister.sh`-Befehle
im Plan-Output generieren.

## Entscheidungen

| Punkt          | Entscheidung                                                                       |
|----------------|------------------------------------------------------------------------------------|
| Validierung    | PDB-Token-Match + Bestätigung via `dat/pdbs.json`                                  |
| CDBROOT        | Ausgeschlossen von Move-Erkennung                                                  |
| Mehrdeutigkeit | Alle Kandidaten auflisten, trotzdem aus Missing/Orphan entfernen                   |
| Plan-Output    | Option B: immer aktiv, `--plan-reregister` Flag und automatisch in `--plan-script` |
| Missing/Orphan | Erkannte Moves werden aus beiden Listen entfernt                                   |
| Credentials    | `--from-oci` standardmässig, Secret analog Register-Action                         |
| Exit-Code      | `RC_FAILURE` bleibt auch bei erkannten Moves                                       |
| Script-Pfad    | Via `DATASAFE_BASE` aufgelöst wie andere DS-Scripts                                |

---

## Implementierung: `exa_ds.sh`

### Datei

`/Users/stefan.oehrli/Library/CloudStorage/OneDrive-Accenture/20_Customers/VW/10_Arbeitsresultate/exatoolbox/bin/exa_ds.sh`

---

### Task 1 — Globale Variablen ergänzen

**Wo**: globaler Variablen-Block (nach `ReconcilePlanScript=""`)

```bash
ReconcilePlanReregister=false
ReregisterScript="ds_target_reregister.sh"   # Pfad via InitScriptPaths aufgelöst
```

- [x] Task 1 erledigt

---

### Task 2 — `InitScriptPaths` erweitern

**Wo**: Funktion `InitScriptPaths`

Analog zu `RegisterScript`:

```bash
ReregisterScript="${DATASAFE_BASE}/bin/${ReregisterScript}"
```

Und in der Verifikations-Schleife hinzufügen:

```bash
for Script in "$PrereqsScript" ... "$ReregisterScript"; do
```

- [x] Task 2 erledigt

---

### Task 3 — `ParseParameters` erweitern

**Wo**: `case "$1" in` Block in `ParseParameters`

Neues Flag nach `--plan-delete`:

```bash
--plan-reregister)     ReconcilePlanReregister=true; shift ;;
```

- [x] Task 3 erledigt

---

### Task 4 — `ValidateReconcilePlanFlags` erweitern

**Wo**: Funktion `ValidateReconcilePlanFlags`

Analog zu `--plan-register` und `--plan-delete`:

```bash
if [[ "$ReconcilePlanReregister" == "true" ]]; then
    LogMessage -s "$MESSAGE_SEVERITY_INFO" -m "Ignoring --plan-reregister for action $Action"
fi
```

- [x] Task 4 erledigt

---

### Task 5 — `ShowHelp` erweitern

**Wo**: `ShowHelp` Funktion, nach `--plan-delete` Zeile

```text
    --plan-reregister       (reconcile) print suggested reregister commands for detected moves
```

- [x] Task 5 erledigt

---

### Task 6 — Neue Funktion `ValidatePdbMoveInMetadata`

**Zweck**: Prüft ob ein PDB-Name tatsächlich im neuen CDB (new_sid) in `dat/pdbs.json` existiert.

**Signatur**: `ValidatePdbMoveInMetadata "$PdbToken" "$NewSid"`
**Rückgabe**: 0 = PDB in neuem CDB gefunden, 1 = nicht gefunden

```bash
function ValidatePdbMoveInMetadata {
    local PdbToken="$1"
    local NewSid="$2"

    [[ ! -f "$SCRIPT_DAT_DIR/databases.json" ]] && return 1
    [[ ! -f "$SCRIPT_DAT_DIR/pdbs.json"      ]] && return 1

    local Found
    Found=$(jq -rn \
        --arg pdb "$PdbToken" \
        --arg sid "$NewSid" \
        --slurpfile dbs "$SCRIPT_DAT_DIR/databases.json" \
        --slurpfile pdbs "$SCRIPT_DAT_DIR/pdbs.json" \
        '
        ($dbs[0].databases | to_entries[]
          | select((.value."db-name" | ascii_downcase) == ($sid | ascii_downcase))
          | .value.id) as $dbid |
        $pdbs[0].pdbs | to_entries[]
        | select(
            .value."container-database-id" == $dbid
            and ((.value."pdb-name" | ascii_downcase) == ($pdb | ascii_downcase))
          )
        | .value."pdb-name"
        ' 2>/dev/null | head -n1)

    [[ -n "$Found" ]]
}
```

- [x] Task 6 erledigt

---

### Task 7 — Neue Funktion `DetectMovedTargets`

**Zweck**: Erkennt Orphan/Missing-Paare die auf einen PDB-Move hinweisen.

**Signatur**:

```text
DetectMovedTargets "$MissingFile" "$OrphanFile" "$MovedFile"
```

- liest `$MissingFile` und `$OrphanFile` (sorted, non-empty lines)
- schreibt erkannte Moves nach `$MovedFile` (Format: `ORPHAN|MISSING|STATUS`)
  - STATUS = `confirmed` (1:1 Match + Metadata-Validierung)
  - STATUS = `ambiguous` (1:N oder N:1 Match, alle Kandidaten validiert)
- entfernt erkannte Orphans/Missing aus den Dateien (in-place via tmp)
- gibt Anzahl erkannter Move-Paare zurück (via stdout, nicht exitcode)

**Algorithmus**:

1. PDB-Map aus `$MissingFile` bauen: `pdb_token → [missing_targets]`
   - Nur non-CDBROOT Targets
2. Für jeden Orphan (non-CDBROOT) aus `$OrphanFile`:
   - Extrahiere `pdb_token` (letztes `_`-Segment)
   - Kandidaten = `pdb_map[pdb_token]`
   - Validiere jeden Kandidaten mit `ValidatePdbMoveInMetadata`
   - Bestimme STATUS: `confirmed` (1 validierter Kandidat), `ambiguous` (>1 validiert)
   - Schreibe Paare nach `$MovedFile`
   - Markiere Orphan als "moved"
3. Filtere `$OrphanFile` und `$MissingFile` (entferne alle markierten Einträge)
4. Gibt Anzahl erkannter Paare aus (echo)

- [x] Task 7 erledigt

---

### Task 8 — Neue Funktion `PrintReconcilePlanReregister`

**Zweck**: Gibt `ds_target_reregister.sh`-Befehle für erkannte Moves aus.

**Signatur**: `PrintReconcilePlanReregister "$MovedFile"`

Für jede Zeile `ORPHAN|MISSING|STATUS` in `$MovedFile`:

- Parse `ORPHAN` → alter Target-Name (wird als `--target` übergeben)
- Parse `MISSING` → neue Token: `new_cluster`, `new_sid`, `new_pdb`
  - Aus Target-Format: `<new_cluster>_<new_sid>_<new_pdb>`
- Baue Befehl:

  ```bash
  $SCRIPT_NAME --action reregister \
    --target "ORPHAN" --cluster "new_cluster" --sid "new_sid" \
    --from-oci [secret-flags]
  ```

  - Wenn `DSSecretFile` gesetzt: `--secret-file "$DSSecretFile"`
  - Sonst kein Secret-Flag (muss separat angegeben werden)
- Bei STATUS=`ambiguous`: Kommentar-Zeile mit Warnung voranstellen

**Hinweis**: Die `reregister`-Action ist noch nicht in `exa_ds.sh` implementiert.
Die generierten Befehle rufen `ds_target_reregister.sh` direkt auf (nicht via `exa_ds.sh`).
Befehlsformat:

```bash
"$DATASAFE_BASE/bin/ds_target_reregister.sh" \
  --target "ORPHAN" --cluster "new_cluster" --sid "new_sid" --from-oci --apply
```

- [x] Task 8 erledigt

---

### Task 9 — `WritePlanScript` erweitern

**Signatur neu**: `WritePlanScript "$MissingFile" "$OrphanFile" "$MovedFile"`

Abschnitt vor den Register-Commands einfügen:

```bash
# --- Reregister commands for moved targets ---
```

- Analog zu `PrintReconcilePlanReregister` aber direkt in die Datei schreiben
- Reihenfolge: Reregister → Register → Delete

- [x] Task 9 erledigt

---

### Task 10 — `RunReconcile` integrieren

**Änderungen**:

1. Neues Temp-File: `MovedFile="${TmpDir}/moved.pairs"`
2. Nach `comm` für Missing/Orphan:

   ```bash
   LogMessage ... "Reconcile phase: detecting PDB moves"
   local MoveCount
   MoveCount=$(DetectMovedTargets "$MissingFile" "$OrphanFile" "$MovedFile")
   # MissingFile + OrphanFile sind jetzt bereinigt
   ```

3. Counts neu berechnen nach Move-Detection
4. Summary erweitern: `moved=$MoveCount`
5. Move-Ausgabe: Liste der erkannten Moves
6. Plan-Output: `PrintReconcilePlanReregister "$MovedFile"` wenn `--plan-reregister` oder `--plan-script`
7. `WritePlanScript`-Aufruf: drittes Argument `"$MovedFile"` ergänzen

- [x] Task 10 erledigt

---

### Task 11 — Shellcheck + manuelle Verifikation

```bash
shellcheck --shell=bash exa_ds.sh
```

Testfälle:

- `--action reconcile --filter .` ohne Moves → kein moved-Output
- `--action reconcile --filter .` mit simuliertem Move-Paar → moved-Output, aus missing/orphan entfernt
- `--action reconcile --plan-reregister` → reregister-Befehle ausgegeben
- `--action reconcile --plan-script` → Datei enthält alle drei Sektionen

- [ ] Task 11 erledigt

---

## Resultat

Nach Implementierung gibt Reconcile folgende Sektionen aus:

```text
Reconcile summary: expected=150 current=148 missing=1 orphan=1 moved=1
Suspected Moves:
  exa001_cdb01a01_MYAPP  →  exa002_cdb02a01_MYAPP  [confirmed]
Missing targets:
  (none after move detection)
Orphan targets:
  (none after move detection)
Suggested reregister commands:
  .../ds_target_reregister.sh --target "exa001_cdb01a01_MYAPP" \
    --cluster "exa002" --sid "cdb02a01" --from-oci --apply
```
