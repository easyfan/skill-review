# skill-review

Skills/Agents Design Committee — систематическая многомерная проверка качества файлов skill, agent, command и SKILL.md для Claude Code.

## Функции

`/skill-review` запускает трёхэтапный конвейер проверки:

**Stage 1 (параллельно)**: 4 специализированных ревьюера анализируют целевые файлы одновременно
- S1 Качество определения: ясность промпта, выбор модели, соответствие инструментов, точность description
- S2 Цепочка взаимодействий: паттерны оркестрации, контракты данных, корректность параллельного/последовательного выполнения
- S3 Внешние исследования: сравнение с лучшими практиками отрасли (включает WebSearch)
- S4 Удобство использования: UX, формат вывода, обработка ошибок, обратная связь о прогрессе

**Stage 2 (последовательно)**:
- Challenger (opus): выносит вердикты CONFIRM / DISPUTE / UNVERIFIABLE по находкам P0/P1
- Reporter: сводный отчёт + прямые исправления подтверждённых проблем

**Stage 3 (условно)**:
- Grader: автоматически генерирует утверждения should-trigger / should-not-trigger после изменений description

Уровни качества: 🔴 Неработоспособен / 🟡 Работоспособен с дефектами / 🟢 Готов к production / ⭐ Отличный

## Установка

### Вариант А — Маркетплейс плагинов Claude Code

Выполнить в сессии Claude Code:

```
/plugin marketplace add easyfan/skill-review
/plugin install skill-review@skill-review
```

> ⚠️ **Не проверено автоматическими тестами**: `/plugin` — встроенная команда REPL Claude Code, недоступная через `claude -p`. Запускать вручную в сессии Claude Code; не охвачено конвейером skill-test (looper Stage 5).

### Вариант Б — Скрипт установки

```bash
git clone https://github.com/easyfan/skill-review.git
cd skill-review
bash install.sh
```

Установка в указанный каталог (`CLAUDE_DIR` имеет приоритет над `--target`):

```bash
CLAUDE_DIR=~/.claude bash install.sh
# или
bash install.sh --target ~/.claude
```

> ✅ **Проверено**: покрыто конвейером skill-test (looper Stage 5).

### Вариант В — Вручную

```bash
cp commands/skill-review.md ~/.claude/commands/
cp agents/*.md ~/.claude/agents/
```

После установки перезапустить сессию Claude Code для активации агентов.

> ✅ **Проверено**: покрыто конвейером skill-test (looper Stage 5).

## Использование

```
/skill-review [target_list|all|all-commands|all-agents|all-skills]
```

**Примеры:**

```bash
# Проверить все commands, agents и skills
/skill-review all

# Проверить только agents
/skill-review all-agents

# Проверить только skills (~/.claude/skills/*/SKILL.md)
/skill-review all-skills

# Проверить конкретный skill по имени
/skill-review readme-i18n

# Проверить несколько целей (через запятую, без пробелов)
/skill-review looper,patterns

# Лёгкая быстрая проверка (ввести "stop" после Stage 1 для пропуска Challenger)
/skill-review looper
# → ввести "stop" после завершения Stage 1
```

> **Skills** идентифицируются по имени директории в `~/.claude/skills/` (например, `readme-i18n` соответствует `~/.claude/skills/readme-i18n/SKILL.md`). Поля YAML `model` и `tools` не обязательны для файлов SKILL.md — критерии проверки адаптируются автоматически.

## Установленные файлы

| Файл | Путь установки | Описание |
|------|---------------|----------|
| `commands/skill-review.md` | `~/.claude/commands/` | Команда-координатор, запускается через `/skill-review` |
| `agents/skill-reviewer-s1.md` | `~/.claude/agents/` | S1 аудитор качества определений (sonnet) |
| `agents/skill-reviewer-s2.md` | `~/.claude/agents/` | S2 аудитор цепочки взаимодействий (sonnet) |
| `agents/skill-researcher.md` | `~/.claude/agents/` | S3 специалист внешних исследований (sonnet + WebSearch) |
| `agents/skill-reviewer-s4.md` | `~/.claude/agents/` | S4 аудитор удобства использования (sonnet) |
| `agents/skill-challenger.md` | `~/.claude/agents/` | Challenger (**opus**) |
| `agents/skill-reporter.md` | `~/.claude/agents/` | Reporter — сводный отчёт + прямые правки (sonnet + **Edit**) |

## Модель разрешений

| Контекст | Поведение |
|----------|----------|
| Мета-проект (`user-level-write` найден в `PROJECT_ROOT` или выше) | Reporter может напрямую редактировать файлы в `~/.claude/` |
| Обычный проект | Находки по файлам уровня пользователя записываются в `~/.claude/proposals/`; прямые правки не выполняются |
| Само-референтный режим (проверка самого комитета) | Reporter генерирует только предложения; Edit запрещён |

Обнаружение `user-level-write` выполняется от `PROJECT_ROOT` вверх до `CLAUDE_CWD` (каталог запуска Claude; по умолчанию `$HOME`). Маркер мета-проекта в корне рабочего пространства корректно обнаруживается даже при запуске из поддиректории.

## Стоимость

- Stage 1: 4 агента sonnet параллельно — примерно $0,1–0,5 USD
- Stage 2 Challenger: **модель opus** — примерно $0,5–2 USD (~5× стоимости sonnet)
- Для дешёвой быстрой проверки: ввести "stop" после Stage 1, чтобы пропустить Challenger
- Предупреждение о стоимости показывается при числе целевых файлов > 15

## Данные и конфиденциальность

| Данные | Отправляются в |
|--------|---------------|
| Содержимое целевых файлов skill/agent | Claude API (S1–S4, Challenger, Reporter — 6 вызовов всего) |
| Первый раздел `CLAUDE.md` (контекст проекта) | Claude API (все 4 агента Stage 1) |
| Ожидающие proposals в `~/.claude/proposals/` | Claude API (как исторический контекст) |
| Поисковые запросы S3 | **Внешний поисковый сервис** (WebSearch / Jina) — содержимое файлов не включается |

**Рекомендуется: использовать в git-репозитории**, чтобы автоматические правки Reporter можно было проверить и откатить:

```bash
git diff .claude/   # просмотреть все изменения Reporter
git checkout .claude/commands/my-skill.md  # откатить конкретный файл
```

## Примечания

- Одновременные запуски не поддерживаются (защита lockfile; второй экземпляр выдаёт ошибку)
- Reporter выводит предварительный просмотр каждого изменения перед редактированием; использовать `git diff` для проверки или отката
- Семантические переработки полей `description` требуют подтверждения человека; Reporter только выводит предложения
- Аргументы не принимают символы обхода пути (`../`, абсолютные пути и т.д.) — только имена skills

## Разработка

```bash
# Установить локально в ~/.claude/ по умолчанию
bash install.sh

# Установить в пользовательский каталог (для тестирования)
bash install.sh --target /tmp/test-claude
```

## Changelog

### v1.4.1 (2026-03-31)

Исправление модели разрешений — обнаружение ELEVATED теперь обходит дерево каталогов вверх:

| Элемент | Изменение |
|---------|----------|
| Обнаружение ELEVATED | Изменено с точной проверки `$PROJECT_ROOT/.claude/user-level-write` на поиск вверх от `PROJECT_ROOT` до `CLAUDE_CWD` — исправляет ложноотрицательный результат при запуске из поддиректории мета-проекта |

### v1.4.0 (2026-03-31)

Поддержка skills — файлы `~/.claude/skills/*/SKILL.md` теперь являются целями проверки первого класса.

### v1.3.0 (2026-03-27)

Усиление безопасности — 3 исправления P1 после дополнительной проверки S2.

### v1.2.0 (2026-03-26)

Усиление безопасности и конфиденциальности.

### v1.1.0 (2026-03-26)

Пакет исправлений после прохождения всех 5 этапов конвейера skill-test.
