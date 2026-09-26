# Implementation Plan — 3 LOW-priority скилла для `.opencode/skills/`

**Задача:** реализовать скиллы `agent-report`, `pipeline-visualize`, `deploy-package-build` по паттерну существующих скиллов (уже реализованы 9: `integrity-check`, `config-sync`, `agent-model-migrate`, `backup-snapshot`, `model-key-validate`, `agent-add`, `model-discovery`, `provider-config-audit`, `bifrost-config-apply` — все являются ОБРАЗЦОМ).
**Дата инспекции файлов:** 2026-09-23. Все якоря — ТЕКСТОВЫЕ (переживают дрейф номеров строк); номера строк даны только как справка на дату инспекции (ARCHITECTURE.md: `## Model Roles` L108, whitelists L7/L37, `## 2. Pipelines` L307).
**Исполнитель:** dev-professor (реализует строго из этого файла). Язык SKILL.md и комментариев скриптов — английский (конвенция существующих скиллов); язык этого плана — русский.

---

## Goal

Создать 3 проектных скилла в `.opencode/skills/` (9 файлов: 3 × {SKILL.md, scripts/*.ps1, scripts/*.py}):

1. **agent-report** — отчёт о состоянии агентов: таблица агент → модель → роль → permissions → routing + сводки распределения по моделям и ролям. Форматы: table / markdown / json. Read-only, секунды, без LLM. Exit 0/2.
2. **pipeline-visualize** — ASCII-визуализация всех пайплайнов из ARCHITECTURE.md §2 с моделями агентов в каждом шаге и подсветкой prewalk-пар (дорогая → дешёвая модель). Форматы: ascii / markdown / json. Read-only. Exit 0/2.
3. **deploy-package-build** — сборка `deploy-package/` из live-файлов: байт-копирование + SHA256-верификация + HASHES.txt + gates (счётчики 37/10/25/10, routing-таблицы из 3 источников, secret-скан) + опциональный `deploy-package.7z`. Exit 0/2/3.

## Architecture

### Общие паттерны (ОБЯЗАТЕЛЬНЫ к повторению — извлечены из check.ps1/sync.ps1/migrate.ps1/snapshot.ps1)

**Раскладка:**
```
.opencode/skills/<skill-name>/
├── SKILL.md              # frontmatter: name + description (ОДИНАРНЫЕ КАВЫЧКИ!)
└── scripts/
    ├── <main>.ps1        # Windows PowerShell 5.1+
    └── <main>.py         # POSIX mirror, Python 3.8+, stdlib only
```
Имена главных скриптов: `report.ps1/.py`, `visualize.ps1/.py`, `build.ps1/.py` (конвенция коротких глаголов: check, sync, migrate, snapshot, validate, add, audit, discover, apply).

**⚠️ YAML-грабля (silent skill drop):** opencode МОЛЧА дропает скилл, если `description:` содержит незакавыченную последовательность `": "`. **Все три SKILL.md берут description в одинарные кавычки; апострофы внутри description запрещены.** Регистрация скилла подхватывается только в НОВОЙ сессии.

**⚠️ Unicode-грабля (PS 5.1):** PowerShell 5.1 читает `.ps1` БЕЗ BOM как ANSI (cp1251) — литералы `→` (U+2192) и `∥` (U+2225) в исходнике скрипта сломаются. **Правило: в .ps1 и .py НЕ использовать юникодные литералы стрелок — только escapes `\u2192` / `\u2225` в regex и `[char]0x2192` / `'\u2192'` при IndexOf/split.** Вывод скриптов — ASCII-only (`->`, `==>`, `|`, `+`).

**Определение repo root** (копия verbatim):
- PS: `$skillDir = Split-Path -Parent $MyInvocation.MyCommand.Path`; 4× `Split-Path -Parent` → repo root; fallback `git rev-parse --show-toplevel` через `Invoke-Native` если `deploy-package` не найден.
- PY: `Path(__file__).resolve().parents[3]` (функция `repo_root(script_dir)` из snapshot.py — копия verbatim).

**Live-пути:**
- PS: `$liveDir = Join-Path $env:USERPROFILE '.config\opencode'`
- PY: `Path.home() / '.config' / 'opencode'`

**Хелперы — скопировать VERBATIM из существующих скриптов** (идентичны во всех скиллах):

| Хелпер (PS / PY) | Источник | Нужен в |
|---|---|---|
| `Read-RawText` / `read_raw` (BOM-aware) | check.ps1 L~77 / check.py | все 3 |
| `Write-RawText` / `write_raw` | migrate.ps1 L103 / migrate.py | build |
| `Get-Sha256` / `sha256_file` (64KB chunks, UPPER) | check.ps1 / check.py | build |
| `Invoke-Native` | migrate.ps1 L76 | build (7z), visualize (git fallback) |
| `Get-FmModel` / `get_fm_model` (`\A---\r?\n(.*?)\r?\n---` + `^model:[ \t]*(.*)$`) | migrate.ps1 L121 | report, visualize, build |
| `Split-ModelKey` / `split_model_key` (split по ПЕРВОМУ `/`) | migrate.ps1 L113 | report, visualize |
| `Split-Tokens` / `split_tokens` (comma-split + trim) | migrate.ps1 L159 | report, visualize |
| repo-root блок | snapshot.ps1 / snapshot.py | все 3 |
| `Count-TaskAllow` | check.ps1 L125–131 | build (gate), report (cross-check — см. вариант Get-TaskAllowNames ниже) |
| `Count-RoutingPlugin` | check.ps1 L133–139 | build (gate) |
| `Get-WhitelistCount` | check.ps1 L141–153 | build (gate) |

**Конвенция вывода (все скиллы):** токены UPPERCASE `STATUS:`, `WARN:`, `ERROR:`, `SUMMARY:`, `GATE:`, `COUNT:`, `SAME:/CHANGED:/NEW:/COPIED:/VERIFY:` (build), `AGENT:/MODEL_DIST:/ROLE_DIST:` (report), `PIPELINE:/PREWALK:/INFO:TIER_DROP` (visualize). Exit codes: `0` успех/отчёт, `2` usage/environment, `3` gate block/находки (ТОЛЬКО build; report и visualize — без exit 3, они не гейтят).

**Байт-безопасность:** чтение/запись только через `[System.IO.File]::ReadAllBytes/WriteAllBytes` (PS) и `Path.read_bytes/write_bytes` (PY); копирование — байтовое (`[System.IO.File]::Copy` / `shutil.copyfile`), CRLF/BOM сохраняются by construction; HASHES.txt — принудительный LF.

**Token-exact matching:** имена агентов/моделей сравниваются байт-в-байт (`-ceq` в PS, `==` в PY); имена моделей с пробелами/скобками (`GLM-5.3 (res)`, `Kimi K3`) — в ЛЮБОМ regex-паттерне только через `[regex]::Escape()` / `re.escape()`.

**PS 5.1 ограничения:** без тернарного оператора, без `??`, без `-Encoding utf8NoBOM`; `${env:ProgramFiles(x86)}` для x86-переменной; `ConvertTo-Json -Depth 6`.
**Python:** 3.8+, только stdlib (`json, hashlib, argparse, pathlib, re, sys, shutil, subprocess, datetime`); YAML-модуля НЕТ — мини-парсеры frontmatter/permissions идентичны в PS и PY (output parity).

**Источник ARCHITECTURE.md — ВСЕГДА корневой (repo root).** Известное пре-существующее расхождение: live-копия `~/.config/opencode/ARCHITECTURE.md` расходится с корневой в Model Roles — скиллы её НЕ читают.

**CHANGELOG:** проектные скиллы записей в CHANGELOG.md НЕ получают (конвенция — 9 существующих скиллов без записей). Git-коммит — только через агента `git-commit` (в WARN:MANUAL follow-ups).

---

# Скилл 1: agent-report

## 1.1 Полное содержимое SKILL.md

````markdown
---
name: agent-report
description: 'Fast LLM-free fleet report — per-agent table (frontmatter model, Model Roles role/tier, mode, flattened permissions, routing membership orch/plan/both/none) plus model-distribution and role-distribution summaries. Sources: live (default) or deploy agent files, root ARCHITECTURE.md (Model Roles + whitelists), live opencode.json (routing cross-check, WARN on mismatch). Formats: aligned table (default), markdown, JSON. Strictly read-only, runs in seconds. Exit 0 report generated, exit 2 usage/environment error.'
---

# Agent Report

Deterministic, LLM-free state report of the agent fleet: every agent with its
model, Model Roles role/tier, mode, flattened frontmatter permissions and
routing-whitelist membership, plus model- and role-distribution summaries.
Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- "What does the fleet look like NOW" overview before/after migrations
- Model load review: how many agents run on each model (cost/tier balance)
- Role and tier audit input (which agents are top/mid/low)
- Routing overview: which subagents each primary agent may call
- Embeddable report for plans/PRs/docs (-Format markdown / -Format json)

## When NOT to use

- Gated validation (pair hashes, counters vs expected) — use `integrity-check`
- Model key validity/suggestions — use `model-key-validate`
- Changing a model — use `agent-model-migrate`
- Pipeline structure diagrams — use `pipeline-visualize`
- Packaging deploy-package — use `deploy-package-build`

## Data sources

| Field | Source (authority order) |
|-------|--------------------------|
| model, mode, permissions | agent frontmatter — live `~/.config/opencode/agents/*.md` (default) or `deploy-package/agents` (`-Source deploy`) |
| role, tier | root `ARCHITECTURE.md` → `## Model Roles` table |
| routing | root `ARCHITECTURE.md` → `### orchestrator Whitelist` / `### plankestrator Whitelist` table rows |
| routing cross-check | `opencode.json` (`-Config`, default live) → `agent.<primary>.permission.task` allow-keys (mismatch → WARN, never fatal) |

Authority rule: the displayed `model` is ALWAYS the frontmatter value
(Permission Authority — opencode.json carries no model field). The Model Roles
`model` column is only COMPARED against frontmatter (`WARN:ROLE_MODEL_DRIFT`),
never displayed as truth. Skills read the ROOT ARCHITECTURE.md (known
pre-existing drift: the live copy under ~/.config/opencode may differ).

## Report columns

`agent | model | role | tier | mode | routing | permissions`

- routing: `orch` / `plan` / `both` / `-` (in neither whitelist, e.g. scout)
- permissions: frontmatter `permission:` block flattened to dot-path pairs in
  document order: `edit=allow; bash.*=allow; bash.git commit*=deny;
  task.*=deny; task.scout=allow`. Table format truncates to 6 pairs + `+N`;
  markdown shows all; JSON keeps them as an object.

## Summaries

- `MODEL_DIST` — per distinct frontmatter model (sorted by count desc, then
  model asc): count + agent names
- `ROLE_DIST` — per Model Roles role (table order): tier, count + agent names
- `SUMMARY` — agents, shown, distinct models, roles, routing counts
  (orch/plan/both/none), unmapped agents, warnings

## Workflow

1. Resolve flags/paths; invalid flags or combinations → exit 2
2. Read ARCHITECTURE.md; require anchors `## Model Roles` and BOTH whitelist
   headers (missing → exit 2)
3. Scan agents dir (`*.md`); parse each frontmatter (model, mode, permission
   flat); missing/empty dir → exit 2; frontmatter without `model:` →
   `WARN:FM_NO_MODEL` (row still reported with `model=<missing>`)
4. Join: role map (agent → role/tier; absent → `WARN:ROLE_UNMAPPED`,
   role=`<unmapped>`, tier=`?`); Model Roles model vs frontmatter model
   (byte-compare, mismatch → `WARN:ROLE_MODEL_DRIFT`); whitelist membership;
   opencode.json task-allow cross-check (mismatch → `WARN:ROUTING_MISMATCH`;
   file missing/unparsable → `WARN:CROSSCHECK_SKIPPED`)
5. Apply filters (`-Agent` exact — not found → exit 2; `-Role` exact;
   `-Model` case-insensitive substring)
6. Compute distributions on the FULL fleet; render body per `-Format`;
   emit tokens; exit 0

## Usage

```powershell
& ".opencode\skills\agent-report\scripts\report.ps1"
& ".opencode\skills\agent-report\scripts\report.ps1" -Format markdown
& ".opencode\skills\agent-report\scripts\report.ps1" -Format json
& ".opencode\skills\agent-report\scripts\report.ps1" -Source deploy
& ".opencode\skills\agent-report\scripts\report.ps1" -Role executor-cheap
& ".opencode\skills\agent-report\scripts\report.ps1" -Model "GLM-5.3"
& ".opencode\skills\agent-report\scripts\report.ps1" -Agent worker
```

### POSIX mirror

```bash
python .opencode/skills/agent-report/scripts/report.py [--source live|deploy] [--format table|markdown|json] [--agent NAME] [--role ROLE] [--model SUBSTR]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Source live\|deploy` | agents dir: live (default) or `deploy-package/agents` |
| `-Format table\|markdown\|json` | report body format (default `table`) |
| `-Agent <name>` | single-agent report (exact, token-equal; not found → exit 2) |
| `-Role <role>` | filter by Model Roles role (exact) |
| `-Model <substr>` | filter by model substring (case-insensitive) |
| `-AgentsDir <dir>` | explicit agents dir (overrides `-Source`; relative → repo root) |
| `-Arch <path>` | ARCHITECTURE.md (default: repo root) |
| `-Config <path>` | opencode.json for routing cross-check (default: live; missing → WARN skip) |

## Gates

| Gate | Effect |
|------|--------|
| `-Agent` combined with `-Role`/`-Model` | BLOCK (exit 2) |
| `-Source` value other than live/deploy combined with `-AgentsDir` | BLOCK (exit 2) |
| Agents dir / ARCHITECTURE.md missing, agents dir empty | BLOCK (exit 2) |
| Anchors `## Model Roles` / whitelist headers not found | BLOCK (exit 2) |
| `-Agent <name>` not found among scanned agents | BLOCK (exit 2) |
| Role/model/routing drift, unmapped agents, cross-check skip | WARN (exit code unchanged) |

## Output format

table/markdown modes emit token lines + the rendered body:

```
STATUS:REPORT_START source=live agents=37 arch=ARCHITECTURE.md
WARN:ROLE_UNMAPPED agent=<name> (not in Model Roles table)
WARN:ROLE_MODEL_DRIFT agent=plan-bug arch=<model> frontmatter=<model>
WARN:ROUTING_MISMATCH primary=orchestrator arch_only=[...] json_only=[...]
WARN:CROSSCHECK_SKIPPED reason=<opencode.json missing/unparsable>
<report body: aligned table or markdown sections>
MODEL_DIST:bifrost-litellm/MiniMax-M3 count=10 agents=execute-bug,git-commit,...
ROLE_DIST:executor-cheap tier=low count=10 agents=execute-bug,...
SUMMARY:agents=37 shown=37 models=10 roles=18 orch=25 plan=10 both=1 none=1 unmapped=0 warn=2
STATUS:SUCCESS
```

json mode emits ONLY the JSON document (no token lines):
`{generated_utc, source, agents_dir, agents:[{name,model,role,tier,mode,routing,permissions:{...}}], model_dist:[{model,count,agents}], role_dist:[{role,tier,count,agents}], routing:{orchestrator:[],plankestrator:[],both:[],none:[]}, warnings:[], summary:{...}}`

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Report generated (WARNs allowed — a report never fails on drift) |
| 2 | Usage/environment error (bad flags/combination, missing dirs/files, anchors absent, `-Agent` not found, empty agents dir) |

This skill has NO exit 3: it reports state, it does not gate. Gating checks
live in `integrity-check` / `deploy-package-build`.

## Hard rules

- STRICTLY READ-ONLY: never writes, fixes or deletes anything
- No LLM, no network — deterministic local parsing only (seconds)
- Frontmatter `model:` is the ONLY model authority; ARCHITECTURE.md model
  column is compared, never displayed as truth
- Model/agent names are byte-exact (spaces and parentheses: `GLM-5.3 (res)`,
  `Kimi K3`); always `[regex]::Escape()` / `re.escape()` before pattern use
- Token-exact agent-name matching for `-Agent` and whitelist joins (no fuzzy)
- No hardcoded agent count — the agents dir is scanned as-is (works
  mid-migration when the count is 37 or 38)
- Distributions are computed on the FULL fleet; filters affect the body only
  (`shown=` vs `agents=` in SUMMARY)
- WARN never changes the exit code
- PS and PY mirrors produce identical tokens/columns (output parity)
- Never edit user-level skills
````

## 1.2 Логика PowerShell-скрипта (`report.ps1`, ~380 строк)

### Параметры

```powershell
param(
    [ValidateSet('', 'live', 'deploy')]
    [string]$Source = 'live',
    [ValidateSet('table', 'markdown', 'json')]
    [string]$Format = 'table',
    [string]$Agent = '',
    [string]$Role = '',
    [string]$Model = '',
    [string]$AgentsDir = '',
    [string]$Arch = '',
    [string]$Config = ''
)
```

### Хелперы (копия verbatim)

`Read-RawText`, `Split-ModelKey`, `Get-FmModel`, `Split-Tokens`, repo-root блок (см. Architecture).

### Новые хелперы (полный код — реализовывать как есть)

**Get-SectionText** — текст секции от start-заголовка до следующего `## ` (используется также в visualize):

```powershell
function Get-SectionText([string]$Text, [string]$StartPat, [string]$EndPat) {
    $m = [regex]::Match($Text, $StartPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $m.Success) { return $null }
    $after = $Text.Substring($m.Index + $m.Length)
    $e = [regex]::Match($after, $EndPat, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($e.Success) { return $after.Substring(0, $e.Index) }
    return $after
}
```
Вызов: `Get-SectionText $archText '(?m)^## Model Roles' '(?m)^## '`. Якорь `^## ` (пробел после ##) НЕ матчит `###` — вложенные заголовки остаются внутри секции.

**Get-ModelRoleMap** — парсер таблицы Model Roles (role/tier/archModel на агента):

```powershell
function Get-ModelRoleMap([string]$ArchText) {
    $sec = Get-SectionText $ArchText '(?m)^## Model Roles' '(?m)^## '
    if ($null -eq $sec) { return $null }
    $map = @{}; $roles = @()
    foreach ($ln in ($sec -split '\r?\n')) {
        if ($ln -notmatch '^\|') { continue }
        $cells = @($ln.Split('|') | ForEach-Object { $_.Trim() })
        if ($cells.Count -lt 5) { continue }
        $r = $cells[1]; $m = $cells[2]; $t = $cells[3]; $ags = $cells[4]
        if (-not $r -or $r -eq 'Role' -or $r -match '^-+$') { continue }
        if ($t -ne 'top' -and $t -ne 'mid' -and $t -ne 'low') { continue }
        $roles += , @{ Role = $r; Model = $m; Tier = $t }
        foreach ($a in (Split-Tokens $ags)) {
            $map[$a] = @{ Role = $r; Tier = $t; ArchModel = $m }
        }
    }
    if ($roles.Count -eq 0) { return $null }
    return @{ Map = $map; Roles = $roles }
}
```
Ячейки модели содержат пробелы/скобки (`GLM-5.3 (res)`) — split по `|` их не трогает; сравнение потом байтовое.

**Get-WhitelistNames** — имена из whitelist-таблицы (модификация Get-WhitelistCount из check.ps1 L141):

```powershell
function Get-WhitelistNames([string]$ArchText, [string]$Primary) {
    $headerPat = '(?m)^### ' + [regex]::Escape($Primary) + ' Whitelist \(\d+ agents\)'
    $hm = [regex]::Match($ArchText, $headerPat)
    if (-not $hm.Success) { return $null }
    $after = $Text = $ArchText.Substring($hm.Index + $hm.Length)
    $firstPipe = [regex]::Match($after, '(?m)^\|')
    if (-not $firstPipe.Success) { return @() }
    $rest = $after.Substring($firstPipe.Index)
    $blank = [regex]::Match($rest, '\r?\n[ \t]*\r?\n')
    $tbl = if ($blank.Success) { $rest.Substring(0, $blank.Index) } else { $rest }
    $names = @()
    foreach ($rm in [regex]::Matches($tbl, '(?m)^\|\s*\d+\s*\|\s*([^|]+?)\s*\|')) {
        $names += $rm.Groups[1].Value.Trim()
    }
    return $names
}
```
Header-строка (`| Agent Name | Role |`) и сепаратор (`|---|`) не матчат `^\|\s*\d+\s*\|` — фильтрация не нужна.

**Get-TaskAllowNames** — имена allow-ключей из opencode.json (для cross-check; Count-TaskAllow из check.ps1 считает количество, здесь нужны имена):

```powershell
function Get-TaskAllowNames($CfgObj, [string]$Primary) {
    try {
        $node = $CfgObj.agent.$Primary.permission.task
        if (-not $node) { return $null }
        return @($node.PSObject.Properties |
            Where-Object { $_.Name -ne '*' -and [string]$_.Value -eq 'allow' } |
            ForEach-Object { $_.Name })
    } catch { return $null }
}
```

**Get-FmPermissionFlat** — мини-YAML: flatten блока `permission:` из frontmatter в dot-path пары (YAML-модуля нет ни в PS, ни в stdlib Python — парсер идентичен в обоих зеркалах):

```powershell
function Get-FmPermissionFlat([string]$Text) {
    $fm = [regex]::Match($Text, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $fm.Success) { return @() }
    $out = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.List[object]  # @{Indent;Key}
    $inPerm = $false
    foreach ($ln in [regex]::Split($fm.Groups[1].Value, '\r?\n')) {
        if ($ln -match '^\s*$') { continue }
        $indent = $ln.Length - $ln.TrimStart().Length
        $trimmed = $ln.Trim()
        if (-not $inPerm) {
            if ($indent -eq 0 -and $trimmed -match '^permission:\s*$') { $inPerm = $true }
            continue
        }
        if ($indent -eq 0) { break }   # следующий top-level ключ завершает блок
        if ($trimmed -notmatch '^("[^"]+"|[^:]+):\s*(.*)$') { continue }
        $key = $Matches[1].Trim('"')
        $val = $Matches[2].Trim().Trim('"')
        while ($stack.Count -gt 0 -and $stack[$stack.Count - 1].Indent -ge $indent) {
            $stack.RemoveAt($stack.Count - 1)
        }
        $path = ((@($stack | ForEach-Object { $_.Key })) + $key) -join '.'
        if ($val) { $out.Add("$path=$val") }
        else { $stack.Add(@{ Indent = $indent; Key = $key }) }
    }
    return @($out)
}
```
Пример: worker.md → `edit=allow; bash.*=allow; bash.git commit*=deny; bash.git push*=deny`; dev-planner.md → `edit.*=ask; edit.*.md=allow; bash=deny; task.*=deny; task.view-image=allow; task.scout=allow`.

**Format-AgentTable** — рендер выровненной таблицы (скетч, механика простая):

```powershell
function Format-AgentTable($Rows) {
    $cols = @('AGENT', 'MODEL', 'ROLE', 'TIER', 'MODE', 'ROUTE', 'PERMISSIONS')
    $w = @{}
    foreach ($c in $cols) { $w[$c] = $c.Length }
    foreach ($r in $Rows) { foreach ($c in $cols) {
        $l = ("$($r.$c)").Length; if ($l -gt $w[$c]) { $w[$c] = $l } } }
    $sep = '+' + (($cols | ForEach-Object { '-' * ($w[$_] + 2) }) -join '+') + '+'
    $lines = @($sep)
    $lines += '| ' + (($cols | ForEach-Object { $_.PadRight($w[$_]) }) -join ' | ') + ' |'
    $lines += $sep
    foreach ($r in $Rows) {
        $lines += '| ' + (($cols | ForEach-Object { ("$($r.$_)").PadRight($w[$_]) }) -join ' | ') + ' |'
    }
    $lines += $sep
    return $lines
}
```

### Main flow

```
1. Валидация комбинаций: $Agent -and ($Role -or $Model) -> ERROR:COMBINATION + exit 2;
   $Source -ne 'live' -and $AgentsDir -> ERROR:COMBINATION + exit 2
2. repoRoot; $agentsDir = $AgentsDir | (Source=deploy -> <repo>\deploy-package\agents) | ($liveDir\agents)
   Test-Path dir, *.md count > 0 -> иначе ERROR:ENV + exit 2
3. $archPath = $Arch | <repo>\ARCHITECTURE.md; Read-RawText; 
   Get-ModelRoleMap -> $null => ERROR:ANCHOR model_roles + exit 2
   Get-WhitelistNames 'orchestrator' -> $null => ERROR:ANCHOR whitelist_orchestrator + exit 2
   Get-WhitelistNames 'plankestrator' -> $null => ERROR:ANCHOR whitelist_plankestrator + exit 2
4. $cfgPath = $Config | $liveDir\opencode.json; если существует -> ConvertFrom-Json
   (ошибка парсинга/нет файла -> WARN:CROSSCHECK_SKIPPED reason=..., $cfg=$null)
   $jsonOrch = Get-TaskAllowNames $cfg 'orchestrator'; $jsonPlan = ...
   Сравнить НАБОРЫ (sorted join) arch vs json -> WARN:ROUTING_MISMATCH primary=<p> arch_only=[...] json_only=[...]
5. STATUS:REPORT_START source=<s> agents=<n> arch=<relpath>
6. ForEach agent-файл (sorted by BaseName):
   - Read-RawText; Get-FmModel -> $model ($null -> WARN:FM_NO_MODEL agent=<n>, model='<missing>')
   - mode: regex '(?m)^mode:[ \t]*(.*)$' внутри fm-блока (default 'subagent')
   - Get-FmPermissionFlat -> $perms
   - role/tier: $roleMap.Map[$name] -> нет: WARN:ROLE_UNMAPPED, role='<unmapped>', tier='?'
   - drift: ArchModel -cne $model -> WARN:ROLE_MODEL_DRIFT agent=<n> arch=<a> frontmatter=<f> (байтовое сравнение!)
   - routing: inOrch/inPlan -> 'orch'|'plan'|'both'|'-'
7. Фильтры: -Agent (exact -ceq; не найден -> ERROR:AGENT_NOT_FOUND + exit 2); -Role exact; -Model substring ci
8. Distribution по ПОЛНОМУ набору: model_dist (group by model, sort count desc/model asc),
   role_dist (порядок строк таблицы Model Roles)
9. Рендер тела:
   - table: Format-AgentTable + секции '== MODEL DISTRIBUTION ==' / '== ROLE DISTRIBUTION =='
   - markdown: '## Agents' md-таблица (permissions полные, ';' join) + '## Model distribution' + '## Role distribution'
   - json: ConvertTo-Json -Depth 6 ЕДИНСТВЕННЫМ документом (токены НЕ печатаются; warnings внутри)
10. В table/markdown дополнительно токен-строки MODEL_DIST:<model> count=<n> agents=<csv> и ROLE_DIST:<role> tier=<t> count=<n> agents=<csv>
11. SUMMARY:agents=<n> shown=<m> models=<k> roles=<r> orch=25 plan=10 both=<b> none=<x> unmapped=<u> warn=<w>
    STATUS:SUCCESS; exit 0
```

## 1.3 Логика Python-скрипта (`report.py`, ~340 строк)

- argparse: `--source {live,deploy}` (default live), `--format {table,markdown,json}` (default table), `--agent`, `--role`, `--model`, `--agents-dir`, `--arch`, `--config`.
- Функции-зеркала: `read_raw`, `get_fm_model`, `split_model_key`, `split_tokens`, `repo_root` (verbatim-копии) + `get_section_text`, `get_model_role_map`, `get_whitelist_names`, `get_task_allow_names` (json-обход: `cfg['agent'][primary]['permission']['task']`, dict comprehension), `get_fm_permission_flat`:

```python
def get_fm_permission_flat(text):
    fm = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not fm:
        return []
    out, stack, in_perm = [], [], False
    for ln in re.split(r'\r?\n', fm.group(1)):
        if not ln.strip():
            continue
        indent = len(ln) - len(ln.lstrip())
        trimmed = ln.strip()
        if not in_perm:
            if indent == 0 and re.match(r'^permission:\s*$', trimmed):
                in_perm = True
            continue
        if indent == 0:
            break
        m = re.match(r'^("[^"]+"|[^:]+):\s*(.*)$', trimmed)
        if not m:
            continue
        key, val = m.group(1).strip('"'), m.group(2).strip().strip('"')
        while stack and stack[-1][0] >= indent:
            stack.pop()
        path = '.'.join([k for _, k in stack] + [key])
        if val:
            out.append('%s=%s' % (path, val))
        else:
            stack.append((indent, key))
    return out
```

- Рендер таблицы: тот же алгоритм padding (`str.ljust`), разделители `+---+`; markdown/json — идентичные структуры. JSON: `json.dumps(doc, ensure_ascii=False, indent=2)` — единственный вывод.
- Порядок обхода, токены, WARNING-строки, SUMMARY — БАЙТ-ИДЕНТИЧНЫ PS-версии (output parity: `diff <(pwsh report.ps1) <(python report.py)` различается только разделителями путей).

## 1.4 Gates и exit codes

| Ситуация | Токен | Exit |
|---|---|---|
| `-Agent` + `-Role`/`-Model`; `-Source` + `-AgentsDir` | `ERROR:COMBINATION` | 2 |
| agents dir / ARCHITECTURE.md отсутствуют, dir пуст | `ERROR:ENV` | 2 |
| Якорь `## Model Roles` / whitelist-заголовки не найдены | `ERROR:ANCHOR <name>` | 2 |
| `-Agent` не найден (token-exact) | `ERROR:AGENT_NOT_FOUND` | 2 |
| ROLE_UNMAPPED / ROLE_MODEL_DRIFT / ROUTING_MISMATCH / FM_NO_MODEL / CROSSCHECK_SKIPPED | `WARN:...` | не влияет (0) |
| Успех | `STATUS:SUCCESS` | 0 |

Exit 3 НЕТ — отчёт не гейтит.

## 1.5 Тестовые сценарии (agent-report)

Все команды из repo root; после каждого — `$LASTEXITCODE`.

1. **Базовый table:** `& ".opencode\skills\agent-report\scripts\report.ps1"` → 37 строк; exit 0; spot-check: `worker` → model `bifrost-litellm/stepfun/step-5-preview`, role `executor-step5`, tier `low`, route `orch`; `scout` → route `-`; `view-image` → route `both`; `advisor` → route `orch`.
2. **JSON:** `... -Format json | ConvertFrom-Json` → парсится; `.agents.Count -eq 37`; `.summary.models -eq 10`; в выводе НЕТ токенов `STATUS:`.
3. **Markdown:** `... -Format markdown` → содержит `## Agents`, `## Model distribution`, `## Role distribution`; permissions полные (без `+N` truncation).
4. **Одиночный агент:** `... -Agent worker` → 1 строка, exit 0; `... -Agent nosuch` → `ERROR:AGENT_NOT_FOUND`, exit 2.
5. **Фильтр роли:** `... -Role executor-cheap` → shown=10 (execute-bug, utility, mcp-github, mcp-read, mcp-search, summarizer, devops-agent, devops-readonly, view-image, git-commit); SUMMARY agents=37 shown=10; distributions считаются по всем 37.
6. **Фильтр модели:** `... -Model "GLM-5.3"` → plan-bug, plan-reviewer-simple, research-reviewer, dev-professor (4 агента, substring case-insensitive).
7. **Комбинация-гейт:** `... -Agent worker -Role docs` → exit 2.
8. **Deploy source:** `... -Source deploy` → exit 0; при синхронном дереве вывод идентичен live (кроме `source=deploy` и `agents_dir=`).
9. **WARN не влияет на exit:** проверить, что любой WARN (например ROLE_MODEL_DRIFT при существующем дрейфе) оставляет exit 0.
10. **PS/PY parity:** `python .opencode/skills/agent-report/scripts/report.py --format json` vs PS `-Format json` → идентичные наборы agents/model_dist/summary (кроме generated_utc/путей).

---

# Скилл 2: pipeline-visualize

## 2.1 Полное содержимое SKILL.md

````markdown
---
name: pipeline-visualize
description: 'Fast LLM-free ASCII visualization of every orchestration pipeline parsed from root ARCHITECTURE.md section "2. Pipelines" — step-chain diagrams where each agent step is annotated with its frontmatter model and Model Roles role/tier; prewalk pairs highlighted (planner-role step handing off to an equal-or-cheaper tier, e.g. dev-planner top ==> dev-professor mid); rework loops, parallel waves, wildcards and pseudo-steps rendered as distinct nodes; notation examples and decision-tree arrows excluded. Formats: ascii (default), markdown, json. Strictly read-only, runs in seconds. Exit 0 rendered, exit 2 usage/environment error.'
---

# Pipeline Visualize

Deterministic, LLM-free renderer of the orchestration pipelines defined in
root `ARCHITECTURE.md` `## 2. Pipelines`: ASCII step-chain diagrams with model
and tier annotations per agent step, prewalk handoffs highlighted, rework
loops and parallel waves as grouped nodes. Read-only — never writes.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Onboarding/overview: all pipelines with model costs at a glance
- Before/after model migrations: where cheap/expensive models sit in flows
- Prewalk audit: which planner→executor handoffs exist per pipeline
- Diagrams for plans/reviews/docs (-Format markdown / -Format json)

## When NOT to use

- Tier compliance validation (Check 11) — use the `consistency-checker` agent
- Fleet data (routing, permissions) — use `agent-report`
- Counters/pairs/integrity gating — use `integrity-check`
- Editing pipelines — ARCHITECTURE.md is edited manually via text anchors

## Parsing rules (what becomes a diagram)

| Rule | Detail |
|------|--------|
| Span | `## 2. Pipelines` → next `## ` heading (anchor missing → exit 2) |
| Labels | nearest `###` heading; a line prefix `NAME:` (e.g. `DOCS DEEP:`) overrides the label; duplicate labels get ` #N` suffix |
| Chains | lines containing an arrow (U+2192 or `->`); a line STARTING with an arrow CONTINUES the previous chain (multi-line fences) |
| Excluded spans | `### Pipeline Notation`, `### DEV Complexity Classification`, `### Auto-DOCS Hook` (syntax demos / decision tree / hook rule — not pipelines) |
| Excluded lines | lines containing `TRIAGE_RESULT`; chains with <2 tokens or ZERO agent/wildcard-resolved tokens |
| Annotations | parentheticals `(writes bug_plan.md)`, `(Kimi K3)` etc. dropped; markdown bullets/backticks/bold stripped |
| Loops | `[rework loop: a → b, max 3]` → LOOP node (inner text + max N) |
| Waves | `[a ∥ b ∥ c]` (U+2225 inside brackets) → WAVE node (parallel members) |
| Steps | exact agent name → AGENT node; `name-*` with >=1 prefix match → WILDCARD node; anything else (barrier, decompose, synthesis, RESEARCH.md) → PSEUDO node |

Models come from agent frontmatter (live by default; `-Source deploy` for
deploy-package); role/tier from root ARCHITECTURE.md `## Model Roles`.
Expected labels (WARN:PIPELINE_NOT_FOUND when absent, case-insensitive
substring over parsed labels): `BUGFIX (SIMPLE)`, `BUGFIX DEEP`, `DEV SIMPLE`,
`DEV COMPLEX`, `DEV SUPERCOMPLEX`, `DEVOPS`, `DOCS`, `PLAN`, `RESEARCH`.

## Prewalk highlighting

tierRank: top=3, mid=2, low=1 (`?`=unmapped — never analyzed). For adjacent
AGENT-resolved steps A → B (loops/waves/pseudo/wildcards skipped; loop
interiors not analyzed):

| Condition | Marker | Connector |
|-----------|--------|-----------|
| role(A) starts with `plan` or equals `docs-plan`, AND tierRank(A) >= tierRank(B) | `PREWALK:` | `==>` |
| role(A) starts with `plan` or equals `docs-plan`, AND tierRank(A) < tierRank(B) | `WARN:PREWALK_INVERSION` | `!-->` |
| otherwise tierRank(A) > tierRank(B) | `INFO:TIER_DROP` | `~->` |
| otherwise | — | `-->` |

Compliance enforcement stays with consistency-checker Check 11 — markers here
are advisory. Canonical expected pairs: plan-bug ==> execute-bug (BUGFIX DEEP),
dev-planner ==> dev-professor (DEV COMPLEX), docs-planner ==> docs-writer
(DOCS DEEP, equal tier).

## Workflow

1. Resolve flags/paths (invalid → exit 2); read ARCHITECTURE.md
2. Extract §2 span (missing → exit 2); cut excluded subsections; scan lines →
   raw chain list (label/variant, continuations, loop/wave placeholders)
3. Filter (>=2 tokens, >=1 agent-resolved) / dedupe / label `#N` suffixes;
   expected-label check (WARN)
4. Resolve steps: model via frontmatter (`model=<missing>` → WARN:STEP_NO_MODEL),
   role/tier via Model Roles (WARN:ROLE_UNMAPPED), wildcards (WARN:STEP_UNRESOLVED
   kind=wildcard matches=N), pseudo/unknown (WARN:STEP_UNRESOLVED kind=pseudo|unknown)
5. Detect prewalk / inversion / tier-drop pairs
6. Render per -Format; `-Pipeline` filter (zero matches → exit 2); SUMMARY; exit 0

## Usage

```powershell
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1"
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Pipeline "DEV COMPLEX"
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Format markdown
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Format json
& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1" -Source deploy -NoModels
```

### POSIX mirror

```bash
python .opencode/skills/pipeline-visualize/scripts/visualize.py [--pipeline SUBSTR] [--format ascii|markdown|json] [--source live|deploy] [--no-models]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Pipeline <substr>` | render only pipelines whose label contains substr (case-insensitive); zero matches → exit 2 |
| `-Format ascii\|markdown\|json` | output format (default ascii) |
| `-Source live\|deploy` | agents dir for models (default live) |
| `-AgentsDir <dir>` | explicit agents dir (overrides `-Source`) |
| `-NoModels` | compact boxes: index+name and tier only |
| `-Arch <path>` | ARCHITECTURE.md (default: repo root) |

## Output format

ascii/markdown modes:

```
STATUS:VIS_START arch=ARCHITECTURE.md pipelines=12 agents_source=live
=== DEV COMPLEX (8 steps) ===
+-------------------+     +---------------------+
| 1. dev-planner    | ==> | 2. dev-professor    | --> ...
|    qwen3.8-max    |     |    GLM-5.3 (res)    |
|    top            |     |    mid              |
+-------------------+     +---------------------+
LEGEND: --> seq | ==> prewalk | ~-> tier drop | !--> INVERSION | LOOP/WAVE boxes
PIPELINE:DEV COMPLEX steps=8 agents=7 pseudo=0 loops=1 waves=0 prewalk=1 drops=1
PREWALK:DEV COMPLEX dev-planner(plan-strong,top) ==> dev-professor(executor-strong,mid)
INFO:TIER_DROP:DEV COMPLEX dev-reviewer(top) -> rework(low)
WARN:PIPELINE_NOT_FOUND name=<expected>
WARN:STEP_UNRESOLVED pipeline=PLAN step=plan-writer-* kind=wildcard matches=2
SUMMARY:pipelines=12 steps=84 agents=70 pseudo=6 loops=6 waves=1 prewalk=3 inversions=0 drops=8 unresolved=6 warn=6
STATUS:SUCCESS
```

json mode emits ONLY: `{generated_utc, arch, source, pipelines:[{label,
steps:[{kind,name,model,role,tier,loop:{text,max}|null,wave:[names]|null}],
prewalk:[{from,to,from_tier,to_tier}], tier_drops:[...]}], warnings:[],
summary:{...}}`

markdown mode: per pipeline `### <LABEL>` + fenced ```text block (same ASCII)
+ step table `| # | Step | Kind | Model | Role | Tier |` + `**Prewalk:**` /
`**Tier drops:**` bullet lists.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Diagrams rendered (WARN/INFO allowed) |
| 2 | Usage/environment error (bad flags, ARCHITECTURE.md or agents dir missing, `## 2. Pipelines` / `## Model Roles` anchors absent, `-Pipeline` matched nothing) |

No exit 3 — visualization does not gate (WARN:PREWALK_INVERSION is advisory;
authoritative enforcement is consistency-checker Check 11).

## Hard rules

- STRICTLY READ-ONLY: never writes, fixes or deletes anything
- No LLM, no network — deterministic parsing/rendering only (seconds)
- OUTPUT IS ASCII-ONLY (`->`, `==>`, `+`, `|`): unicode arrows U+2192/U+2225
  are INPUT syntax, never printed (console cp866/cp1251 safety); script
  SOURCES contain no unicode literals — `\u2192`/`\u2225` escapes only
- Agent/model names byte-exact (`GLM-5.3 (res)`, `Kimi K3`); `[regex]::Escape()`/
  `re.escape()` in every pattern; token-exact step matching (no fuzzy)
- Displayed model = model key WITHOUT the provider prefix (split on first `/`);
  frontmatter is the only model authority
- Excluded-span headings and the expected-pipeline label list are script-top
  constants — update them together with this SKILL.md when §2 legitimately changes
- WARN/INFO never change the exit code
- PS and PY mirrors produce byte-identical diagrams (output parity)
- Never edit user-level skills
````

## 2.2 Логика PowerShell-скрипта (`visualize.ps1`, ~520 строк)

### Параметры

```powershell
param(
    [string]$Pipeline = '',
    [ValidateSet('ascii', 'markdown', 'json')]
    [string]$Format = 'ascii',
    [ValidateSet('', 'live', 'deploy')]
    [string]$Source = 'live',
    [string]$AgentsDir = '',
    [switch]$NoModels,
    [string]$Arch = ''
)
```

### Константы (top of script)

```powershell
$Arrow = [string][char]0x2192          # единственный способ получить '→' без литерала
$Par   = [string][char]0x2225          # '∥'
$SkipHeadings = @('Pipeline Notation', 'DEV Complexity Classification', 'Auto-DOCS Hook')
$ExpectedLabels = @('BUGFIX (SIMPLE)', 'BUGFIX DEEP', 'DEV SIMPLE', 'DEV COMPLEX',
                    'DEV SUPERCOMPLEX', 'DEVOPS', 'DOCS', 'PLAN', 'RESEARCH')
$TierRank = @{ 'low' = 1; 'mid' = 2; 'top' = 3 }
```

### Хелперы (копия verbatim)

`Read-RawText`, `Get-FmModel`, `Split-ModelKey`, `Split-Tokens`, `Invoke-Native`, repo-root блок; `Get-SectionText` + `Get-ModelRoleMap` — из report.ps1 §1.2 (та же реализация; скиллы self-contained — дублирование СОЗНАТЕЛЬНОЕ).

### Новые хелперы

**Get-PipelineChains** — линейный сканер §2 (самый сложный узел; полный код):

```powershell
function Get-PipelineChains([string]$SecText) {
    # Возвращает список @{Label; Variant; Raw} — сырые цепочки без нормализации
    $chains = @()
    $label = ''; $skip = $false; $buf = $null
    foreach ($ln in ($SecText -split '\r?\n')) {
        if ($ln -match '^###\s+(.+?)\s*$') {
            if ($buf) { $chains += , $buf; $buf = $null }
            $label = $Matches[1]
            $skip = $false
            foreach ($sh in $script:SkipHeadings) { if ($label.StartsWith($sh)) { $skip = $true } }
            continue
        }
        if ($skip) { continue }
        if ($buf -and $ln -match 'TRIAGE_RESULT') { $chains += , $buf; $buf = $null; continue }
        if (-not $ln -and $ln.Trim() -eq '') { continue }
        $t = $ln.Trim()
        if (-not $t) { continue }
        $t = $t -replace '^[-*]\s+', ''
        $t = $t -replace '`', ''
        $t = $t -replace '\*\*', ''
        $arrowAlt = '\u2192|->'
        $isCont = [regex]::IsMatch($t, '^(?:' + $arrowAlt + ')')
        $hasArrow = [regex]::IsMatch($t, '(?:' + $arrowAlt + ')')
        if ($buf -and $isCont) { $buf.Raw = $buf.Raw + ' ' + $t; continue }
        if ($buf) { $chains += , $buf; $buf = $null }
        if (-not $hasArrow) { continue }
        $variant = ''; $raw = $t
        $vm = [regex]::Match($t, '^([^\u2192:]{1,60}):\s*(.+)$')
        if ($vm.Success -and [regex]::IsMatch($vm.Groups[2].Value, '(?:\u2192|->)')) {
            $variant = $vm.Groups[1].Value.Trim(); $raw = $vm.Groups[2].Value
        }
        $buf = @{ Label = $label; Variant = $variant; Raw = $raw }
    }
    if ($buf) { $chains += , $buf }
    return $chains
}
```
Логика: заголовок `###` сбрасывает буфер и переключает label/skip; строка, начинающаяся со стрелки, — продолжение предыдущей цепочки (многострочный fence DOCS DEEP); префикс `NAME:` до первой стрелки — вариант-label (`DOCS SIMPLE:`, `Without plan:`); строки `TRIAGE_RESULT` сбрасывают буфер и пропускаются.

**Convert-RawToNodes** — нормализация цепочки в узлы (полный код; while-циклы вместо MatchEvaluator для PS 5.1-совместимости):

```powershell
function Convert-RawToNodes([string]$Raw, [string[]]$AgentNames) {
    $loops = @{}; $waves = @{}
    # 1) [rework loop: ...] -> <<Ln>> (внутренние стрелки сохраняются ВНУТРИ placeholder)
    $i = 0
    while (($idx = $Raw.IndexOf('[rework loop:')) -ge 0) {
        $end = $Raw.IndexOf(']', $idx)
        if ($end -lt 0) { break }
        $inner = $Raw.Substring($idx + 13, $end - $idx - 13)
        $loops["L$i"] = $inner.Trim(); $Raw = $Raw.Remove($idx, $end - $idx + 1).Insert($idx, "<<L$i>>")
        $i++
    }
    # 2) волны: [...] содержащие U+2225 -> <<Wn>>
    $i = 0
    while ($true) {
        $m = [regex]::Match($Raw, '\[[^\[\]]*\u2225[^\[\]]*\]')
        if (-not $m.Success) { break }
        $waves["W$i"] = $m.Value.Substring(1, $m.Value.Length - 2)
        $Raw = $Raw.Remove($m.Index, $m.Length).Insert($m.Index, "<<W$i>>")
        $i++
    }
    # 3) выбросить пояснения в скобках и мусорную пунктуацию
    $Raw = [regex]::Replace($Raw, '\([^)]*\)', '')
    $Raw = $Raw -replace '[\[\]"]', ''
    # 4) split по стрелкам, классификация токенов
    $parts = [regex]::Split($Raw, '\s*(?:\u2192|->)\s*')
    $nodes = @()
    foreach ($p in $parts) {
        $s = $p.Trim().Trim(',').Trim()
        if (-not $s) { continue }
        if ($s -match '^<<L(\d+)>>$') {
            $inner = $loops["L$($Matches[1])"]
            $mm = [regex]::Match($inner, ',?\s*max\s+(\d+)\s*$')
            $maxN = 0; $body = $inner
            if ($mm.Success) { $maxN = [int]$mm.Groups[1].Value; $body = $inner.Substring(0, $mm.Index).Trim() }
            $nodes += , @{ Kind = 'loop'; Text = $body; Max = $maxN }
            continue
        }
        if ($s -match '^<<W(\d+)>>$') {
            $members = @($waves["W$($Matches[1])"] -split '\u2225' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $nodes += , @{ Kind = 'wave'; Members = $members }
            continue
        }
        if ($s -cmatch '^[a-z][a-z0-9-]*$' -and $AgentNames -ccontains $s) {
            $nodes += , @{ Kind = 'agent'; Name = $s }
            continue
        }
        if ($s -match '^([a-z][a-z0-9-]+)-\*$') {
            $prefix = $Matches[1] + '-'
            $hits = @($AgentNames | Where-Object { $_.StartsWith($prefix) })
            if ($hits.Count -ge 1) { $nodes += , @{ Kind = 'wildcard'; Name = $s; Matches = $hits }; continue }
        }
        $nodes += , @{ Kind = 'pseudo'; Name = $s }
    }
    return $nodes
}
```
Классификация token-exact: `-ccontains` (case-sensitive) для имён агентов; `barrier`, `decompose`, `synthesis`, `RESEARCH.md`, `continue ...` → pseudo.

**Get-PrewalkPairs** — детектор по rules из SKILL.md:

```powershell
function Get-PrewalkPairs($Nodes, $RoleMap) {
    $pairs = @()
    for ($i = 0; $i -lt $Nodes.Count - 1; $i++) {
        $a = $Nodes[$i]; $b = $Nodes[$i + 1]
        if ($a.Kind -ne 'agent' -or $b.Kind -ne 'agent') { continue }
        if (-not $RoleMap.ContainsKey($a.Name) -or -not $RoleMap.ContainsKey($b.Name)) { continue }
        $ra = $RoleMap[$a.Name]; $rb = $RoleMap[$b.Name]
        if (-not $TierRank.ContainsKey($ra.Tier) -or -not $TierRank.ContainsKey($rb.Tier)) { continue }
        $ta = $TierRank[$ra.Tier]; $tb = $TierRank[$rb.Tier]
        $isPlanner = ($ra.Role.StartsWith('plan') -or $ra.Role -eq 'docs-plan')
        if ($isPlanner -and $ta -ge $tb) { $pairs += , @{ Kind = 'prewalk';   I = $i; A = $a.Name; B = $b.Name } }
        elseif ($isPlanner)              { $pairs += , @{ Kind = 'inversion'; I = $i; A = $a.Name; B = $b.Name } }
        elseif ($ta -gt $tb)             { $pairs += , @{ Kind = 'drop';      I = $i; A = $a.Name; B = $b.Name } }
    }
    return $pairs
}
```

**Render-NodeBox / Join-Boxes** — ASCII-рендер (скетч + правила):

```powershell
function Render-NodeBox($Node, $Idx, $Info, [switch]$NoModels) {
    # Возвращает string[] строк бокса. Правила ширины:
    #   agent:    строки '<Idx>. <Name>' / '<ModelKey>' / '<Tier>'  (ModelKey = Split-ModelKey(model).Key; '-' если <missing>; NoModels -> без строки модели)
    #   wildcard: '<Idx>. <Name>' / '<N> agents'
    #   pseudo:   '<Name>'
    #   loop:     'LOOP max <N>:' + Text (Text может содержать '->' — внутренние стрелки рендерятся ASCII '->')
    #   wave:     'WAVE (parallel):' + members join ' | '
    # ширина = max(len(строк)) + 2 (по одному пробелу слева/справа); рамки '+'/'-'/'|'
}
function Join-Boxes([object[]]$Boxes, [string[]]$Conns) {
    # Все боксы дополняются пустыми строками до max-высоты;
    # коннектор (' --> ', ' ==> ', ' ~-> ', ' !-> ') печатается в строке вертикального центра боксов;
    # в остальных строках — пробелы той же ширины. Результат: string[] строк диаграммы.
}
```

### Main flow

```
1. Флаги: -Source + -AgentsDir -> exit 2. repoRoot.
2. $archText = Read-RawText($Arch | <repo>\ARCHITECTURE.md)  (нет файла -> ERROR:ENV exit 2)
   $sec2 = Get-SectionText $archText '(?m)^## 2\. Pipelines' '(?m)^## '   ($null -> ERROR:ANCHOR pipelines, exit 2)
   $roleInfo = Get-ModelRoleMap $archText                                 ($null -> ERROR:ANCHOR model_roles, exit 2)
3. agentsDir (live/deploy/explicit); нет/пуст -> ERROR:ENV exit 2
   $agentNames = BaseName всех *.md (sorted); $modelByName: Get-FmModel каждого файла
4. $chains = Get-PipelineChains $sec2
   ForEach chain: $nodes = Convert-RawToNodes chain.Raw $agentNames
   ФИЛЬТР: nodes.Count >= 2 И хотя бы один Kind in (agent, wildcard) — иначе отбросить
   Label: Variant ? Variant : Label; дубликаты label -> ' #2', ' #3' (порядок появления)
   Дедуп: одинаковые (label-independent) последовательности токенов -> оставить первую (gлотает повтор fan-out в 'Wave → Barrier → Synthesis Pattern')
5. Expected-check: для каждого $ExpectedLabels — хотя бы один parsed label содержит его (ci) -> иначе WARN:PIPELINE_NOT_FOUND name=<l>
6. -Pipeline фильтр (ci substring по label); 0 совпадений -> ERROR:NO_MATCH exit 2
7. ForEach pipeline: обогатить узлы (model/role/tier из $modelByName/$roleInfo.Map);
   unresolved/unknown/pseudo/wildcard -> WARN:STEP_UNRESOLVED pipeline=<l> step=<s> kind=<k> [matches=N]
   model=<missing> -> WARN:STEP_NO_MODEL
   $pairs = Get-PrewalkPairs; PREWALK:/WARN:PREWALK_INVERSION:/INFO:TIER_DROP: токены
8. Рендер:
   ascii:     '=== <LABEL> (<n> steps) ===' + Join-Boxes + LEGEND-строка (один раз в конце всего вывода)
   markdown:  '### <LABEL>' + fenced ```text (тот же ascii) + таблица шагов '| # | Step | Kind | Model | Role | Tier |' + bullets Prewalk/Tier drops
   json:      единственный документ (структура из SKILL.md), ConvertTo-Json -Depth 8
9. PIPELINE:<label> steps=<n> agents=<n> pseudo=<n> loops=<n> waves=<n> prewalk=<n> drops=<n>  (ascii/markdown)
10. SUMMARY:pipelines=... steps=... agents=... pseudo=... loops=... waves=... prewalk=... inversions=... drops=... unresolved=... warn=...
    STATUS:SUCCESS; exit 0
```

Порядок строк вывода: `STATUS:VIS_START` → все блоки диаграмм с их `PIPELINE:`/`PREWALK:`/`INFO:`/`WARN:` строками → LEGEND → SUMMARY → STATUS:SUCCESS.

## 2.3 Логика Python-скрипта (`visualize.py`, ~470 строк)

- argparse: `--pipeline`, `--format {ascii,markdown,json}`, `--source {live,deploy}`, `--agents-dir`, `--no-models`, `--arch`.
- Константы: `ARROW = '\u2192'`, `PARALLEL = '\u2225'`, `SKIP_HEADINGS`, `EXPECTED_LABELS`, `TIER_RANK = {'low':1,'mid':2,'top':3}`.
- Зеркала: `get_section_text`, `get_model_role_map` (identisch report.py), `get_pipeline_chains` (тот же конечный автомат; `re.match(r'^(?:\u2192|->)', t)`), `convert_raw_to_nodes` (в Python `re.sub` с lambda для placeholder'ов допустим — поведение тождественно while-версии PS), `get_prewalk_pairs`, `render_node_box`/`join_boxes`.
- Ключевое отличие PY: `str.split`/`re.split(r'\s*(?:\u2192|->)\s*', raw)`; nodes — list of dict.
- Диаграммы БАЙТ-ИДЕНТИЧНЫ PS-версии (тест parity — diff ascii-вывода).
- JSON: `json.dumps(..., ensure_ascii=False, indent=2)`.

## 2.4 Gates и exit codes

| Ситуация | Токен | Exit |
|---|---|---|
| `-Source` + `-AgentsDir` | `ERROR:COMBINATION` | 2 |
| ARCHITECTURE.md / agents dir отсутствуют или пусты | `ERROR:ENV` | 2 |
| Якоря `## 2. Pipelines` / `## Model Roles` не найдены | `ERROR:ANCHOR pipelines\|model_roles` | 2 |
| `-Pipeline` не сматчил ни одного label | `ERROR:NO_MATCH` | 2 |
| Ожидаемый label не найден среди распарсенных | `WARN:PIPELINE_NOT_FOUND` | 0 |
| Wildcard/pseudo/unknown шаг, модель отсутствует, ROLE_UNMAPPED | `WARN:STEP_UNRESOLVED` / `WARN:STEP_NO_MODEL` / `WARN:ROLE_UNMAPPED` | 0 |
| Prewalk-инверсия (planner tier < executor tier) | `WARN:PREWALK_INVERSION` | 0 (advisory; Check 11 — авторитет) |
| Успех | `STATUS:SUCCESS` | 0 |

Exit 3 НЕТ — визуализация не гейтит.

## 2.5 Тестовые сценарии (pipeline-visualize)

1. **Полный рендер:** `& ".opencode\skills\pipeline-visualize\scripts\visualize.ps1"` → exit 0; `WARN:PIPELINE_NOT_FOUND` ОТСУТСТВУЕТ для всех 9 expected labels; распознано ≥11 диаграмм (BUGFIX (SIMPLE), BUGFIX DEEP, DEV SIMPLE ×2 варианта, DEV COMPLEX, DEV SUPERCOMPLEX, DEVOPS, DOCS SIMPLE, DOCS DEEP, PLAN, RESEARCH + fan-out).
2. **Prewalk-подсветка (канонические пары):** в выводе есть `PREWALK:BUGFIX DEEP plan-bug(plan-flash,mid) ==> execute-bug(executor-cheap,low)`; `PREWALK:DEV COMPLEX dev-planner(plan-strong,top) ==> dev-professor(executor-strong,mid)`; `PREWALK:DOCS DEEP docs-planner(docs-plan,low) ==> docs-writer(docs,low)`; SUMMARY `prewalk=3` (как минимум); коннектор `==>` присутствует в диаграммах.
3. **Tier drop info:** `INFO:TIER_DROP:DEV COMPLEX dev-reviewer(top) -> rework(low)` присутствует; коннектор `~->`.
4. **Фильтр:** `-Pipeline "dev complex"` (lowercase) → ровно 1 диаграмма, exit 0; `-Pipeline nosuch` → `ERROR:NO_MATCH`, exit 2.
5. **Loop/wave узлы:** DEV COMPLEX содержит бокс `LOOP max 3:` с `rework -> consistency-checker`; RESEARCH fan-out — бокс `WAVE (parallel):` с 5 членами (mcp-search, mcp-read, mcp-github, devops-readonly, scout).
6. **Исключения не парсятся:** в выводе НЕТ диаграмм с шагами `Q1a`, `SUPERCOMPLEX`, `a`, `b` (notation/decision-tree); НЕТ цепочек из `TRIAGE_RESULT` строк; НЕТ диаграммы `Auto-DOCS Hook`.
7. **Форматы:** `-Format markdown` → `### DEV COMPLEX` + fenced text + таблица шагов; `-Format json | ConvertFrom-Json` → `.pipelines.Count >= 11`, у DEV COMPLEX `.steps` содержит элемент `kind=loop` с `max=3`.
8. **ASCII-безопасность:** вывод не содержит символов U+2192/U+2225 (проверка: `... | Select-String ([char]0x2192)` пусто).
9. **Deploy source:** `-Source deploy` → exit 0, модели из deploy-фронтматтеров.
10. **PS/PY parity:** ascii-выводы PS и PY совпадают байт-в-байт (`fc` / `diff`).

---

# Скилл 3: deploy-package-build

## 3.1 Полное содержимое SKILL.md

````markdown
---
name: deploy-package-build
description: 'Deterministic rebuild of deploy-package/ from live sources — byte-copies live agents (37), live opencode.json, live plugins/workflow-enforcement.ts and 4 root docs (ARCHITECTURE/AGENTS/MCP_SETUP/PLUGIN) into the package, SHA256-verifies every copy, regenerates HASHES.txt, and gates on counters (agents 37, distinct models 10, routing 25/10 across opencode.json + ARCHITECTURE.md + workflow-enforcement.ts) plus a literal-secrets scan of opencode.json. -Plan (default) reports SAME/CHANGED/NEW/STALE without writing; -Apply performs the build; -Archive additionally rebuilds deploy-package.7z via 7-Zip. Never deletes files, never runs git. Exit 0, exit 2 usage/environment, exit 3 gate/copy failure.'
---

# Deploy Package Build

Deterministic, LLM-free rebuild of `deploy-package/` from the live config and
root documentation: byte-copy + SHA256 verify + counter/secret gates +
HASHES.txt manifest + optional 7z archive. The package is the git-tracked
shipping artifact consumed by `deploy-package/scripts/install.ps1` on target
machines.

These skills are project-level: invoke them from the repo root via
`.opencode\skills\...` (not the user-level `~/.config/opencode/skills/...` root).

## When to use

- Packaging a release after config changes (agent-add, agent-model-migrate,
  plugin/doc edits) once the live state is known-good
- Refreshing deploy-package after `config-sync` confirmed live is the truth
- Producing HASHES.txt / deploy-package.7z for distribution
- Pre-release gate: counters + routing + secrets verified BEFORE shipping

## When NOT to use

- Syncing mirror CHAINS (root ↔ opencode-config ↔ deploy docs, 3-way plugin
  copies) — use `config-sync` (this skill copies live→deploy only)
- Backups/rollback — use `backup-snapshot`
- Full integrity audit (pair hashes, model keys) — use `integrity-check`
- Installing on a target machine — `deploy-package/scripts/install.ps1`

## Mapping (source → package)

| Source | Destination |
|--------|-------------|
| `~/.config/opencode/agents/*.md` (all, expected 37) | `deploy-package/agents/` |
| `~/.config/opencode/opencode.json` | `deploy-package/opencode.json` |
| `~/.config/opencode/plugins/workflow-enforcement.ts` | `deploy-package/plugins/workflow-enforcement.ts` |
| `<repo>/ARCHITECTURE.md`, `AGENTS.md`, `MCP_SETUP.md`, `PLUGIN.md` | `deploy-package/project-files/` |

Untouched (static): `scripts/`, `README.md`, `DEPLOYMENT_GUIDE.md`,
`plugins/package.json`, `plugins/node_modules/`. Out of scope: live
`plugins/package.json` / `plugins/node_modules` are NOT mirrored (documented
limitation — they change only on plugin dependency updates, handled manually).

## Gates (run in BOTH -Plan and -Apply; any BLOCK → exit 3, zero copies)

1. `GATE:JSON` — live opencode.json parses
2. `GATE:SECRETS` — literal-secret scan of live opencode.json:
   `"sk-..."`-style tokens (>=16 chars) and `"api_key|apikey|access_token|secret":
   "<literal>"` (value not starting with `$` / `YOUR_` / `{{`). Output NEVER
   prints secret values — pattern name + hit count only
3. `COUNT:agents_live` == `-ExpectedAgents` (default 37)
4. `COUNT:models_used` — distinct frontmatter models across live agents ==
   `-ExpectedModels` (default 10)
5. `COUNT:routing_orchestrator` — opencode.json task-allows == ARCHITECTURE.md
   header number == ARCHITECTURE.md table rows == plugin ROUTING_TABLES entries
   == `-ExpectedOrch` (default 25)
6. `COUNT:routing_plankestrator` — same, `-ExpectedPlan` (default 10)

## Workflow

### -Plan (default, zero writes)

1. Pre-check flags/paths (exit 2); run gates 1–6 (any BLOCK → exit 3)
2. Diff scan every mapped pair (SHA256 both sides):
   `SAME:<rel> sha=<8>` / `CHANGED:<rel> live=<8> deploy=<8>` / `NEW:<rel>` (dest missing)
3. STALE scan (deploy-only files in managed scopes — see Hard rules):
   `WARN:STALE:<rel>` (with `-Strict` → exit 3)
4. `PLAN:HASHES.txt files=<n>` (would-generate info)
5. `SUMMARY:mode=plan scanned=<n> same=<n> changed=<n> new=<n> stale=<n>` +
   `STATUS:PLAN_OK` exit 0

### -Apply

1. Pre-check + gates (as above; BLOCK → exit 3 before any copy)
2. Byte-copy CHANGED/NEW files only (SAME skipped — no churn); per file:
   `COPIED:<rel> sha=<8> bytes=<n>` + re-hash verify `VERIFY:<rel> identical`;
   copy error or hash mismatch → `ERROR:<rel>` + `STATUS:FAILED copied=<n>
   failed=<n>` exit 3 (copied files are KEPT — never deleted)
3. HASHES.txt regenerated over the package scope; content-equal → no rewrite
   (`SAME:HASHES.txt`), else `EDITED:HASHES.txt lines=<n>`; write failure → exit 3
4. STALE report; `SUMMARY:mode=apply scanned/same/changed/new/copied/stale/bytes`;
   `STATUS:SUCCESS`
5. `-Archive` (only after STATUS:SUCCESS): 7-Zip build (below)
6. `WARN:MANUAL` follow-ups: git commit via the `git-commit` agent
   (deploy-package changed); live-config changes take effect in a NEW opencode
   session; target install via `deploy-package/scripts/install.ps1`;
   recommended post-check: `integrity-check` + `deploy-package/scripts/verify.ps1`

### HASHES.txt

`<SHA256-UPPER>␣␣<rel/path>` — two spaces, forward slashes, sorted by rel,
LF endings, trailing LF (backup-snapshot-compatible format). Scope = ALL
package files EXCEPT `plugins/node_modules/**`, `deploy-package.7z`,
`*.tmp7z`, `HASHES.txt` itself.

### -Archive

7-Zip resolved via PATH, then `%ProgramFiles%\7-Zip\7z.exe`, then
`%ProgramFiles(x86)%\7-Zip\7z.exe` (none found → exit 2 in pre-check). Build
runs with repo root as working dir:

```
7z a -t7z -mx=5 deploy-package\deploy-package.7z.tmp7z deploy-package\* -xr!*.tmp7z -xr!deploy-package.7z
```

(includes node_modules for install parity; excludes the old archive and the
tmp). 7z exit >= 2 → `ERROR:ARCHIVE` exit 3 (tmp KEPT — never deleted).
Success → tmp atomically replaces `deploy-package\deploy-package.7z` (build
artifact overwrite), then `ARCHIVED:deploy-package.7z sha=<8> bytes=<n>`.

## Usage

```powershell
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Plan
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply -Archive
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Apply -Strict
& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Plan -ExpectedAgents 38
```

### POSIX mirror

```bash
python .opencode/skills/deploy-package-build/scripts/build.py --plan
python .opencode/skills/deploy-package-build/scripts/build.py --apply [--archive] [--strict] [--json]
```

## Parameters

| Param | Meaning |
|-------|---------|
| `-Plan` | report-only, zero writes (default when neither -Plan nor -Apply given) |
| `-Apply` | perform the build (copy + verify + HASHES.txt) |
| `-Archive` | with -Apply: rebuild deploy-package.7z (requires 7-Zip) |
| `-Strict` | STALE findings → exit 3 |
| `-ExpectedAgents <n>` | gate default 37 |
| `-ExpectedModels <n>` | gate default 10 |
| `-ExpectedOrch <n>` / `-ExpectedPlan <n>` | gate defaults 25 / 10 |
| `-Json` | JSON report instead of token lines (exit codes unchanged) |

## Gates

| Gate | Effect |
|------|--------|
| `-Plan` + `-Apply` together | BLOCK (exit 2) |
| `-Archive` without `-Apply` | BLOCK (exit 2) |
| Live dir / repo root / `deploy-package/` / any mapped source missing or unreadable | BLOCK (exit 2, zero copies) |
| 7-Zip not found with `-Archive` | BLOCK (exit 2) |
| GATE:JSON / GATE:SECRETS / any COUNT mismatch | BLOCK (exit 3, zero copies) |
| Copy error / SHA256 verify mismatch / HASHES.txt write failure | exit 3 (copies kept) |
| STALE deploy-only files | WARN (exit unchanged); with `-Strict` → exit 3 |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | -Plan clean report, or -Apply success (archive ok if requested) |
| 2 | Usage/environment error |
| 3 | Gate BLOCK, copy/verify failure, HASHES write failure, -Strict with STALE |

## Hard rules

- NEVER deletes any file (STALE deploy-only files are reported, not removed;
  a failed archive tmp is kept); overwriting mapped deploy-package copies and
  replacing the .7z build artifact are the ONLY mutations
- Byte-level copy (`[System.IO.File]::Copy` / `shutil.copyfile`) — CRLF/BOM
  preserved by construction; SHA256 verify after every copy
- Gates run BEFORE any copy; a blocked build writes nothing (zero-copy guarantee)
- Secret values are NEVER printed — pattern name + hit count only
- Counter parsers are verbatim copies of integrity-check helpers
  (`Count-TaskAllow` / `Get-WhitelistCount` / `Count-RoutingPlugin`) — skills
  are self-contained, no cross-skill imports; update together if anchors change
- STALE scopes: `deploy-package/agents/*.md` absent from live, and
  `project-files/*.md` outside the 4-doc mapping; everything else static
- HASHES.txt: LF-forced, sorted, two-space format — stable for git diffs
- Never runs git (commit via the `git-commit` agent); never touches live files
  (one-way live→deploy only)
- Expected counters are parameters (37/10/25/10 defaults) — after a legitimate
  architecture change, update the defaults in BOTH scripts and this file together
- Never edit user-level skills
````

## 3.2 Логика PowerShell-скрипта (`build.ps1`, ~560 строк)

### Параметры

```powershell
param(
    [switch]$Plan,
    [switch]$Apply,
    [switch]$Archive,
    [switch]$Strict,
    [int]$ExpectedAgents = 37,
    [int]$ExpectedModels = 10,
    [int]$ExpectedOrch = 25,
    [int]$ExpectedPlan = 10,
    [switch]$Json
)
```

### Хелперы (копия verbatim)

- Из migrate.ps1/snapshot.ps1: `Read-RawText`, `Write-RawText`, `Get-Sha256`, `Invoke-Native`, `Get-FmModel`, repo-root блок.
- Из check.ps1 (L125–153): `Count-TaskAllow`, `Count-RoutingPlugin`, `Get-WhitelistCount` — gate-парсеры routing-счётчиков (СОЗНАТЕЛЬНОЕ дублирование: скиллы self-contained).

### Новые хелперы

**Build-FileMap** — карта копирования (агенты — скан директории, без hardcode):

```powershell
function Build-FileMap([string]$LiveDir, [string]$RepoRoot, [string]$Pkg) {
    $map = @()
    $agentsLive = Join-Path $LiveDir 'agents'
    foreach ($f in (Get-ChildItem -LiteralPath $agentsLive -Filter '*.md' -File | Sort-Object Name)) {
        $map += , @{ Src = $f.FullName; Dst = (Join-Path $Pkg ('agents\' + $f.Name)); Rel = ('agents/' + $f.Name) }
    }
    $map += , @{ Src = (Join-Path $LiveDir 'opencode.json'); Dst = (Join-Path $Pkg 'opencode.json'); Rel = 'opencode.json' }
    $map += , @{ Src = (Join-Path $LiveDir 'plugins\workflow-enforcement.ts'); Dst = (Join-Path $Pkg 'plugins\workflow-enforcement.ts'); Rel = 'plugins/workflow-enforcement.ts' }
    foreach ($d in @('ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md')) {
        $map += , @{ Src = (Join-Path $RepoRoot $d); Dst = (Join-Path $Pkg ('project-files\' + $d)); Rel = ('project-files/' + $d) }
    }
    return $map
}
```

**Test-Secrets** — консервативный скан литеральных секретов (значения НИКОГДА не печатаются):

```powershell
function Test-Secrets([string]$JsonText) {
    $hits = @()
    $pats = @(
        @{ Name = 'sk-token';          Rx = '"sk-[A-Za-z0-9_\-]{16,}"' },
        @{ Name = 'literal-key-field'; Rx = '(?i)"(?:api[_-]?key|apikey|access[_-]?token|secret)"\s*:\s*"(?!\$)(?!YOUR_)(?!\{\{)[^"]{12,}"' }
    )
    foreach ($p in $pats) {
        $n = [regex]::Matches($JsonText, $p.Rx).Count
        if ($n -gt 0) { $hits += , @{ Pattern = $p.Name; Count = $n } }
    }
    return $hits
}
```

**Write-HashesFile** — генерация HASHES.txt (LF, sorted, two-space):

```powershell
function Write-HashesFile([string]$Pkg) {
    $entries = @()
    foreach ($f in (Get-ChildItem -LiteralPath $Pkg -Recurse -File)) {
        $rel = $f.FullName.Substring($Pkg.Length + 1) -replace '\\', '/'
        if ($rel -like 'plugins/node_modules/*') { continue }
        if ($rel -eq 'deploy-package.7z' -or $rel -eq 'HASHES.txt' -or $rel -like '*.tmp7z') { continue }
        $entries += , @{ Rel = $rel; Sha = (Get-Sha256 $f.FullName) }
    }
    $sorted = @($entries | Sort-Object { $_.Rel })
    $text = (($sorted | ForEach-Object { '{0}  {1}' -f $_.Sha, $_.Rel }) -join "`n") + "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)   # без BOM, LF
    $target = Join-Path $Pkg 'HASHES.txt'
    if ((Test-Path -LiteralPath $target)) {
        $old = [System.IO.File]::ReadAllBytes($target)
        if ($old.Length -eq $bytes.Length) {
            $same = $true
            for ($i = 0; $i -lt $bytes.Length; $i++) { if ($old[$i] -ne $bytes[$i]) { $same = $false; break } }
            if ($same) { return @{ Changed = $false; Lines = $sorted.Count } }
        }
    }
    [System.IO.File]::WriteAllBytes($target, $bytes)
    return @{ Changed = $true; Lines = $sorted.Count }
}
```

**Find-SevenZip**:

```powershell
function Find-SevenZip {
    $cmd = Get-Command '7z' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cands = @()
    if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
    if (${env:ProgramFiles(x86)}) { $cands += (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe') }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}
```

**Get-StaleFiles** — deploy-only файлы в управляемых scope:

```powershell
function Get-StaleFiles([string]$Pkg, [string[]]$LiveAgentNames) {
    $stale = @()
    $depAgents = Join-Path $Pkg 'agents'
    if (Test-Path -LiteralPath $depAgents) {
        foreach ($f in (Get-ChildItem -LiteralPath $depAgents -Filter '*.md' -File)) {
            if ($LiveAgentNames -notcontains $f.BaseName) { $stale += ('agents/' + $f.Name) }
        }
    }
    $pf = Join-Path $Pkg 'project-files'
    $allowedDocs = @('ARCHITECTURE.md', 'AGENTS.md', 'MCP_SETUP.md', 'PLUGIN.md')
    if (Test-Path -LiteralPath $pf) {
        foreach ($f in (Get-ChildItem -LiteralPath $pf -Filter '*.md' -File)) {
            if ($allowedDocs -notcontains $f.Name) { $stale += ('project-files/' + $f.Name) }
        }
    }
    return $stale
}
```

### Main flow

```
1. Флаги: $Plan -and $Apply -> ERROR:FLAGS exit 2; $Archive -and -not $Apply -> ERROR:FLAGS exit 2
   $mode = if ($Apply) {'apply'} else {'plan'}   # -Plan по умолчанию
2. Пути: repoRoot; $liveDir; $pkg = <repo>\deploy-package
   Pre-check (все Test-Path, иначе ERROR:ENV exit 2, zero copies):
   $liveDir, $liveDir\agents (не пуст), $liveDir\opencode.json, $liveDir\plugins\workflow-enforcement.ts,
   $pkg, $pkg\agents, $pkg\project-files, 4 root-дока, все Src из Build-FileMap
   Если -Archive: Find-SevenZip -> $null => ERROR:ENV sevenzip exit 2
3. STATUS:BUILD_START mode=<plan|apply> agents_expected=<n>
4. GATES (до единой записи):
   a. $cfgText = Read-RawText(live opencode.json); ConvertFrom-Json -> ошибка: GATE:JSON ... BLOCK
   b. Test-Secrets $cfgText -> hits: GATE:SECRETS file=opencode.json hits=<n> patterns=<csv> -> BLOCK (значения не печатаются)
      иначе GATE:JSON -> PASS, GATE:SECRETS hits=0 -> PASS
   c. COUNT:agents_live=<n> expected=<E> -> PASS|BLOCK        (Get-ChildItem live agents *.md)
   d. COUNT:models_used=<distinct Get-FmModel по live агентам> expected=<E> -> PASS|BLOCK
   e. COUNT:routing_orchestrator json=<Count-TaskAllow> arch_header=<Get-WhitelistCount.Header> arch_rows=<.Rows> plugin=<Count-RoutingPlugin по LIVE ts> expected=<E> -> PASS|BLOCK
      (plugin-якорь не распарсен -> WARN:routing plugin anchor not parsed, источник пропускается — как в check.ps1)
   f. То же для plankestrator
   Любой BLOCK -> SUMMARY:gates_failed=<n> + STATUS:BLOCKED gates=<n> + exit 3 (zero copies)
5. DIFF-скан (SHA256 Src vs Dst; Dst отсутствует -> NEW):
   plan и apply печатают SAME:/CHANGED:/NEW: (apply additionally COPIED:/VERIFY:)
6. STALE: Get-StaleFiles -> WARN:STALE:<rel> каждый; $Strict и stale>0 -> STATUS:BLOCKED stale=<n> exit 3 (в plan — до копий; в apply — ПОСЛЕ копий? НЕТ: strict-блок в обоих режимах ДО записи, шаг 6 выполняется сразу после 5)
7. mode=plan: PLAN:HASHES.txt files=<n> (прогноз scope) + SUMMARY:mode=plan scanned same changed new stale + STATUS:PLAN_OK exit 0
8. mode=apply:
   foreach CHANGED|NEW: New-Item dest dir (если нет); [System.IO.File]::Copy(Src,Dst,$true);
     Get-Sha256 Dst -ceq Get-Sha256 Src -> COPIED:<rel> sha=<8> bytes=<n> + VERIFY:<rel> identical
     иначе ERROR:<rel> hash mismatch; $failed++
   $failed > 0 -> STATUS:FAILED copied=<n> failed=<n> exit 3 (скопированное ОСТАЁТСЯ)
   Write-HashesFile -> EDITED:HASHES.txt lines=<n> | SAME:HASHES.txt; исключение -> ERROR:HASHES exit 3
   Если -Archive:
     $tmp = $pkg\deploy-package.7z.tmp7z
     Invoke-Native 7z @('a','-t7z','-mx=5',("-w" + $repoRoot), 'deploy-package\deploy-package.7z.tmp7z','deploy-package\*','-xr!*.tmp7z','-xr!deploy-package.7z')
     $LASTEXITCODE -ge 2 -> ERROR:ARCHIVE exit 3 (tmp остаётся)
     Move-Item -LiteralPath $tmp -Destination $pkg\deploy-package.7z -Force
     ARCHIVED:deploy-package.7z sha=<8> bytes=<n>
   WARN:MANUAL git-commit via git-commit agent; new opencode session; install via scripts\install.ps1; post-check integrity-check + verify.ps1
   SUMMARY:mode=apply scanned=<n> same=<n> changed=<n> new=<n> copied=<n> stale=<n> bytes=<n>
   STATUS:SUCCESS exit 0
9. -Json: вместо токенов — единственный JSON {mode,gates:[{id,status,detail}],files:[{rel,status,live_sha8,deploy_sha8}],stale:[],hashes:{lines,changed},archive:{...}|null,summary:{...}} (exit code тот же)
```

## 3.3 Логика Python-скрипта (`build.py`, ~500 строк)

- argparse: `--plan`, `--apply`, `--archive`, `--strict`, `--expected-agents 37`, `--expected-models 10`, `--expected-orch 25`, `--expected-plan 10`, `--json`.
- Зеркала: `read_raw`, `write_raw`, `sha256_file`, `get_fm_model`, `repo_root` + `count_task_allow` (обход dict), `count_routing_plugin`, `get_whitelist_count` (regex-копии check.py) + `build_file_map`, `test_secrets`, `write_hashes_file` (`os.linesep` НЕ используется — join по `'\n'`, `Path.write_bytes`), `find_seven_zip` (`shutil.which('7z') or shutil.which('7za') or Path('/usr/bin/7z')`), `get_stale_files`.
- Копирование: `shutil.copyfile(src, dst)` (байтовое) + `os.makedirs(dst.parent, exist_ok=True)`; верификация `sha256_file(src) == sha256_file(dst)`.
- 7z: `subprocess.run([...], cwd=repo_root, capture_output=True)`; returncode >= 2 → ERROR:ARCHIVE; замена архива: `os.replace(tmp, final)`.
- Сравнение строк байтовое: `==` в Python для str — по code points, для FRONTMATTER-моделей дополнительно НЕ lower-ить (token-exact).
- Токены, порядок, SUMMARY — идентичны PS (output parity).

## 3.4 Gates и exit codes

| # | Проверка | Режим | Exit |
|---|---|---|---|
| 1 | `-Plan -Apply` вместе / `-Archive` без `-Apply` | оба | 2 |
| 2 | live dir / agents dir (пуст) / opencode.json / plugin ts / repo root / deploy-package / project-files / root-доки — что-то отсутствует | оба | 2 (zero copies) |
| 3 | 7-Zip не найден при `-Archive` | оба | 2 |
| 4 | `GATE:JSON` — opencode.json не парсится | оба | 3 (zero copies) |
| 5 | `GATE:SECRETS` — литеральные секреты (hits > 0) | оба | 3 (zero copies) |
| 6 | `COUNT:agents_live` ≠ Expected | оба | 3 (zero copies) |
| 7 | `COUNT:models_used` ≠ Expected | оба | 3 (zero copies) |
| 8 | `COUNT:routing_orchestrator/plankestrator` — любое расхождение 3 источников с Expected | оба | 3 (zero copies) |
| 9 | `-Strict` + STALE > 0 | оба | 3 (до записи) |
| 10 | Copy error / SHA mismatch / HASHES write failure / 7z exit ≥ 2 | apply | 3 (частичные копии/tmp ОСТАЮТСЯ) |
| 11 | WARN: plugin-якорь не распарсен, MANUAL follow-ups, STALE без -Strict | оба | не влияет |
| 12 | Успех | plan → `STATUS:PLAN_OK`; apply → `STATUS:SUCCESS` | 0 |

## 3.5 Тестовые сценарии (deploy-package-build)

⚠️ Перед тестами: `backup-snapshot -Full` (live-файлы тесты НЕ модифицируют, но дрейф注入руется в deploy-копии — бэкап деплоя не требуется, т.к. deploy восстанавливается из live повторным -Apply; git restore как fallback).

1. **Plan на синхронном дереве:** `& ".opencode\skills\deploy-package-build\scripts\build.ps1" -Plan` → все gates PASS; `SAME:` для всех ~42 пар; `PLAN:HASHES.txt files=<n>`; `STATUS:PLAN_OK`; exit 0; НИ один файл не изменён (проверить отсутствие HASHES.txt, если его не было, и mtime деплой-файлов).
2. **Drift-обнаружение:** внести 1 байт в `deploy-package\agents\worker.md` (например `Add-Content` пробел) → `-Plan` показывает `CHANGED:agents/worker.md live=<sha8> deploy=<sha8>`; exit 0.
3. **Apply восстанавливает:** `-Apply` → `COPIED:agents/worker.md` + `VERIFY:agents/worker.md identical`; `EDITED:HASHES.txt lines=<n>`; exit 0; `fc /b` live vs deploy → no differences.
4. **HASHES.txt формат:** первая строка матчит `^[0-9A-F]{64}  [a-z]`; сортировка (rel-пути возрастают); LF-only (`Format-Hex` — нет `0D`); node_modules/7z/HASHES.txt исключены; повторный `-Apply` → `SAME:HASHES.txt` (нет churn).
5. **Counter gate:** `-Plan -ExpectedAgents 38` → `COUNT:agents_live=37 expected=38 -> BLOCK`, `STATUS:BLOCKED gates=1`, exit 3, zero copies. Аналогично `-ExpectedOrch 24`, `-ExpectedModels 9`.
6. **Flag gates:** `-Plan -Apply` → exit 2; `-Archive` (без -Apply) → exit 2.
7. **Strict + STALE:** создать `deploy-package\agents\zz-ghost.md` (копия любого) → `-Plan` → `WARN:STALE:agents/zz-ghost.md`, exit 0; `-Plan -Strict` → exit 3; `-Apply` → файл скопирован НЕ будучи удалён (STALE остаётся, WARN), exit 0. Удалить ghost вручную после теста.
8. **Archive:** `-Apply -Archive` (7-Zip установлен) → `ARCHIVED:deploy-package.7z sha=<8> bytes=<n>`; архив открывается (`7z l`), содержит `deploy-package/agents/...` и node_modules, НЕ содержит старый .7z; повторный запуск — архив пересобран (не дополнен).
9. **Verify-совместимость:** после `-Apply` → `powershell deploy-package\scripts\verify.ps1` проходит (если live-окружение валидно); `integrity-check` → PAIR:* все OK, exit 0.
10. **PS/PY parity:** `python .opencode/skills/deploy-package-build/scripts/build.py --plan` → тот же token-поток (SAME/CHANGED наборы, gates, SUMMARY), exit code совпадает.

---

## Edge Cases (сквозные)

- **Консоль cp866/cp1251:** весь вывод — ASCII; юникодные стрелки/параллели — только входной синтаксис (в .ps1/.py — `\u2192`/`\u2225` escapes и `[char]0x2192`, никаких литералов — PS 5.1 читает .ps1 без BOM как ANSI).
- **Имена моделей с пробелами/скобками** (`GLM-5.3 (res)`, `Kimi K3`, `stepfun/step-5-preview`): сравнение байт-в-байт (`-ceq` / `==`); в regex — только `[regex]::Escape()` / `re.escape()`; split model key — по ПЕРВОМУ `/` (key может содержать `/`).
- **YAML silent-drop:** description всех трёх SKILL.md — в одинарных кавычках, без `": "` вне кавычек и без апострофов внутри.
- **Frontmatter без `model:`** — не краш: report → `model=<missing>` + WARN:FM_NO_MODEL; visualize → WARN:STEP_NO_MODEL; build → distinct-счётчик просто не включает пустое значение (но COUNT:models_used тогда, вероятно, заблокирует — это корректное поведение gate).
- **Агент вне Model Roles** (будущее добавление до обновления таблицы): report → `WARN:ROLE_UNMAPPED` role=`<unmapped>` tier=`?`; visualize → узел без tier, prewalk-анализ пропускает; build → не влияет (счётчики roles не гейтят).
- **scout** — вне обоих whitelist'ов → routing `-`; в пайплайнах §2 не встречается (только во внутреннем fan-out RESEARCH — agent-resolved, модель mimo-v2.5).
- **Wildcard-шаги** (`plan-writer-*`, `plan-reviewer-*`, `research-writer-*`): prefix-resolve; при matches ≥ 2 — без tier/prewalk; WARN:STEP_UNRESOLVED kind=wildcard.
- **Известный дрейф Model Roles (root vs live ARCHITECTURE.md):** все три скилла читают ТОЛЬКО корневой ARCHITECTURE.md; WARN:ROLE_MODEL_DRIFT в agent-report легитимно сработает, если root-таблица разошлась с frontmatter — это фича (сигнал для agent-model-migrate), не баг.
- **Multi-line fence DOCS DEEP:** строки, начинающиеся с `→`, — продолжение буфера (учтено в сканере); пустые строки внутри fence буфер НЕ сбрасывают.
- **Одинаковые цепочки в разных секциях** (fan-out RESEARCH дублируется в `Wave → Barrier → Synthesis Pattern`): дедуп по последовательности токенов — первая побеждает.
- **deploy-package-build zero-copy guarantee:** gates + strict-блок выполняются ДО первой записи; частичный сбой копирования оставляет скопированное (never delete) — повторный запуск идемпотентен (SAME пропускаются).
- **HASHES.txt в git:** файл НОВЫЙ для deploy-package — после первого `-Apply` потребуется коммит через `git-commit` агента (WARN:MANUAL). Формат совместим с backup-snapshot для диффинга.
- **7z exit code 1 = warning** (не ошибка) — фейл только при ≥ 2; tmp-архив при фейле остаётся (never delete), следующий запуск перезапишет.
- **`-Json` режимы:** JSON — ЕДИНСТВЕННЫЙ stdout (никаких токенов), как в integrity-check; exit codes не меняются.
- **Счётчики не захардкожены в report/visualize** (mid-migration 37/38 устойчивы); в build — параметры с дефолтами 37/10/25/10 (при легитимном изменении архитектуры обновляются в ОБОИХ скриптах + SKILL.md одновременно).
- **Конфиг читается на старте сессии:** регистрация новых скиллов и любые live-изменения — только в НОВОЙ сессии opencode (WARN:MANUAL в build).
- **`__pycache__/`** появляется рядом с .py — безвредно; в git не коммитить (можно добавить в `.opencode/.gitignore` отдельным тикетом, вне scope).

## Dependencies (что проверить до реализации)

1. **Уникальность якорей** (каждый `rg -c` == 1 в корневом ARCHITECTURE.md): `^## Model Roles`, `^## 2\. Pipelines`, `^### Pipeline Notation`, `^### DEV Complexity Classification`, `^### Auto-DOCS Hook`, `^### orchestrator Whitelist \(\d+ agents\)`, `^### plankestrator Whitelist \(\d+ agents\)`.
2. **Базовое здоровье:** `integrity-check` → `STATUS:ALL_PASS` (иначе — зафиксировать пре-существующие FAIL как baseline и НЕ чинить в рамках этой задачи; gates build воспроизведут те же находки).
3. **Структура Model Roles таблицы:** строки вида `| role | model | tier | agents |`, tier ∈ {top,mid,low}; контрольная сумма `2 primary + 35 subagents = 37` (L133) не парсится скиллами — только строки таблицы.
4. **deploy-package layout:** `agents/`, `project-files/` (4 дока), `plugins/workflow-enforcement.ts`, `opencode.json`, `scripts/`, `README.md`, `DEPLOYMENT_GUIDE.md` — на месте; `deploy-package/HASHES.txt` отсутствует (будет создан).
5. **Live layout:** `~/.config/opencode/{agents/*.md, opencode.json, plugins/workflow-enforcement.ts}`; `agent.orchestrator.permission.task` / `agent.plankestrator.permission.task` присутствуют в live opencode.json.
6. **7-Zip** доступен (`7z` в PATH или `%ProgramFiles%\7-Zip\7z.exe`) — для теста `-Archive`; при отсутствии — тест 8 пропускается (gate exit 2 проверить отдельно).
7. **Python 3.8+** доступен для прогона PY-зеркал.
8. **Порядок реализации:** agent-report → pipeline-visualize (переиспользует Get-SectionText/Get-ModelRoleMap из report — копирование) → deploy-package-build (независим). После каждого скилла — его тестовые сценарии + синтаксическая проверка (utility).
9. **После реализации:** прогон `integrity-check` (не должен сломаться), коммит 9 новых файлов через `git-commit` агента; CHANGELOG-запись НЕ нужна (конвенция проектных скиллов); проверка регистрации скиллов — в НОВОЙ сессии.

## Files to Create

```
.opencode/skills/agent-report/SKILL.md
.opencode/skills/agent-report/scripts/report.ps1
.opencode/skills/agent-report/scripts/report.py
.opencode/skills/pipeline-visualize/SKILL.md
.opencode/skills/pipeline-visualize/scripts/visualize.ps1
.opencode/skills/pipeline-visualize/scripts/visualize.py
.opencode/skills/deploy-package-build/SKILL.md
.opencode/skills/deploy-package-build/scripts/build.ps1
.opencode/skills/deploy-package-build/scripts/build.py
```

Модификации существующих файлов: НЕ ТРЕБУЮТСЯ (deploy-package/HASHES.txt и deploy-package.7z создаются/пересобираются только при ПРОГОНЕ build -Apply, не при реализации скиллов).
