# skill-review

Skills/Agents Design Committee — révision qualité systématique et multi-dimensionnelle des fichiers skill, agent, command et SKILL.md pour Claude Code.

## Fonctionnalités

`/skill-review` lance un pipeline de révision en trois étapes :

**Stage 1 (parallèle)** : 4 réviseurs spécialisés analysent les fichiers cibles simultanément
- S1 Qualité de définition : clarté du prompt, sélection du modèle, adéquation des outils, précision de la description
- S2 Chaîne d'interaction : patterns d'orchestration, contrats de données, correction parallèle/série
- S3 Recherche externe : comparaison avec les meilleures pratiques du secteur (inclut WebSearch)
- S4 Utilisabilité : UX, format de sortie, gestion des erreurs, retour d'avancement

**Stage 2 (série)** :
- Challenger (opus) : émet des verdicts CONFIRM / DISPUTE / UNVERIFIABLE sur les découvertes P0/P1
- Reporter : rapport consolidé + corrections directes des problèmes confirmés

**Stage 3 (conditionnel)** :
- Grader : génère automatiquement des assertions should-trigger / should-not-trigger après des changements de description

Niveaux de qualité : 🔴 Inutilisable / 🟡 Utilisable avec défauts / 🟢 Prêt pour la production / ⭐ Excellent

## Installation

### Option A — Place de marché de plugins Claude Code

À exécuter dans une session Claude Code :

```
/plugin marketplace add easyfan/skill-review
/plugin install skill-review@skill-review
```

> ⚠️ **Partiellement couvert par des tests automatisés** : Le chemin CLI sous-jacent `claude plugin install` est vérifié par looper T2b (Plan B). Le point d'entrée REPL `/plugin` (interface interactive) ne peut pas être testé via `claude -p` et doit être vérifié manuellement dans une session Claude Code.

### Option B — Script d'installation

```bash
git clone https://github.com/easyfan/skill-review.git
cd skill-review
bash install.sh
```

Installation dans un répertoire spécifique (`CLAUDE_DIR` est prioritaire sur `--target=`) :

```bash
CLAUDE_DIR=~/.claude bash install.sh
# ou
bash install.sh --target=~/.claude
```

> ✅ **Vérifié** : couvert par le pipeline skill-test (looper Stage 5).

### Option C — Manuel

```bash
cp commands/skill-review.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

Redémarrer la session Claude Code après l'installation pour que les agents prennent effet.

> ✅ **Vérifié** : couvert par le pipeline skill-test (looper Stage 5).

## Utilisation

```
/skill-review [target_list|all|all-commands|all-agents|all-skills]
```

**Exemples :**

```bash
# Réviser tous les commands, agents et skills
/skill-review all

# Réviser uniquement les agents
/skill-review all-agents

# Réviser uniquement les skills (~/.claude/skills/*/SKILL.md)
/skill-review all-skills

# Réviser un skill spécifique par nom
/skill-review readme-i18n

# Réviser plusieurs cibles (séparées par des virgules, sans espaces)
/skill-review looper,patterns

# Vérification rapide légère (entrer "stop" après Stage 1 pour ignorer le Challenger)
/skill-review looper
# → entrer "stop" après la fin de Stage 1
```

> **Les skills** sont identifiés par leur nom de répertoire sous `~/.claude/skills/` (ex. `readme-i18n` correspond à `~/.claude/skills/readme-i18n/SKILL.md`). Les champs YAML `model` et `tools` ne sont pas requis pour les fichiers SKILL.md — la révision adapte ses critères en conséquence.

## Fichiers installés

| Fichier | Chemin d'installation | Description |
|---------|----------------------|-------------|
| `commands/skill-review.md` | `~/.claude/commands/` | Command coordinateur, déclenché via `/skill-review` |
| `agents/skill-reviewer-s1.md` | `~/.claude/agents/` | S1 auditeur qualité de définition (sonnet) |
| `agents/skill-reviewer-s2.md` | `~/.claude/agents/` | S2 auditeur chaîne d'interaction (sonnet) |
| `agents/skill-researcher.md` | `~/.claude/agents/` | S3 spécialiste recherche externe (sonnet + WebSearch) |
| `agents/skill-reviewer-s4.md` | `~/.claude/agents/` | S4 auditeur utilisabilité (sonnet) |
| `agents/skill-challenger.md` | `~/.claude/agents/` | Challenger (**opus**) |
| `agents/skill-reporter.md` | `~/.claude/agents/` | Reporter — rapport consolidé + éditions directes (sonnet + **Edit**) |
| `skills/validate-plugin-manifest/` | `~/.claude/skills/` | Skill de validation des manifests plugin et conformité install.sh |

## Modèle de permissions

| Contexte | Comportement |
|----------|-------------|
| Méta-projet (`user-level-write` trouvé à ou au-dessus de `PROJECT_ROOT`) | Reporter peut modifier directement les fichiers sous `~/.claude/` |
| Projet normal | Découvertes pour les fichiers utilisateur écrites dans `~/.claude/proposals/` ; pas de modification directe |
| Mode auto-référentiel (révision du committee lui-même) | Reporter génère uniquement des suggestions ; Edit est interdit |

La détection de `user-level-write` remonte de `PROJECT_ROOT` vers `CLAUDE_CWD` (répertoire de lancement de Claude ; par défaut `$HOME`). Un marqueur méta-projet à la racine du workspace est correctement détecté même depuis un sous-répertoire.

## Coût

- Stage 1 : 4 agents sonnet en parallèle — environ $0,1–0,5 USD
- Stage 2 Challenger : **modèle opus** — environ $0,5–2 USD (~5× le coût sonnet)
- Pour une vérification rapide à faible coût : entrer "stop" après Stage 1 pour ignorer le Challenger
- Un avertissement de coût s'affiche quand le nombre de fichiers cibles dépasse 15

## Données et confidentialité

| Données | Envoyées à |
|---------|-----------|
| Contenus des fichiers skill/agent cibles | Claude API (S1–S4, Challenger, Reporter — 6 appels au total) |
| Première section de `CLAUDE.md` (contexte projet) | Claude API (les 4 agents Stage 1) |
| Proposals en attente dans `~/.claude/proposals/` | Claude API (comme contexte historique) |
| Mots-clés de recherche S3 | **Service de recherche externe** (WebSearch / Jina) — contenu des fichiers non inclus |

**Recommandé : utiliser dans un dépôt git** pour pouvoir examiner et annuler les modifications automatiques du Reporter :

```bash
git diff .claude/   # examiner toutes les modifications du Reporter
git checkout .claude/commands/my-skill.md  # annuler un fichier spécifique
```

## Notes

- Les exécutions simultanées ne sont pas prises en charge (protection par lockfile ; une seconde instance génère une erreur)
- Le Reporter affiche un aperçu de chaque modification avant l'édition ; utiliser `git diff` pour examiner ou annuler
- Les réécritures sémantiques des champs `description` nécessitent une confirmation humaine ; le Reporter n'écrit que des suggestions
- Les arguments n'acceptent pas les caractères de traversée de chemin (`../`, chemins absolus, etc.) — noms de skills uniquement

## Développement

```bash
# Installer localement dans le ~/.claude/ par défaut
bash install.sh

# Installer dans un répertoire personnalisé (pour les tests)
bash install.sh --target /tmp/test-claude
```

## Changelog

### v1.6.0 (2026-04-14)

Quality and robustness improvements — all self-referential committee review findings applied (CONFIRMED P1×4, P2×10, P3×7). Key changes: mandatory parallel constraint for Stage 1 Agent calls, explicit `CHALLENGER_FAILED` preread branch in Step 2b, active-voice placeholder write subject, mid-point summary template, extended description trigger coverage, dead `TOTAL_LINES` variable removed, `trap` for lockfile cleanup on all exit paths, A/B/C/D strategies inline-defined, self-ref path detection, Stage 3 tool call budget check.

### v1.5.0 (2026-04-14)

Hard gate on oversized targets — skill-shrink is now a required companion: any target file >400 lines triggers a hard exit with instructions to run `/skill-shrink` first. Post-install check detects whether skill-shrink is installed.

### v1.4.1 (2026-03-31)

Correction du modèle de permissions — la détection ELEVATED remonte désormais l'arborescence :

| Élément | Changement |
|---------|-----------|
| Détection ELEVATED | Changé de la vérification exacte `$PROJECT_ROOT/.claude/user-level-write` à une recherche ascendante de `PROJECT_ROOT` vers `CLAUDE_CWD` — corrige les faux négatifs lors de l'exécution depuis un sous-répertoire d'un méta-projet |

### v1.4.0 (2026-03-31)

Support des skills — les fichiers `~/.claude/skills/*/SKILL.md` sont maintenant des cibles de révision de premier ordre.

### v1.3.0 (2026-03-27)

Durcissement de la sécurité — 3 corrections P1 après révision supplémentaire S2.

### v1.2.0 (2026-03-26)

Durcissement de la sécurité et de la confidentialité.

### v1.1.0 (2026-03-26)

Lot de corrections de bugs après passage réussi du pipeline skill-test (5 étapes).
