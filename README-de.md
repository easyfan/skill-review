# skill-review

Skills/Agents Design Committee — systematische, mehrdimensionale Qualitätsprüfung für Claude Code skill-, agent-, command- und SKILL.md-Dateien.

## Funktionen

`/skill-review` startet eine dreistufige Review-Pipeline:

**Stage 1 (parallel)**: 4 spezialisierte Reviewer analysieren Zieldateien gleichzeitig
- S1 Definitionsqualität: Prompt-Klarheit, Modellauswahl, Tool-Set-Passung, Description-Genauigkeit
- S2 Interaktionskette: Orchestrierungsmuster, Datenverträge, Parallel-/Serialkorrektheit
- S3 Externe Recherche: Benchmarking gegen Best Practices der Branche (inkl. WebSearch)
- S4 Usability: UX, Ausgabeformat, Fehlerbehandlung, Fortschrittsrückmeldung

**Stage 2 (seriell)**:
- Challenger (opus): erteilt CONFIRM / DISPUTE / UNVERIFIABLE-Urteile zu P0/P1-Befunden
- Reporter: konsolidierter Bericht + direkte Korrekturen bei bestätigten Problemen

**Stage 3 (bedingt)**:
- Grader: generiert automatisch should-trigger / should-not-trigger-Assertions nach Description-Änderungen

Qualitätsstufen: 🔴 Nicht verwendbar / 🟡 Verwendbar mit Mängeln / 🟢 Produktionsreif / ⭐ Exzellent

## Installation

### Option A — Claude Code Plugin-Marktplatz

In einer Claude Code-Sitzung ausführen:

```
/plugin marketplace add easyfan/skill-review
/plugin install skill-review@skill-review
```

> ⚠️ **Nicht durch automatisierte Tests verifiziert**: `/plugin` ist ein Claude Code REPL-Befehl und kann nicht via `claude -p` aufgerufen werden. Manuell in einer Claude Code-Sitzung ausführen; nicht durch die skill-test-Pipeline (looper Stage 5) abgedeckt.

### Option B — Installationsskript

```bash
git clone https://github.com/easyfan/skill-review.git
cd skill-review
bash install.sh
```

In ein bestimmtes Verzeichnis installieren (`CLAUDE_DIR` hat Vorrang vor `--target`):

```bash
CLAUDE_DIR=~/.claude bash install.sh
# oder
bash install.sh --target ~/.claude
```

> ✅ **Verifiziert**: durch die skill-test-Pipeline (looper Stage 5) abgedeckt.

### Option C — Manuell

```bash
cp commands/skill-review.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

Claude Code-Sitzung nach der Installation neu starten, damit Agents aktiv werden.

> ✅ **Verifiziert**: durch die skill-test-Pipeline (looper Stage 5) abgedeckt.

## Verwendung

```
/skill-review [target_list|all|all-commands|all-agents|all-skills]
```

**Beispiele:**

```bash
# Alle Commands, Agents und Skills prüfen
/skill-review all

# Nur Agents prüfen
/skill-review all-agents

# Nur Skills prüfen (~/.claude/skills/*/SKILL.md)
/skill-review all-skills

# Bestimmten Skill nach Name prüfen
/skill-review readme-i18n

# Mehrere Ziele (kommagetrennt, ohne Leerzeichen)
/skill-review looper,patterns

# Leichtgewichtige Schnellprüfung (nach Stage 1 "stop" eingeben, um Challenger zu überspringen)
/skill-review looper
# → nach Stage 1 "stop" eingeben
```

> **Skills** werden durch ihren Verzeichnisnamen unter `~/.claude/skills/` identifiziert (z.B. `readme-i18n` entspricht `~/.claude/skills/readme-i18n/SKILL.md`). Die YAML-Felder `model` und `tools` sind für SKILL.md-Dateien nicht erforderlich — die Prüfung passt ihre Kriterien entsprechend an.

## Installierte Dateien

| Datei | Installationspfad | Beschreibung |
|-------|------------------|--------------|
| `commands/skill-review.md` | `~/.claude/commands/` | Koordinator-Command, ausgelöst via `/skill-review` |
| `agents/skill-reviewer-s1.md` | `~/.claude/agents/` | S1 Definitionsqualitätsprüfer (sonnet) |
| `agents/skill-reviewer-s2.md` | `~/.claude/agents/` | S2 Interaktionsketten-Prüfer (sonnet) |
| `agents/skill-researcher.md` | `~/.claude/agents/` | S3 Externe Recherche-Spezialist (sonnet + WebSearch) |
| `agents/skill-reviewer-s4.md` | `~/.claude/agents/` | S4 Usability-Prüfer (sonnet) |
| `agents/skill-challenger.md` | `~/.claude/agents/` | Challenger (**opus**) |
| `agents/skill-reporter.md` | `~/.claude/agents/` | Reporter — Bericht + direkte Korrekturen (sonnet + **Edit**) |

## Berechtigungsmodell

| Kontext | Verhalten |
|---------|-----------|
| Meta-Projekt (`user-level-write` bei oder oberhalb von `PROJECT_ROOT` gefunden) | Reporter darf Dateien unter `~/.claude/` direkt bearbeiten |
| Normales Projekt | Befunde für Dateien auf Benutzerebene in `~/.claude/proposals/` geschrieben; keine direkten Änderungen |
| Selbstreferenzieller Modus (Prüfung des Committees selbst) | Reporter erstellt nur Vorschläge; Edit ist verboten |

Die `user-level-write`-Erkennung geht von `PROJECT_ROOT` aufwärts bis `CLAUDE_CWD` (Verzeichnis, in dem Claude gestartet wurde; Standard `$HOME`). Ein Meta-Projekt-Marker im Workspace-Stammverzeichnis wird auch aus Unterverzeichnissen heraus korrekt erkannt.

## Kosten

- Stage 1: 4 sonnet Agents parallel — ca. $0,1–0,5 USD
- Stage 2 Challenger: **opus-Modell** — ca. $0,5–2 USD (~5× sonnet-Kosten)
- Für günstige Schnellprüfung: nach Stage 1 "stop" eingeben, um Challenger zu überspringen
- Kostenwarnung wird angezeigt, wenn die Anzahl der Zieldateien 15 überschreitet

## Datenschutz

| Daten | Gesendet an |
|-------|------------|
| Inhalte der Ziel-Skill-/Agent-Dateien | Claude API (S1–S4, Challenger, Reporter — 6 Aufrufe gesamt) |
| Erster Abschnitt von `CLAUDE.md` (Projektkontext) | Claude API (alle 4 Stage-1-Agents) |
| Ausstehende Proposals in `~/.claude/proposals/` | Claude API (als historischer Kontext) |
| S3-Suchbegriffe | **Externer Suchdienst** (WebSearch / Jina) — Dateiinhalte nicht enthalten |

**Empfohlen: in einem Git-Repository verwenden**, damit automatische Reporter-Änderungen geprüft und rückgängig gemacht werden können:

```bash
git diff .claude/   # alle Reporter-Änderungen prüfen
git checkout .claude/commands/my-skill.md  # bestimmte Datei zurücksetzen
```

Zwischendateien werden in `.claude/agent_scratch/skill_review_committee/` und `.claude/reports/` geschrieben. Empfohlene `.gitignore`-Einträge:

```
.claude/agent_scratch/
.claude/reports/
```

## Hinweise

- Gleichzeitige Ausführungen werden nicht unterstützt (Lockfile-Schutz; eine zweite Instanz gibt einen Fehler aus)
- Reporter gibt vor jeder Änderung eine Vorschau aus; `git diff` zum Prüfen oder Zurücksetzen verwenden
- Semantische Umschreibungen von `description`-Feldern erfordern menschliche Bestätigung; Reporter gibt nur Vorschläge aus
- Argumente akzeptieren keine Pfad-Traversal-Zeichen (`../`, absolute Pfade usw.) — nur Skill-Namen

## Entwicklung

```bash
# Lokal in das Standard-~/.claude/ installieren
bash install.sh

# In ein benutzerdefiniertes Verzeichnis installieren (zum Testen)
bash install.sh --target /tmp/test-claude
```

### Evals

`evals/evals.json` enthält 15 Testfälle, die die Hauptzweige der Koordinatorlogik abdecken:

| ID | Szenario | Was verifiziert wird |
|----|----------|---------------------|
| 1 | Aufruf ohne Argumente | Gibt Verwendungshinweis aus; keine Agents gestartet |
| 2 | Nicht existierender Zielname | Gibt "nicht gefunden"-Fehler und verfügbare Namensliste aus |
| 3 | `skill-review` (selbst) | Tritt in selbstreferenziellen Modus ein; Reporter erstellt nur Vorschläge |
| 4 | `all-commands` | Erkennt Commands-Verzeichnis dynamisch; startet Stage-1-Vierdfachprüfung |
| 5 | Einzelziel (`looper`) | Löst Zuordnungstabelle auf, Schnellformatprüfung, startet Stage 1 |
| 6 | `all,looper` (gemischte Argumente) | Lehnt gemischte Argumente ab, gibt Fehler aus und beendet |
| 7 | `looper, patterns` (Komma + Leerzeichen) | Korrigiert Format automatisch und fährt fort |
| 8 | `all-agents` | Erkennt Agents-Verzeichnis dynamisch; inkl. kebab-case-Namenscheck |
| 9 | Gleichzeitiger Lockschutz | Erkennt laufenden Prozess mit `lock.pid`; lehnt zweite Instanz ab |
| 10 | Kostenwarnungsgate | Gibt Warnung aus, wenn Dateianzahl > 15; wartet auf Bestätigung oder Aufteilung |
| 11 | Nullbefunde-Schnellpfad | Überspringt Challenger; Reporter gibt ⭐-Stufe aus |
| 12 | Meta-Projekt-Modus (ELEVATED) | `user-level-write` bei oder oberhalb von `PROJECT_ROOT` → Reporter zum direkten Bearbeiten autorisiert |
| 13 | Normaler Projektmodus | Befunde auf Benutzerebene in `proposals/` statt direkte Änderungen |
| 14 | Challenger-Fehler | Gibt Optionen A/B aus, wartet auf Benutzerauswahl; kein automatisches Überspringen |
| 15 | Stage-3-Auto-Trigger | `modification_log.md` enthält Description-Änderung → Assertion-Design ausgelöst |

## Changelog

### v1.4.1 (2026-03-31)

Berechtigungsmodell-Fix — ELEVATED-Erkennung geht nun the Verzeichnisbaum aufwärts:

| Element | Änderung |
|---------|----------|
| ELEVATED-Erkennung | Von exakter `$PROJECT_ROOT/.claude/user-level-write`-Prüfung auf aufwärts gerichtete Suche von `PROJECT_ROOT` bis `CLAUDE_CWD` geändert — behebt falsch-negatives Ergebnis beim Ausführen aus einem Unterverzeichnis eines Meta-Projekts |

### v1.4.0 (2026-03-31)

Skills-Unterstützung — `~/.claude/skills/*/SKILL.md`-Dateien sind nun erstklassige Review-Ziele.

### v1.3.0 (2026-03-27)

Sicherheitshärtung — 3 P1-Fixes nach S2-Ergänzungsprüfung.

### v1.2.0 (2026-03-26)

Sicherheits- und Datenschutzhärtung.

### v1.1.0 (2026-03-26)

Bug-Fix-Batch nach erfolgreicher skill-test-Pipeline (alle 5 Stufen).
