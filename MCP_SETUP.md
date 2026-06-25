# MCP Setup Guide — OpenCode Agent Orchestration System

Полное и исчерпывающее руководство по развертыванию системы оркестрации агентов OpenCode на машинах коллег.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Installation Steps](#3-installation-steps)
4. [opencode.json — Full Configuration](#4-opencodejson--full-configuration)
5. [Agent Definitions — All 32 Agents](#5-agent-definitions--all-32-agents)
6. [Routing Tables](#6-routing-tables)
7. [Pipelines](#7-pipelines)
8. [ARCHITECTURE.md Integration](#8-architecturemd-integration)
9. [AGENTS.md — Project Rules](#9-agentsmd--project-rules)
10. [Plugin — workflow-enforcement.ts](#10-plugin--workflow-enforcementts)
11. [MCP Servers](#11-mcp-servers)
12. [Commands](#12-commands)
13. [File Locations](#13-file-locations)
14. [Troubleshooting](#14-troubleshooting)
15. [Verification Checklist](#15-verification-checklist)

---

## 1. Overview

### System Architecture

OpenCode использует архитектуру с двумя primary-агентами:

| Primary Agent | Role | Workflows |
|---------------|------|-----------|
| **orchestrator** | Operational tasks | BUGFIX, DEVOPS, DEV, DOCS |
| **plankestrator** | Planning & research | PLAN, RESEARCH, RESEARCH+PLAN |

### Agent Count

| Category | Count |
|----------|-------|
| Primary agents | 2 |
| Subagents | 30 |
| **Total unique agents** | **32** |

### Models Distribution

| Model | Provider | Agents Count | Agents |
|-------|----------|--------------|--------|
| `glm-5` | alibaba-coding-plan | 7 | orchestrator, plankestrator, orchestrator-identity-probe, plankestrator-identity-probe, docs-writer, research-writer-simple, plan-reviewer-simple |
| `qwen3.7-plus` | alibaba-coding-plan | 9 | worker, bugfix, bugfix-triage, plan-bug, dev-planner, devops-reviewer, plan-writer-simple, consistency-checker, utility |
| `glm-5.2` | zai-coding-plan | 5 | dev-professor, plan-writer-complex, research-writer-complex, execute-bug, rework |
| `k2p7` | kimi-for-coding | 3 | dev-reviewer, plan-reviewer-complex, research-reviewer |
| `MiniMax-M2.7` | minimax-coding-plan | 7 | mcp-github, mcp-read, mcp-search, summarizer, devops, devops-agent, devops-readonly |

### MCP Servers

| Server | Type | Purpose |
|--------|------|---------|
| zread | Remote | GitHub repository operations |
| webSearchPrime | Remote | Web search |
| webReader | Remote | URL content reading |
| serena | Local | Code symbol operations |
| unity-mcp | Remote | Unity Editor operations |
| zai-mcp-server | Local | Image analysis (fallback) |

---

## 2. Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18+ | Plugin runtime, npx |
| OpenCode CLI | Latest | Agent orchestration |
| Git | 2.x | Repository operations |
| Python | 3.10+ | Serena MCP server |
| uv | Latest | Python package manager (for Serena) |

### For Unity Projects (Optional)

| Software | Version | Purpose |
|----------|---------|---------|
| Unity Editor | 2021.3 LTS+ | Unity MCP server host |
| unity-mcp package | Latest | Unity MCP integration via git URL |

### Required API Keys

| Provider | Key | Purpose |
|----------|-----|---------|
| Alibaba (bailian-token-plan) | `sk-sp-*` | Qwen, GLM models (glm-5, qwen3.7-plus) |
| Z.AI (zai-coding-plan) | через API | GLM-5.2 модели |
| Z.AI | `a8d38aaca0e04f678f11c7f8bd135a12.*` | zread, webSearchPrime, webReader, zai-mcp-server |

---

## 3. Installation Steps

### Step 0: Clone Repository

```powershell
# Клонировать репозиторий с конфигурацией
git clone https://github.com/pavelherocraft/opencode-config.git
cd opencode-config
```

### Step 1: Install OpenCode CLI

```bash
npm install -g opencode
```

### Step 2: Install Serena

Serena — MCP сервер для операций с кодовыми символами (поиск классов, функций, рефакторинг).

```powershell
# Скачать Serena с https://github.com/mrworkwhile/serena/releases
# Установить serena.exe в:
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin"
Move-Item serena.exe "$env:USERPROFILE\.local\bin\serena.exe"

# Добавить в PATH (опционально)
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:USERPROFILE\.local\bin", "User")
```

Проверка установки:
```powershell
serena --version
```

### Step 3: Install zai-mcp-server

```powershell
# Устанавливается автоматически через npx при первом запуске
npx -y @z_ai/mcp-server
```

### Step 4: Configure Unity MCP (Optional — только для Unity проектов)

1. Установить Unity 2021.3 LTS или новее
2. Установить unity-mcp package через Unity Package Manager:
   - Открыть Package Manager
   - Добавить package из git URL: `https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main`
3. Запустить Unity Editor
4. Запустить MCP сервер: `Window > MCP for Unity > Start Server`
5. Сервер работает на `http://localhost:8080/mcp`

### Step 5: Create Directory Structure

```powershell
# Windows (PowerShell)
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\plugins"
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.config\opencode\agents"
```

### Step 6: Copy Configuration Files

```powershell
# Скопировать opencode.json
Copy-Item "opencode-config\opencode.json" "$env:USERPROFILE\.config\opencode\opencode.json" -Force

# Скопировать plugin
Copy-Item "plugins\workflow-enforcement.ts" "$env:USERPROFILE\.config\opencode\plugins\workflow-enforcement.ts" -Force

# Скопировать все agent файлы
Copy-Item "agents\*.md" "$env:USERPROFILE\.config\opencode\agents\" -Force
```

### Step 7: Configure API Keys

Откройте `$env:USERPROFILE\.config\opencode\opencode.json` и замените:
- `sk-sp-YOUR_API_KEY` → ваш Alibaba Token Plan API key
- `YOUR_Z_AI_KEY` → ваш Z.AI API key (для zread, webSearchPrime, webReader, zai-mcp-server)

### Step 8: Copy Project Files

Скопировать в корень проекта:
- `AGENTS.md` — Правила проекта и разрешения агентов
- `ARCHITECTURE.md` — Требования к архитектуре
- `PLUGIN.md` — Документация плагина
- `MCP_SETUP.md` — Это руководство

---

## 4. opencode.json — Full Configuration

### Provider Configuration

```json
"provider": {
  "bailian-token-plan": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Alibaba Token Plan",
    "options": {
      "baseURL": "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
      "apiKey": "sk-sp-YOUR_API_KEY"
    },
    "models": {
      "qwen3.7-max": { "name": "Qwen3.7 Max", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "qwen3.7-plus": { "name": "Qwen3.7 Plus", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "qwen3.6-flash": { "name": "Qwen3.6 Flash", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "deepseek-v4-pro": { "name": "DeepSeek V4 Pro" },
      "deepseek-v4-flash": { "name": "DeepSeek V4 Flash" },
      "deepseek-v3.2": { "name": "DeepSeek V3.2" },
      "kimi-k2.6": { "name": "Kimi K2.6", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "kimi-k2.5": { "name": "Kimi K2.5", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "glm-5": { "name": "GLM-5", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } },
      "MiniMax-M2.5": { "name": "MiniMax M2.5" }
    }
  },
  "zai-coding-plan": {
    "npm": "@ai-sdk/openai-compatible",
    "name": "Z.AI Coding Plan",
    "options": {
      "baseURL": "https://api.z.ai/anthropic/v1",
      "apiKey": "YOUR_Z_AI_KEY"
    },
    "models": {
      "glm-5.2": { "name": "GLM-5.2", "options": { "thinking": { "type": "enabled", "budgetTokens": 8192 } } }
    }
  }
}
```

### MCP Servers Configuration

```json
"mcp": {
  "zread": {
    "url": "https://api.z.ai/api/mcp/zread/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "webSearchPrime": {
    "url": "https://api.z.ai/api/mcp/web_search_prime/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "webReader": {
    "url": "https://api.z.ai/api/mcp/web_reader/mcp",
    "headers": { "Authorization": "Bearer YOUR_Z_AI_KEY" },
    "type": "remote"
  },
  "serena": {
    "type": "local",
    "command": ["%USERPROFILE%\\.local\\bin\\serena.exe", "start-mcp-server", "--transport", "stdio", "--context=ide", "--project-from-cwd"],
    "enabled": true
  },
  "unity-mcp": {
    "type": "remote",
    "url": "http://localhost:8080/mcp",
    "enabled": true
  },
  "zai-mcp-server": {
    "type": "local",
    "command": ["npx", "-y", "@z_ai/mcp-server"],
    "environment": {
      "Z_AI_API_KEY": "YOUR_Z_AI_KEY",
      "Z_AI_MODE": "ZAI"
    },
    "enabled": true
  }
}
```

### Plugin Configuration

```json
"plugin": ["./plugins/workflow-enforcement.ts"]
```

### Shell Configuration

```json
"shell": "powershell"
```

---

## 5. Agent Definitions — All 32 Agents

### Primary Agents

#### orchestrator

| Field | Value |
|-------|-------|
| Mode | primary |
| Model | alibaba-coding-plan/glm-5 |
| Temperature | 0.1 |
| Role | Task classifier and delegator (BUGFIX/DEVOPS/DEV/DOCS) |

**Prompt:**
```
You MUST output JSON in EVERY response. First line: 'IDENTITY VERIFIED: I am orchestrator...'. Second: JSON code block with fields: agent, type, complexity, plan_exists, plan_source, goal, next_agent, pipeline. Third: Call Task tool if next_agent is not null. This is MANDATORY. NO EXCEPTIONS.

## Tool Priority
For code operations, ALWAYS try Serena MCP tools FIRST:
- serena_find_symbol (not grep)
- serena_find_referencing_symbols (not grep)
- serena_get_symbols_overview (not grep)
- serena_rename_symbol (not edit with regex)
- serena_replace_symbol_body (not edit)

Use built-in tools (grep, read, edit) as FALLBACK when Serena fails or for non-symbol tasks.

## Image Analysis Priority
For image analysis tasks, ALWAYS use view-image agent FIRST (NOT zai-mcp-server):
- Call Task tool with view-image subagent
- view-image has direct vision capabilities via kimi-for-coding/k2p6
- Use zai-mcp-server only as FALLBACK when view-image is unavailable

## Pipeline Logic
| Task Type | plan_exists | Pipeline |
|-----------|-------------|----------|
| DEV SIMPLE | false | worker → utility |
| DEV SIMPLE | true | worker → consistency-checker → utility |
| DEV COMPLEX | any | dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → rework → consistency-checker → utility |
| DEV SUPERCOMPLEX | large plan (>3 steps) | PER STEP: dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → consistency-checker → [rework loop] → utility |

**Decision rules:**
- When `plan_exists=true` for DEV SIMPLE, add consistency-checker before utility. When `plan_exists=false`, skip consistency-checker.
- When plan has >3 steps AND huge volume, use DEV SUPERCOMPLEX (complexity: SUPERCOMPLEX).

### ⚠️ MANDATORY Prompt Requirements — FAILURE TO COMPLY BREAKS THE PIPELINE ⚠️

When the orchestrator calls agents in DEV pipelines, it MUST include these instructions in the prompt. This is NOT optional. The pipeline WILL FAIL if dev-planner does not write to dev_plan.md and dev-professor does not read from it.

**dev-planner**: ALWAYS include "Write the plan to dev_plan.md." in the prompt. The prompt template is:
```
Plan implementation for: [task description]. Write the plan to dev_plan.md.
```
DO NOT call dev-planner without this suffix. DO NOT let dev-planner return plan as plain text — it MUST go to dev_plan.md file.

**dev-professor**: ALWAYS include "Review dev_plan.md" in the prompt. The prompt template is:
```
Review dev_plan.md and implement step by step.
```
DO NOT call dev-professor without this prefix. dev-professor MUST read dev_plan.md before implementing.

**DEV COMPLEX / DEV SUPERCOMPLEX pipelines MUST follow these prompt requirements.** For each step in SUPERCOMPLEX, apply these requirements per step.
```

### BUGFIX DEEP — Mandatory Prompt Requirements

When the orchestrator calls agents in BUGFIX DEEP pipeline, it MUST include these instructions in the prompt. This is NOT optional. The pipeline WILL FAIL if plan-bug does not write to bug_plan.md and execute-bug does not read from it.

**plan-bug**: ALWAYS include "Write the plan to bug_plan.md." in the prompt:
```
Investigate and plan fix for: [bug description]. Write the plan to bug_plan.md.
```
DO NOT call plan-bug without this suffix. DO NOT let plan-bug return plan as plain text — it MUST go to bug_plan.md file.

**execute-bug**: ALWAYS include "Read bug_plan.md" in the prompt:
```
Read bug_plan.md and implement the bug fix.
```
DO NOT call execute-bug without this prefix. execute-bug MUST read bug_plan.md before implementing.

**BUGFIX DEEP pipeline MUST follow these prompt requirements.**

**Permissions:**
| Tool | Permission | Notes |
|------|------------|-------|
| edit | ask | |
| write | deny | |
| read | { "*.py": "ask", "*.ts": "ask", "*.js": "ask", "*": "allow" } | |
| grep | ask | |
| glob | allow | |
| question | allow | |
| bash | deny | |
| todowrite | allow | |
| unity-mcp.* | allow | |
| serena_* | allow | Все Serena инструменты |
| task | { "*": "deny", ... } | Whitelist ниже |

**Task Whitelist (21 agents):**
orchestrator-identity-probe, dev-reviewer, dev-professor, mcp-github, worker, bugfix, rework, mcp-read, utility, devops, bugfix-triage, plan-bug, devops-agent, devops-reviewer, dev-planner, mcp-search, docs-writer, summarizer, execute-bug, consistency-checker, view-image

#### plankestrator

| Field | Value |
|-------|-------|
| Mode | primary |
| Model | alibaba-coding-plan/glm-5 |
| Temperature | 0.1 |
| Role | Planning and research state machine |

**Permissions:**
| Tool | Permission |
|------|------------|
| edit | deny |
| write | deny |
| bash | deny |
| read | allow |
| question | allow |
| todowrite | allow |
| unity-mcp.* | allow |
| serena_* | allow | Все Serena инструменты |

**Task Whitelist (9 agents):**
plankestrator-identity-probe, plan-writer-simple, plan-writer-complex, plan-reviewer-simple, plan-reviewer-complex, research-writer-simple, research-writer-complex, research-reviewer, devops-readonly

### Subagents — Full Table

| Agent | Mode | Model | Temperature | edit | write | read | bash | task whitelist extras |
|-------|------|-------|-------------|------|-------|------|------|----------------------|
| **mcp-github** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | allow | deny | view-image |
| **dev-planner** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | deny | *.md | - | deny | view-image |
| **bugfix** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.2 | allow | - | - | deny | view-image |
| **mcp-read** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | allow | deny | view-image |
| **plan-writer-complex** | subagent | zai-coding-plan/glm-5.2 | 0.1 | allow | - | allow | deny | devops-readonly, view-image |
| **worker** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.2 | allow | - | - | **allow** | view-image |
| **utility** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | deny | deny | - | **allow** | view-image |
| **rework** | subagent | zai-coding-plan/glm-5.2 | 0.2 | allow | - | - | deny | view-image |
| **research-writer-simple** | subagent | alibaba-coding-plan/glm-5 | 0.1 | allow | - | allow | deny | mcp-search, mcp-read, mcp-github, devops-readonly, view-image |
| **plan-reviewer-simple** | subagent | alibaba-coding-plan/glm-5 | 0.1 | allow | - | allow | deny | devops-readonly, view-image |
| **plan-bug** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | *.md | - | - | deny | view-image | Writes bug plan to bug_plan.md |
| **devops** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | allow | **allow** | view-image |
| **docs-writer** | subagent | alibaba-coding-plan/glm-5 | 0.3 | allow | - | - | deny | view-image |
| **dev-professor** | subagent | zai-coding-plan/glm-5.2 | 0.2 | allow | - | - | deny | view-image | Reviews plan from dev_plan.md before implementing |
| **devops-readonly** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | allow | - | allow | deny | view-image |
| **devops-agent** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | - | **allow** | view-image |
| **devops-reviewer** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | deny | deny | allow | deny | view-image |
| **orchestrator-identity-probe** | subagent | alibaba-coding-plan/glm-5 | 0.1 | deny | deny | - | deny | view-image |
| **plankestrator-identity-probe** | subagent | alibaba-coding-plan/glm-5 | 0.1 | deny | deny | - | deny | view-image |
| **mcp-search** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | allow | deny | view-image |
| **summarizer** | subagent | minimax-coding-plan/MiniMax-M2.7 | 0.1 | deny | deny | allow | deny | view-image |
| **bugfix-triage** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | deny | deny | - | deny | view-image |
| **research-reviewer** | subagent | kimi-for-coding/k2p7 | 0.1 | allow | - | allow | deny | view-image |
| **dev-reviewer** | subagent | kimi-for-coding/k2p7 | 0.1 | allow | - | - | deny | view-image |
| **research-writer-complex** | subagent | zai-coding-plan/glm-5.2 | 0.1 | allow | - | allow | deny | mcp-search, mcp-read, mcp-github, devops-readonly, view-image |
| **plan-writer-simple** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | allow | - | allow | deny | devops-readonly, view-image |
| **execute-bug** | subagent | zai-coding-plan/glm-5.2 | 0.2 | allow | - | - | **allow** | view-image | Reads plan from bug_plan.md before implementing |
| **plan-reviewer-complex** | subagent | kimi-for-coding/k2p7 | 0.1 | allow | - | allow | deny | devops-readonly, view-image |
| **consistency-checker** | subagent | alibaba-coding-plan/qwen3.7-plus | 0.1 | allow | - | allow | deny | dev-reviewer, utility, view-image |
| **view-image** | subagent | kimi-for-coding/k2p6 | 0.1 | deny | deny | allow | deny | **NO MCP servers** |

### ⚠️ Manual opencode.json Update Required for plan-bug

`opencode.json` is the **authoritative source** for agent permissions — frontmatter in `.md` files is documentation only (see ARCHITECTURE.md → Permission Authority). The repository does **NOT** ship `opencode.json` — it lives at `~/.config/opencode/opencode.json` (user-managed).

**Required change for `plan-bug`** (to enable `bug_plan.md` writing in BUGFIX DEEP):

```json
// BEFORE (legacy — plan-bug could not write):
"plan-bug": {
  "permission": {
    "edit": "deny"
  }
}

// AFTER (allow .md writing for bug_plan.md):
"plan-bug": {
  "permission": {
    "edit": {
      "*.md": "allow",
      "*": "deny"
    }
  }
}
```

**Why this matters:** Without this change, the BUGFIX DEEP pipeline will fail because `plan-bug` cannot write `bug_plan.md`, so `execute-bug` has nothing to read.

**Steps:**
1. Open `~/.config/opencode/opencode.json`
2. Locate the `plan-bug` agent entry under `agents`
3. Update `permission.edit` to `{ "*.md": "allow", "*": "deny" }`
4. Save and restart opencode (or reload the session)

This mirrors the existing `dev-planner` permission, which already uses `edit: { "*.md": "allow", "*": "deny" }` to write `dev_plan.md`.

### ⚠️ Manual opencode.json Update Required for execute-bug

**Required change for `execute-bug`** (to enable bash access for running tests and commands):

```json
// BEFORE:
"execute-bug": {
  "permission": {
    "bash": "deny"
  }
}

// AFTER:
"execute-bug": {
  "permission": {
    "bash": "allow"
  }
}
```

**Why this matters:** execute-bug is the bug fix implementation agent in the BUGFIX DEEP pipeline. It needs `bash: allow` to run tests, execute commands, and verify fixes. ARCHITECTURE.md specifies `bash: allow` for execute-bug.

**Steps:**
1. Open `~/.config/opencode/opencode.json`
2. Locate the `execute-bug` agent entry under `agents`
3. Update `permission.bash` from `"deny"` to `"allow"`
4. Save and restart opencode (or reload the session)

### view-image — Special Configuration

**Prompt:**
```
You are an image analysis agent. Analyze images and describe what you see. You have direct vision capabilities. Analyze images directly through your model — do NOT use MCP servers for image analysis. You CAN use read, glob, and grep tools to access files when needed.
```

**Permissions:**
| Tool | Permission |
|------|------------|
| edit | deny |
| write | deny |
| bash | deny |
| read | allow |
| glob | allow |
| grep | allow |
| zread.* | **deny** |
| webSearchPrime.* | **deny** |
| webReader.* | **deny** |
| serena.* | **deny** |
| unity-mcp.* | **deny** |
| zai-mcp-server.* | **deny** |

view-image анализирует изображения **напрямую через модель** (kimi-for-coding/k2p6 с vision capabilities). Все MCP серверы запрещены.

### Serena Permissions — All Agents (кроме view-image)

Все агенты (кроме view-image) имеют доступ ко всем Serena инструментам:

| Serena Tool | Permission |
|-------------|------------|
| serena_find_symbol | allow |
| serena_find_referencing_symbols | allow |
| serena_get_symbols_overview | allow |
| serena_rename_symbol | allow |
| serena_safe_delete_symbol | allow |
| serena_replace_symbol_body | allow |
| serena_insert_after_symbol | allow |

### unity-mcp Permissions — All Agents

Все 32 агента имеют `"unity-mcp.*": "allow"` — полный доступ ко всем инструментам Unity MCP.

### Key Agent Permissions Details

#### worker — bash: allow (CRITICAL)

Worker — единственный агент с `bash: allow` для выполнения команд:
- npm operations: `npm install`, `npm run build`, `npm run test`
- git operations: `git status`, `git add`, `git commit`, `git push`
- file operations: `mkdir`, `touch`, `rm`, `cp`
- linting tools: `eslint`, `prettier`, `tsc --noEmit`
- test runners: `jest`, `vitest`, `pytest`, `cargo test`

**Без `bash: allow` worker не может выполнять задачи — это критическая настройка.**

#### utility — bash: allow

Utility имеет `bash: allow` для запуска линтеров, форматтеров, компиляторов при валидации кода.

#### devops / devops-agent — bash: allow

DevOps агенты имеют `bash: allow` для выполнения команд деплоя, сборки, управления инфраструктурой.

### Permission Model: edit vs write — CRITICAL

**⚠️ COMMON MISTAKE: Using `write` as a permission key**

#### The Problem

Many users mistakenly configure permissions like this:

```json
{
  "edit": "deny",
  "write": "*.md"  // ❌ WRONG — this is a DEAD KEY
}
```

This configuration **DOES NOT WORK** because:

1. **`write` is a TOOL NAME, not a permission key**
   - The permission system uses `edit` as the key
   - `write`, `patch`, `multiedit` are all controlled by the `edit` permission

2. **`write: "*.md"` creates a DEAD KEY**
   - OpenCode does not recognize `write` as a valid permission key
   - The configuration is silently ignored
   - Agent cannot write files despite the apparent permission

#### The Solution

To restrict file writing to specific file types, use `edit` with a glob pattern:

```json
{
  "edit": { "*.md": "allow", "*": "deny" }  // ✅ CORRECT
}
```

This configuration:
- Allows editing/writing `.md` files
- Denies editing/writing all other files
- Controls `edit`, `write`, `patch`, and `multiedit` tools

#### Permission Key vs Tool Name

| Permission Key | Controls These Tools |
|----------------|----------------------|
| `edit` | `edit`, `write`, `patch`, `multiedit` |
| `read` | `read` |
| `bash` | `bash` |
| `glob` | `glob` |
| `grep` | `grep` |

**Rule:** Always use the permission KEY, not the tool NAME.

#### Case Study: dev-planner Permission Fix

**Original (broken) configuration:**
```json
{
  "edit": "deny",
  "write": "*.md"  // DEAD KEY — dev-planner couldn't write files
}
```

**Symptoms:**
- dev-planner could not write `dev_plan.md`
- Pipeline failed at DEV COMPLEX step
- Error: "Permission denied for write tool"

**Fixed configuration:**
```json
{
  "edit": { "*.md": "allow", "*": "deny" }  // Now works correctly
}
```

**Result:**
- dev-planner can write `.md` files (including `dev_plan.md`)
- dev-planner cannot edit other file types
- DEV COMPLEX pipeline works correctly

#### Valid Permission Patterns

| Pattern | Meaning | Example Use Case |
|---------|---------|------------------|
| `"allow"` | Allow all operations | Full access agent |
| `"deny"` | Deny all operations | Read-only agent |
| `"ask"` | Ask user for permission | Interactive agent |
| `{ "*.md": "allow", "*": "deny" }` | Allow specific file types | dev-planner (writes plans) |
| `{ "*.py": "ask", "*.ts": "ask", "*": "allow" }` | Ask for code files, allow others | orchestrator (reads code, asks before editing) |
| `{ "src/**": "allow", "*": "deny" }` | Allow specific directory | Agent restricted to src/ |

#### Quick Reference

| Mistake | Correction |
|---------|------------|
| `"write": "*.md"` | `"edit": { "*.md": "allow" }` |
| `"patch": "allow"` | `"edit": "allow"` |
| `"multiedit": "deny"` | `"edit": "deny"` |

**Remember:** `edit` is the permission key that controls all file modification tools.

---

## 6. Routing Tables

### orchestrator Whitelist (21 agents)

| Agent | Role |
|-------|------|
| orchestrator-identity-probe | Identity verification |
| dev-reviewer | Code review |
| dev-professor | Development guidance |
| mcp-github | GitHub operations |
| worker | Simple development tasks |
| bugfix | Bug fixing |
| rework | Rework on feedback |
| mcp-read | File reading |
| utility | Syntax checking, formatting |
| devops | DevOps tasks |
| bugfix-triage | Initial bug analysis |
| plan-bug | Bug fix planning |
| devops-agent | DevOps operations |
| devops-reviewer | DevOps review |
| dev-planner | Development planning |
| mcp-search | Web search |
| docs-writer | Documentation writing |
| summarizer | Content summarization |
| execute-bug | Bug fix implementation |
| consistency-checker | Architecture consistency validation |
| view-image | Image analysis |

### plankestrator Whitelist (9 agents)

plankestrator can only call these agents:

| Agent Name | Role |
|------------|------|
| plankestrator-identity-probe | Identity verification |
| plan-writer-simple | Simple planning |
| plan-writer-complex | Complex planning |
| plan-reviewer-simple | Simple plan review |
| plan-reviewer-complex | Complex plan review |
| research-writer-simple | Simple research |
| research-writer-complex | Complex research |
| research-reviewer | Research review |
| devops-readonly | DevOps read-only |

### Routing Enforcement

Плагин `workflow-enforcement.ts` обеспечивает:
1. **Routing table enforcement** — агенты могут вызывать только агентов из своего whitelist
2. **JSON validation** — primary агенты должны выводить JSON перед вызовом Task tool
3. **Identity drift detection** — обнаружение и логирование смены идентичности агента
4. **Agent detection** — автоматическое определение текущего агента из session data, JSON output, или IDENTITY VERIFIED текста

---

## 7. Pipelines

### BUGFIX Pipelines

| Pipeline | Flow |
|----------|------|
| **BUGFIX SIMPLE** | bugfix-triage → worker → utility |
| **BUGFIX DEEP** | bugfix-triage → plan-bug (writes bug_plan.md) → execute-bug (reads bug_plan.md) → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility |

### DEV Pipelines

| Pipeline | Flow | When to Use |
|----------|------|-------------|
| **DEV SIMPLE (без плана)** | worker → utility | Простые задачи без предварительного планирования |
| **DEV SIMPLE (с планом)** | worker → consistency-checker → utility | Задачи с существующим планом — валидация против плана |
| **DEV COMPLEX** | dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → rework → consistency-checker → utility | Сложные задачи с планированием — dev-planner пишет план в dev_plan.md, dev-professor читает и ревьюит план перед реализацией |
| **DEV SUPERCOMPLEX** | PER PLAN STEP: dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → consistency-checker → [rework loop, max 3] → utility | Очень большие планы (>3 шагов) или огромный объём работ — на каждом шаге dev-planner пишет план в dev_plan.md, dev-professor читает и ревьюит план перед реализацией |

**Decision rule:** Если `plan_exists=true` для DEV SIMPLE, добавить consistency-checker перед utility. Если `plan_exists=false`, пропустить consistency-checker.

### Other Pipelines

| Pipeline | Flow |
|----------|------|
| **DEVOPS** | devops-agent → devops-reviewer |
| **DOCS** | docs-writer → utility |
| **PLAN SIMPLE** | plan-writer-simple → plan-reviewer-simple |
| **PLAN COMPLEX** | plan-writer-complex → plan-reviewer-complex |
| **RESEARCH SIMPLE** | research-writer-simple → research-reviewer |
| **RESEARCH COMPLEX** | research-writer-complex → research-reviewer |
| **RESEARCH+PLAN SIMPLE** | research-writer-simple → research-reviewer → plan-writer-simple → plan-reviewer-simple |
| **RESEARCH+PLAN COMPLEX** | research-writer-complex → research-reviewer → plan-writer-complex → plan-reviewer-complex |

---

## 8. ARCHITECTURE.md Integration

### Purpose

`ARCHITECTURE.md` определяет все архитектурные требования проекта. consistency-checker agent читает этот файл для валидации всех конфигурационных файлов.

### What ARCHITECTURE.md Contains

- Routing tables (agent whitelists)
- Pipeline definitions
- JSON validation fields
- MCP server configurations
- Identity probe whitelists
- Outdated terms to check

### How consistency-checker Uses It

1. Читает `ARCHITECTURE.md` из корня проекта
2. Сравнивает текущие конфигурации с определёнными требованиями
3. Валидирует:
   - Соответствие routing tables
   - Корректность pipeline definitions
   - JSON validation rules
   - MCP server configurations
   - Identity probe configurations
4. Возвращает отчёт о несоответствиях

### When to Update ARCHITECTURE.md

Обновлять `ARCHITECTURE.md` при:
- Добавлении/удалении агентов
- Изменении routing tables
- Добавлении/изменении pipelines
- Изменении MCP server configurations
- Изменении identity probe whitelists

---

## 9. AGENTS.md — Project Rules

### Purpose

`AGENTS.md` определяет правила проекта для всех агентов. Загружается как instructions для каждого агента при старте сессии.

### Key Sections

#### MCP Tools Rules

- **Search**: Always use webSearchPrime MCP for web search
- **Read URLs**: Always use webReader MCP for reading webpage content
- **GitHub**: Always use zread MCP tools for GitHub repositories

#### Image Analysis Rules

- **PRIMARY**: view-image agent via Task tool
- **FALLBACK**: zai-mcp-server (only when view-image unavailable)
- view-image uses `kimi-for-coding/k2p6` with direct vision capabilities

#### Serena MCP Rules

- **PRIMARY**: Все Serena инструменты для code operations
- **FALLBACK**: Built-in tools (grep, read, edit) только когда Serena fails

#### unity-mcp Rules

- **PRIMARY**: unity-mcp для ALL Unity operations
- **FALLBACK**: Built-in tools только когда unity-mcp unavailable
- unity-mcp доступен для ВСЕХ агентов

#### Dual Primary Agents Architecture

- **orchestrator**: BUGFIX, DEVOPS, DEV, DOCS
- **plankestrator**: PLAN, RESEARCH, RESEARCH+PLAN
- Агенты НЕ вызывают друг друга — пользователь переключается вручную

#### Identity Verification

Оба primary агента выводят верификацию идентичности:
```
IDENTITY VERIFIED: I am [agent_name]. I am NOT [other_agent_name].
```

JSON output должен включать поле `agent`:
```json
{
  "agent": "orchestrator" | "plankestrator",
  ...
}
```

---

## 10. Plugin — workflow-enforcement.ts

### Location

`~/.config/opencode/plugins/workflow-enforcement.ts`

### Functionality

1. **Routing table enforcement** — через `tool.execute.before` hook
2. **JSON validation** — через `message.updated` event hook
3. **Identity drift detection** — через `message.updated` event hook
4. **Agent detection** — из session.created, message.updated, tool.execute.before
5. **Pipeline enforcement** — блокирует пропущенные шаги и дубликаты вызовов
6. **Pipeline advancement** — автоматически продвигает pipeline после завершения шага
7. **Incomplete pipeline warning** — предупреждает если сессия завершена с незавершённым pipeline

### Hooks

| Hook | Purpose |
|------|---------|
| `event` | Session lifecycle, identity tracking, JSON validation, **pipeline activation** |
| `tool.execute.before` | Routing table enforcement + **pipeline order enforcement** before tool calls |
| `tool.execute.after` | Log tool completion + **advance pipeline step** |

**Важно**: `session.created`, `session.idle`, `message.updated` — это НЕ top-level хуки, а **event types**, обрабатываемые внутри хука `event`.

### Pipeline Definitions

Плагин определяет ожидаемые последовательности агентов для каждого типа workflow:

| Pipeline Key | Sequence |
|---|---|
| `BUGFIX_SIMPLE` | `bugfix-triage → worker → utility` |
| `BUGFIX_DEEP` | `bugfix-triage → plan-bug (writes bug_plan.md) → execute-bug (reads bug_plan.md) → dev-reviewer → rework → consistency-checker → [rework loop, max 3] → utility` |
| `DEV_SIMPLE_NO_PLAN` | `worker → utility` |
| `DEV_SIMPLE_WITH_PLAN` | `worker → consistency-checker → utility` |
| `DEV_COMPLEX` | `dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → rework → consistency-checker → utility` |
| `DEV_SUPERCOMPLEX` | `PER PLAN STEP: dev-planner (writes dev_plan.md) → dev-professor (reviews dev_plan.md, implements) → dev-reviewer → consistency-checker → [rework loop, max 3] → utility` |
| `DEVOPS` | `devops-agent → devops-reviewer` |
| `DOCS` | `docs-writer → utility` |
| `PLAN_SIMPLE` | `plan-writer-simple → plan-reviewer-simple` |
| `PLAN_COMPLEX` | `plan-writer-complex → plan-reviewer-complex` |
| `PLAN_BUG` | `plan-bug` |
| `RESEARCH_SIMPLE` | `research-writer-simple → research-reviewer` |
| `RESEARCH_COMPLEX` | `research-writer-complex → research-reviewer` |

### Pipeline Enforcement Rules

| Violation Type | Behavior |
|----------------|----------|
| **Skipped Steps** | BLOCKED — нельзя пропускать шаги pipeline |
| **Duplicate Call** | BLOCKED — нельзя вызывать уже завершённого агента |
| **Agent Not in Pipeline** | WARNING (allowed) — identity probes и ad-hoc вызовы |
| **Out of Order** | WARNING — вызов не в ожидаемом порядке |

### Routing Tables in Plugin

```typescript
const ROUTING_TABLES = {
  orchestrator: [
    "orchestrator-identity-probe", "dev-reviewer", "dev-professor", "mcp-github",
    "worker", "bugfix", "rework", "mcp-read", "utility", "devops",
    "bugfix-triage", "plan-bug", "devops-agent", "devops-reviewer",
    "dev-planner", "mcp-search", "docs-writer", "summarizer",
    "execute-bug", "consistency-checker", "view-image"
  ],
  plankestrator: [
    "plankestrator-identity-probe", "plan-writer-simple", "plan-writer-complex",
    "plan-reviewer-simple", "plan-reviewer-complex", "research-writer-simple",
    "research-writer-complex", "research-reviewer", "devops-readonly"
  ]
}
```

### JSON Validation Rules

```typescript
const REQUIRED_JSON_FIELDS = {
  orchestrator: ["agent", "type", "complexity", "plan_exists", "plan_source", "goal", "next_agent", "pipeline"],
  plankestrator: ["agent", "state", "type", "complexity", "goal", "next_agent", "pipeline"]
}
```

### Error Messages

| Error | Trigger |
|-------|---------|
| `JSON OUTPUT REQUIRED` | Agent calls Task tool without outputting JSON first |
| `WORKFLOW VIOLATION` | Agent calls subagent not in routing table |
| `IDENTITY DRIFT DETECTED` | Agent identity changes between messages |

---

## 11. MCP Servers

### zread

| Field | Value |
|-------|-------|
| Type | Remote |
| URL | `https://api.z.ai/api/mcp/zread/mcp` |
| Auth | Bearer token (Z.AI API key) |

**Tools:**
| Tool | Purpose |
|------|---------|
| `zread_search_doc` | Search documentation, issues, PRs, code in GitHub repos |
| `zread_read_file` | Read complete file content from GitHub repo |
| `zread_get_repo_structure` | Get directory structure of GitHub repo |

### webSearchPrime

| Field | Value |
|-------|-------|
| Type | Remote |
| URL | `https://api.z.ai/api/mcp/web_search_prime/mcp` |
| Auth | Bearer token (Z.AI API key) |

**Tools:**
| Tool | Purpose |
|------|---------|
| `webSearchPrime_web_search_prime` | Web search with time/domain filters |

### webReader

| Field | Value |
|-------|-------|
| Type | Remote |
| URL | `https://api.z.ai/api/mcp/web_reader/mcp` |
| Auth | Bearer token (Z.AI API key) |

**Tools:**
| Tool | Purpose |
|------|---------|
| `webReader_webReader` | Fetch URL content, convert to markdown |

### serena

| Field | Value |
|-------|-------|
| Type | Local |
| Command | `serena start-mcp-server --transport stdio --context=ide --project-from-cwd` |
| Executable | `%USERPROFILE%\.local\bin\serena.exe` (adjust path per machine) |

**Tools:**
| Tool | Purpose |
|------|---------|
| `serena_find_symbol` | Find classes/functions by name |
| `serena_find_referencing_symbols` | Find all usages of a symbol |
| `serena_get_symbols_overview` | Get file structure overview |
| `serena_rename_symbol` | Rename symbol across codebase |
| `serena_safe_delete_symbol` | Delete symbol if safe |
| `serena_replace_symbol_body` | Replace symbol body |
| `serena_insert_after_symbol` | Insert code after symbol |

### unity-mcp

| Field | Value |
|-------|-------|
| Type | Remote |
| URL | `http://localhost:8080/mcp` |
| Prerequisites | Unity Editor running with MCP server started |

**Tools:** 20+ Unity Editor tools including:
- `manage_gameobject` — Create/modify/delete GameObjects
- `manage_scene` — Create/save scenes
- `manage_script` — CRUD operations on C# scripts
- `manage_asset` — Import/manage assets
- `read_console` — Read Unity console logs
- `manage_components` — Add/remove/configure components
- `manage_prefabs` — Prefab operations
- `manage_material` — Material operations
- `manage_animation` — Animation operations
- `manage_physics` — Physics operations
- `manage_build` — Build operations
- `manage_camera` — Camera operations
- `manage_graphics` — Graphics/rendering operations
- `manage_ui` — UI Toolkit operations
- `manage_vfx` — VFX operations
- `manage_profiler` — Profiler operations
- `manage_packages` — Package management
- `manage_editor` — Editor state control
- `batch_execute` — Batch operations (10-100x faster)
- `unity_docs` — Unity documentation lookup
- `unity_reflect` — Unity API reflection

### zai-mcp-server

| Field | Value |
|-------|-------|
| Type | Local |
| Command | `npx -y @z_ai/mcp-server` |
| Environment | `Z_AI_API_KEY`, `Z_AI_MODE=ZAI` |

**Purpose:** Image analysis (fallback when view-image unavailable)

---

## 12. Commands

Custom commands defined in opencode.json:

| Command | Description | Agent | Template |
|---------|-------------|-------|----------|
| `read-url` | Read content from a URL | mcp-read | `Read and analyze this URL: $ARGUMENTS` |
| `document` | Generate documentation | docs-writer | `Document the following: $ARGUMENTS` |
| `github` | Search GitHub repositories | mcp-github | `Search GitHub for: $ARGUMENTS` |
| `summarize` | Summarize content | summarizer | `Summarize the following: $ARGUMENTS` |
| `search` | Search the web for information | mcp-search | `Search for: $ARGUMENTS` |

All commands are `subtask: true` — they run as subagent tasks.

---

## 13. File Locations

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| opencode.json | `~/.config/opencode/opencode.json` | Main configuration (providers, MCP, agents, commands) |
| workflow-enforcement.ts | `~/.config/opencode/plugins/workflow-enforcement.ts` | Workflow enforcement plugin |
| [agent].md | `~/.config/opencode/agents/[name].md` | Individual agent definitions (32 files) |

### Data Storage

| Directory | Location | Purpose |
|-----------|----------|---------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite database |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | Session state differences |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | Task tracking |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Tool execution results |
| Logs | `~/.local/share/opencode/log/` | Execution logs |

### Project Files

| File | Location | Purpose |
|------|----------|---------|
| AGENTS.md | Project root | Project rules and agent permissions |
| ARCHITECTURE.md | Project root | Architecture requirements |
| PLUGIN.md | Project root | Plugin documentation |
| MCP_SETUP.md | Project root | This setup guide |
| dev_plan.md | Project root | Implementation plan (written by dev-planner) |
| bug_plan.md | Project root | Bug fix plan (written by plan-bug, read by execute-bug) |

### Agent Files List (32 files)

```
~/.config/opencode/agents/
├── orchestrator.md                    # Primary agent
├── plankestrator.md                   # Primary agent
├── orchestrator-identity-probe.md
├── plankestrator-identity-probe.md
├── worker.md
├── bugfix.md
├── bugfix-triage.md
├── plan-bug.md
├── execute-bug.md
├── dev-planner.md
├── dev-professor.md
├── dev-reviewer.md
├── rework.md
├── consistency-checker.md
├── docs-writer.md
├── utility.md
├── mcp-github.md
├── mcp-read.md
├── mcp-search.md
├── summarizer.md
├── devops.md
├── devops-agent.md
├── devops-reviewer.md
├── devops-readonly.md
├── plan-writer-simple.md
├── plan-writer-complex.md
├── plan-reviewer-simple.md
├── plan-reviewer-complex.md
├── research-writer-simple.md
├── research-writer-complex.md
├── research-reviewer.md
└── view-image.md
```

---

## 14. Troubleshooting

### Common Issues

#### Plugin Not Loading

**Symptoms:**
- No "Workflow enforcement plugin initialized" log
- Routing violations not blocked

**Solution:**
```powershell
# Проверить путь к плагину в opencode.json
cat $HOME\.config\opencode\opencode.json | Select-String "plugin"

# Проверить существование файла плагина
Test-Path $HOME\.config\opencode\plugins\workflow-enforcement.ts
```

#### MCP Server Not Connecting

**Symptoms:**
- MCP tools not available
- "MCP server not found" errors

**Solution:**
- Проверить конфигурацию MCP в opencode.json
- Проверить API keys
- Для serena: убедиться что `serena.exe` в PATH
- Для unity-mcp: убедиться что Unity Editor запущен с MCP сервером

#### Agent Identity Drift

**Symptoms:**
- "IDENTITY DRIFT DETECTED" warnings
- Agent calling wrong subagents

**Solution:**
- Проверить что frontmatter agent файла совпадает с opencode.json
- Убедиться что description агента содержит правильное имя
- Проверить формат identity verification output

#### Routing Violation

**Symptoms:**
- "WORKFLOW VIOLATION" errors
- Task tool calls blocked

**Solution:**
- Проверить routing table в плагине совпадает с whitelist в opencode.json
- Убедиться что агент вызывает правильный subagent для своего типа
- Проверить что JSON output включает правильное поле `"agent"`

#### view-image Cannot Read Files

**Symptoms:**
- view-image reports it cannot access files

**Solution:**
- Убедиться что view-image имеет `read: allow`, `glob: allow`, `grep: allow`
- view-image должен анализировать изображения напрямую через модель, НЕ через MCP серверы

#### Serena Not Working

**Symptoms:**
- serena_* tools not available
- "serena not found" errors

**Solution:**
- Убедиться что `serena.exe` установлен и в PATH
- Проверить что serena запускается: `serena --version`
- Проверить что проект открыт в IDE (serena использует `--project-from-cwd`)

### Debug Commands

```powershell
# Просмотреть последние логи
Get-Content $HOME\.local\share\opencode\log\*.log -Tail 100

# Поискать violations
Select-String "WORKFLOW VIOLATION" $HOME\.local\share\opencode\log\*.log

# Поискать drift
Select-String "IDENTITY DRIFT" $HOME\.local\share\opencode\log\*.log

# Поискать JSON errors
Select-String "INVALID JSON" $HOME\.local\share\opencode\log\*.log

# Просмотреть всю активность плагина
Select-String "workflow-enforcement" $HOME\.local\share\opencode\log\*.log
```

### Escape Hatches

Когда конфигурация сломана и opencode не запускается:

| Env Var | Purpose |
|---------|---------|
| `OPENCODE_DISABLE_PROJECT_CONFIG=1` | Пропустить локальный opencode.json проекта |
| `OPENCODE_CONFIG=/path/to/file.json` | Загрузить альтернативный конфиг |
| `OPENCODE_CONFIG_CONTENT='{}'` | Inject inline JSON как финальный merge |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS=1` | Пропустить default плагины |
| `OPENCODE_PURE=1` | Пропустить внешние плагины |
| `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` | Пропустить skills из ~/.claude/ |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | Пропустить skills из ~/.agents/ |

---

## 15. Verification Checklist

### Pre-Deployment

- [ ] Node.js 18+ installed
- [ ] OpenCode CLI installed
- [ ] Serena installed и в PATH
- [ ] zai-mcp-server доступен через npx
- [ ] Directory structure created

### Configuration

- [ ] opencode.json скопирован в `~/.config/opencode/`
- [ ] Plugin скопирован в `~/.config/opencode/plugins/`
- [ ] Все 32 agent файла скопированы в `~/.config/opencode/agents/`
- [ ] API keys настроены корректно
- [ ] MCP server URLs корректны
- [ ] Routing tables в плагине совпадают с opencode.json

### Post-Deployment

- [ ] OpenCode запускается без ошибок
- [ ] Plugin initialization log появляется
- [ ] MCP tools доступны (zread_*, webSearchPrime_*, webReader_*, serena_*, unity-mcp_*)
- [ ] orchestrator session работает
- [ ] plankestrator session работает
- [ ] Routing violations блокируются корректно
- [ ] JSON validation работает
- [ ] Identity drift detection работает
- [ ] view-image может анализировать изображения напрямую
- [ ] worker может выполнять bash команды

### Test Commands

```bash
# Test orchestrator
opencode --agent orchestrator
# Должно появиться: "Workflow enforcement plugin initialized"
# Должно появиться: "Session created — agent detected: orchestrator"

# Test plankestrator
opencode --agent plankestrator
# Должно появиться: "Session created — agent detected: plankestrator"

# Test routing violation (должно быть заблокировано)
# В orchestrator session, попробовать вызвать plan-writer-simple
# Должно появиться: "WORKFLOW VIOLATION" error

# Test MCP tools
# В любой session, использовать zread_search_doc
# Должно вернуть результаты поиска GitHub

# Test view-image
# В любой session, передать изображение view-image агенту
# Должно вернуть описание изображения
```

---

## Summary

| Component | Count | Location |
|-----------|-------|----------|
| Primary agents | 2 | `~/.config/opencode/agents/` |
| Subagents | 30 | `~/.config/opencode/agents/` |
| MCP servers | 6 | Configured in opencode.json |
| Plugin hooks | 3 | workflow-enforcement.ts |
| Routing tables | 2 | orchestrator (21), plankestrator (9) |
| Pipelines | 13 | BUGFIX, DEV, DEVOPS, DOCS, PLAN, RESEARCH |
| Custom commands | 5 | opencode.json |
| Models | 5 | alibaba, bailian, kimi, minimax |

### Quick Reference

| Task | Command |
|------|---------|
| Start orchestrator | `opencode --agent orchestrator` |
| Start plankestrator | `opencode --agent plankestrator` |
| View logs | `Get-Content ~/.local/share/opencode/log/*.log -Tail 100` |
| Check config | `cat ~/.config/opencode/opencode.json` |
| List agents | `ls ~/.config/opencode/agents/` |
| Test Serena | `serena --version` |
| Test unity-mcp | Открыть Unity Editor → `Window > MCP for Unity > Start Server` |

---

**Document Version:** 11.0
**Last Updated:** 2026-06-18
**Changes:** Added "Permission Model: edit vs write" section explaining that `write` is a tool name (not a permission key), `edit` permission controls edit/write/patch/multiedit tools, using `write: "*.md"` creates a DEAD KEY, correct syntax for file type restrictions, and dev-planner permission fix case study
**Author:** OpenCode Documentation Team
