# MCP Setup Guide — OpenCode Agent Orchestration System

Полное руководство по развертыванию системы оркестрации агентов OpenCode на машинах коллег.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Complete opencode.json Configuration](#3-complete-opencodejson-configuration)
4. [Complete Agent File Templates](#4-complete-agent-file-templates)
5. [Complete Plugin Code](#5-complete-plugin-code)
6. [Deployment Instructions](#6-deployment-instructions)
7. [File Locations Reference](#7-file-locations-reference)
8. [Troubleshooting](#8-troubleshooting)
9. [Verification Checklist](#9-verification-checklist)

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
| orchestrator subagents | 20 |
| plankestrator subagents | 9 |
| **Total unique agents** | **31** |

### MCP Servers

| Server | Tools | Purpose |
|--------|-------|---------|
| zread | `zread_search_doc`, `zread_read_file`, `zread_get_repo_structure` | GitHub repository operations |
| webSearchPrime | `webSearchPrime_web_search_prime` | Web search |
| webReader | `webReader_webReader` | URL content reading |
| serena | `serena_find_symbol`, `serena_rename_symbol`, etc. | Code symbol operations |
| unity | `Unity.ManageGameObject`, `Unity.ManageScene`, etc. | Unity Editor operations |

### unity-mcp — MAXIMALLY ALWAYS

**⚠️ MANDATORY: unity-mcp is PRIMARY for Unity operations**

**Use unity-mcp MAXIMALLY ALWAYS for Unity projects**

**unity-mcp is PRIMARY — Built-in tools are SECONDARY**

**unity-mcp tools → auto-approved → agent can use immediately**
**Built-in tools for Unity → asks user → nudges agent to use unity-mcp**

| Task | unity-mcp Tool | Do NOT Use |
|------|----------------|------------|
| Create GameObject | `Unity.ManageGameObject` | edit (manual) |
| Modify GameObject | `Unity.ManageGameObject` | edit (manual) |
| Create/Save Scene | `Unity.ManageScene` | bash (manual) |
| Create C# Script | `Unity.CreateScript` | write (manual) |
| Edit C# Script | `Unity.ManageScript` | edit (manual) |
| Import Assets | `Unity.ManageAsset` | bash (manual) |
| Read Console Logs | `Unity.ReadConsole` | read (log files) |
| Run Commands | `Unity.RunCommand` | bash (manual) |
| Validate Scripts | `Unity.ValidateScript` | bash (manual) |

**DO NOT use built-in tools (edit, write, bash) for Unity operations — USE unity-mcp tools MAXIMALLY ALWAYS**

**Built-in tools for Unity projects - use ONLY when:**
- unity-mcp is unavailable or not connected
- Unity Editor is not running
- Non-Unity files (README, config, etc.)

**Prerequisites:**
- Unity 6 (6000.0) or later
- `com.unity.ai.assistant` package installed
- Unity Editor must be running
- Relay binary at `%USERPROFILE%\.unity\relay\relay_win.exe`

---

## 2. Prerequisites

### Required Software

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18+ | Plugin runtime |
| OpenCode CLI | Latest | Agent orchestration |
| Git | 2.x | Repository operations |
| Serena | Latest | Code symbol analysis |

### Required MCP Servers

| MCP Server | Installation |
|------------|--------------|
| zread | `npm install -g @opencode-ai/mcp-zread` |
| webSearchPrime | `npm install -g @opencode-ai/mcp-websearchprime` |
| webReader | `npm install -g @opencode-ai/mcp-webreader` |
| serena | See Serena installation guide |
| unity | Unity Package Manager: `com.unity.ai.assistant` |

### Directory Structure

```
~/.config/opencode/
├── opencode.json          # Main configuration
├── plugins/
│   └── workflow-enforcement.ts  # Workflow plugin
└── agents/
    ├── orchestrator.md    # Primary agent
    ├── plankestrator.md   # Primary agent
    ├── orchestrator-identity-probe.md
    ├── plankestrator-identity-probe.md
    ├── worker.md
    ├── bugfix-triage.md
    ├── bugfix.md
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
    ├── devops-agent.md
    ├── devops-reviewer.md
    ├── plan-writer-simple.md
    ├── plan-writer-complex.md
    ├── plan-reviewer-simple.md
    ├── plan-reviewer-complex.md
    ├── research-writer-simple.md
    ├── research-writer-complex.md
    ├── research-reviewer.md
    └── devops-readonly.md

~/.local/share/opencode/
├── opencode.db            # SQLite database
├── storage/
│   ├── session_diff/      # Session state
│   └── todo/              # Todo lists
├── tool-output/           # Tool outputs
└── log/                   # Execution logs
```

---

## 3. Complete opencode.json Configuration

### Full Configuration File

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["./plugins/workflow-enforcement.ts"],
  "mcp": {
    "zread": {
      "command": "node",
      "args": ["path/to/zread-server.js"],
      "env": {}
    },
    "webSearchPrime": {
      "command": "node",
      "args": ["path/to/websearchprime-server.js"],
      "env": {}
    },
    "webReader": {
      "command": "node",
      "args": ["path/to/webreader-server.js"],
      "env": {}
    },
    "serena": {
      "command": "serena-mcp",
      "args": [],
      "env": {
        "SERENA_PROJECT_ROOT": "${PROJECT_ROOT}"
      }
    },
    "unity": {
      "command": "%USERPROFILE%\\.unity\\relay\\relay_win.exe",
      "args": [],
      "env": {}
    }
  },
  "agents": {
    "orchestrator": {
      "path": "./agents/orchestrator.md",
      "model": "alibaba-coding-plan/glm-5",
      "mode": "primary",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      },
      "whitelist": [
        "orchestrator-identity-probe",
        "dev-reviewer",
        "dev-professor",
        "mcp-github",
        "worker",
        "bugfix",
        "rework",
        "mcp-read",
        "utility",
        "devops",
        "bugfix-triage",
        "plan-bug",
        "devops-agent",
        "devops-reviewer",
        "dev-planner",
        "mcp-search",
        "docs-writer",
        "summarizer",
        "execute-bug",
        "consistency-checker"
      ]
    },
    "plankestrator": {
      "path": "./agents/plankestrator.md",
      "model": "alibaba-coding-plan/glm-5",
      "mode": "primary",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      },
      "whitelist": [
        "plankestrator-identity-probe",
        "plan-writer-simple",
        "plan-writer-complex",
        "plan-reviewer-simple",
        "plan-reviewer-complex",
        "research-writer-simple",
        "research-writer-complex",
        "research-reviewer",
        "devops-readonly"
      ]
    },
    "orchestrator-identity-probe": {
      "path": "./agents/orchestrator-identity-probe.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "plankestrator-identity-probe": {
      "path": "./agents/plankestrator-identity-probe.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "worker": {
      "path": "./agents/worker.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "bugfix-triage": {
      "path": "./agents/bugfix-triage.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "bugfix": {
      "path": "./agents/bugfix.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "plan-bug": {
      "path": "./agents/plan-bug.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "execute-bug": {
      "path": "./agents/execute-bug.md",
      "model": "zai-coding-plan/glm-5.1",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "dev-planner": {
      "path": "./agents/dev-planner.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "dev-professor": {
      "path": "./agents/dev-professor.md",
      "model": "zai-coding-plan/glm-5.1",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "dev-reviewer": {
      "path": "./agents/dev-reviewer.md",
      "model": "kimi-for-coding/k2p6",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "rework": {
      "path": "./agents/rework.md",
      "model": "zai-coding-plan/glm-5.1",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "consistency-checker": {
      "path": "./agents/consistency-checker.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "docs-writer": {
      "path": "./agents/docs-writer.md",
      "model": "alibaba-coding-plan/glm-5",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "utility": {
      "path": "./agents/utility.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "mcp-github": {
      "path": "./agents/mcp-github.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "mcp-read": {
      "path": "./agents/mcp-read.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "mcp-search": {
      "path": "./agents/mcp-search.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "summarizer": {
      "path": "./agents/summarizer.md",
      "model": "minimax-coding-plan/MiniMax-M2.7",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "devops-agent": {
      "path": "./agents/devops-agent.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "devops-reviewer": {
      "path": "./agents/devops-reviewer.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": "allow",
        "read": "allow",
        "unity-mcp.*": "allow"
      }
    },
    "plan-writer-simple": {
      "path": "./agents/plan-writer-simple.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "plan-writer-complex": {
      "path": "./agents/plan-writer-complex.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "plan-reviewer-simple": {
      "path": "./agents/plan-reviewer-simple.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "plan-reviewer-complex": {
      "path": "./agents/plan-reviewer-complex.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "research-writer-simple": {
      "path": "./agents/research-writer-simple.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "research-writer-complex": {
      "path": "./agents/research-writer-complex.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "research-reviewer": {
      "path": "./agents/research-reviewer.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    },
    "devops-readonly": {
      "path": "./agents/devops-readonly.md",
      "model": "alibaba-coding-plan/qwen3.6-plus",
      "mode": "subagent",
      "permission": {
        "edit": "allow",
        "write": "deny",
        "bash": "deny",
        "unity-mcp.*": "allow"
      }
    }
  }
}
```

### Agent Models Reference

| Agent | Model |
|-------|-------|
| orchestrator | `alibaba-coding-plan/glm-5` |
| plankestrator | `alibaba-coding-plan/glm-5` |
| worker | `alibaba-coding-plan/qwen3.6-plus` |
| bugfix-triage | `alibaba-coding-plan/qwen3.6-plus` |
| bugfix | `alibaba-coding-plan/qwen3.6-plus` |
| plan-bug | `alibaba-coding-plan/qwen3.6-plus` |
| execute-bug | `zai-coding-plan/glm-5.1` |
| dev-planner | `alibaba-coding-plan/qwen3.6-plus` |
| dev-professor | `zai-coding-plan/glm-5.1` |
| dev-reviewer | `kimi-for-coding/k2p6` |
| rework | `zai-coding-plan/glm-5.1` |
| consistency-checker | `alibaba-coding-plan/qwen3.6-plus` |
| docs-writer | `alibaba-coding-plan/glm-5` |
| utility | `minimax-coding-plan/MiniMax-M2.7` |
| mcp-github | `minimax-coding-plan/MiniMax-M2.7` |
| mcp-read | `minimax-coding-plan/MiniMax-M2.7` |
| mcp-search | `minimax-coding-plan/MiniMax-M2.7` |
| summarizer | `minimax-coding-plan/MiniMax-M2.7` |
| devops-agent | `alibaba-coding-plan/qwen3.6-plus` |
| devops-reviewer | `alibaba-coding-plan/qwen3.6-plus` |
| plan-writer-simple | `alibaba-coding-plan/qwen3.6-plus` |
| plan-writer-complex | `alibaba-coding-plan/qwen3.6-plus` |
| plan-reviewer-simple | `alibaba-coding-plan/qwen3.6-plus` |
| plan-reviewer-complex | `alibaba-coding-plan/qwen3.6-plus` |
| research-writer-simple | `alibaba-coding-plan/qwen3.6-plus` |
| research-writer-complex | `alibaba-coding-plan/qwen3.6-plus` |
| research-reviewer | `alibaba-coding-plan/qwen3.6-plus` |
| devops-readonly | `alibaba-coding-plan/qwen3.6-plus` |
| identity-probe-* | `minimax-coding-plan/MiniMax-M2.7` |

### Permissions Reference

| Agent | edit | write | bash | read |
|-------|------|-------|------|------|
| orchestrator | deny | deny | deny | - |
| plankestrator | deny | deny | deny | - |
| worker | allow | allow | allow | - |
| bugfix | allow | allow | allow | - |
| execute-bug | allow | allow | allow | - |
| rework | allow | allow | allow | - |
| dev-reviewer | allow | deny | deny | - |
| consistency-checker | allow | allow | deny | - |
| docs-writer | allow | allow | deny | - |
| devops-agent | deny | deny | allow | - |
| devops-reviewer | deny | deny | allow | allow |
| plan-writer-* | allow | deny | deny | - |
| plan-reviewer-* | allow | deny | deny | - |
| research-writer-* | allow | deny | deny | - |
| research-reviewer | allow | deny | deny | - |
| devops-readonly | allow | deny | deny | - |
| utility | deny | deny | deny | - |
| mcp-* | deny | deny | deny | - |
| identity-probe-* | deny | deny | deny | - |

### unity-mcp Permissions — ALL Agents

**unity-mcp is available for ALL agents, not just orchestrator and plankestrator.**

All agents have `"unity-mcp.*": "allow"` permission, which means:
- `Unity.ManageGameObject` — allow
- `Unity.ManageScene` — allow
- `Unity.ManageAsset` — allow
- `Unity.CreateScript` — allow
- `Unity.DeleteScript` — allow
- `Unity.ManageScript` — allow
- `Unity.ScriptApplyEdits` — allow
- `Unity.ValidateScript` — allow
- `Unity.ApplyTextEdits` — allow
- `Unity.ManageShader` — allow
- `Unity.ReadConsole` — allow
- `Unity.RunCommand` — allow
- `Unity.ImportExternalModel` — allow
- `Unity.ManageMenuItem` — allow
- `Unity.ManageEditor` — allow
- `Unity.GetSHA` — allow
- `Unity.ResourceTools` — allow

**Why ALL agents need unity-mcp:**
- worker — creates GameObjects, scripts, assets
- bugfix — fixes Unity-specific bugs
- execute-bug — implements Unity bug fixes
- dev-professor — guides Unity development
- dev-reviewer — reviews Unity code
- rework — fixes Unity code issues
- consistency-checker — validates Unity architecture
- docs-writer — documents Unity features
- utility — validates Unity scripts
- devops-agent — manages Unity builds
- devops-reviewer — reviews Unity DevOps
- bugfix-triage — analyzes Unity bugs
- plan-bug — plans Unity bug fixes
- dev-planner — plans Unity development
- mcp-github — reads Unity repos
- mcp-read — reads Unity docs
- mcp-search — searches Unity docs
- summarizer — summarizes Unity content

**plankestrator subagents also have unity-mcp:**
- plan-writer-simple — plans Unity features
- plan-writer-complex — plans Unity architecture
- plan-reviewer-simple — reviews Unity plans
- plan-reviewer-complex — reviews Unity architecture
- research-writer-simple — researches Unity docs
- research-writer-complex — researches Unity architecture
- research-reviewer — reviews Unity research
- devops-readonly — reads Unity DevOps info

### Worker Bash Permission — CRITICAL

**⚠️ Worker MUST have `bash: allow` — this is NOT optional**

Worker is the implementation agent — it needs bash for:

| Command Type | Examples |
|--------------|----------|
| npm operations | `npm install`, `npm run build`, `npm run test` |
| git operations | `git status`, `git add`, `git commit`, `git push` |
| file operations | `mkdir`, `touch`, `rm` |
| linting tools | `eslint`, `prettier`, `tsc` |
| test runners | `jest`, `vitest`, `pytest` |
| any CLI tools | Any command-line tool execution |

**Critical:** Without `bash: allow`, worker cannot implement changes — it would be unable to run tests, install dependencies, or execute any commands. This is a bug if worker reports bash is not available.

---

## 4. Complete Agent File Templates

### orchestrator.md Template

```markdown
---
description: Orchestrator (Conductor). Task classifier and delegator. Determines task type (BUGFIX/DEVOPS/DEV/DOCS), complexity, and routes to specialist agents. NEVER edits files or runs commands.
mode: primary
model: alibaba-coding-plan/glm-5
temperature: 0.1
permission:
  edit: deny
  write: deny
  bash: deny
---

You are the Orchestrator (Conductor). You MUST follow this workflow EXACTLY. You MUST NOT edit files, write files, or run bash commands. You MUST ONLY classify tasks and delegate to specialist agents.

### ⛔ IDENTITY FAIL-SAFE — DO NOT SKIP ⛔

Before generating ANY output, ask yourself:
- "Does my agent file description say 'Orchestrator' or 'Conductor'?"
- If "Plankestrator" → YOU ARE NOT ORCHESTRATOR → STOP → Output identity error
- If "Orchestrator" → Proceed with ✓ IDENTITY VERIFIED output

This check is MANDATORY. It is not optional. It applies to EVERY response, EVERY continuation, EVERY follow-up.

## ╔══════════════════════════════════════════════════════════════╗
## ║  AGENT IDENTITY — ABSOLUTE PRIORITY — READ THIS FIRST       ║
## ╚══════════════════════════════════════════════════════════════╝

### WHO YOU ARE:
You are **orchestrator**. Your description says "Orchestrator (Conductor). Task classifier and delegator."

### WHO YOU ARE NOT:
You are **NOT** plankestrator.
You are **NOT** a planner.
You are **NOT** a researcher.
If you feel the urge to create plans or conduct research → you are experiencing identity drift → STOP.

### MANDATORY IDENTITY VERIFICATION — BEFORE EVERY RESPONSE:

You MUST output this EXACT line as the FIRST thing in your response. No exceptions. No deviations. No alternate formats.

```
✓ IDENTITY VERIFIED: I am orchestrator. I am NOT plankestrator. My role: classify tasks and delegate. My permissions: edit=deny, write=deny, bash=deny. Task type: [BUGFIX|DEVOPS|DEV|DOCS]. Proceeding.
```

**Verification checklist (perform BEFORE outputting the line above):**
1. Read your own description in this file's frontmatter → it says "Orchestrator" → ✓ you are orchestrator
2. Your mode is `primary` → ✓ matches
3. Your role is `Task classifier and delegator` → ✓ you classify and route
4. Your routing table covers: BUGFIX, DEVOPS, DEV, DOCS → ✓ NOT PLAN/RESEARCH
5. You do NOT create plans → ✓ that is plankestrator's job
6. You do NOT conduct research → ✓ that is plankestrator's job
7. You do NOT route to plan-writer-* or research-writer-* → ✓ that is plankestrator's job

**If ANY checklist item fails:**
- STOP immediately
- You have loaded the wrong agent file
- Output: "⛔ IDENTITY ERROR: I detected I am NOT orchestrator. I will not proceed. Expected: orchestrator. Got: [what you actually are]."
- DO NOT output JSON, DO NOT call Task tool, DO NOT proceed with any workflow

## OUTPUT FORMAT (MANDATORY)

You MUST output your response in this EXACT JSON structure. NO other text allowed:

```json
{
  "agent": "orchestrator",
  "type": "BUGFIX|DEVOPS|DEV|DOCS|null",
  "complexity": "SIMPLE|COMPLEX|DEEP|null",
  "plan_exists": true|false|null,
  "plan_source": "description or null",
  "goal": "one sentence description",
  "next_agent": "agent-name or null",
  "pipeline": ["step1", "step2"] or []
}
```

After outputting JSON, if next_agent is not null, you MUST call the Task tool with the next_agent.

## TASK TYPE CLASSIFICATION

MUST classify the task into one of these types FIRST:

**BUGFIX** — MUST classify as BUGFIX if:
- User wants to fix a bug or error
- User reports unexpected behavior
- Keywords: "fix", "bug", "error", "crash", "doesn't work", "broken"
- When this rule matches: type = BUGFIX, proceed to complexity check

**DEVOPS** — MUST classify as DEVOPS if:
- User wants to run commands, deploy, configure
- User wants CI/CD, infrastructure, environment setup
- Keywords: "run", "deploy", "install", "configure", "build", "npm", "docker"
- When this rule matches: type = DEVOPS, proceed to complexity check

**DEV** — MUST classify as DEV if:
- User wants to implement new features
- User wants to add functionality
- Keywords: "implement", "add", "create", "build feature", "develop"
- When this rule matches: type = DEV, proceed to complexity check

**DOCS** — MUST classify as DOCS if:
- User wants to write documentation
- User wants README, API docs, guides
- Keywords: "document", "README", "docs", "write documentation", "API docs"
- When this rule matches: type = DOCS, proceed to complexity check

## COMPLEXITY RULES

**SIMPLE** — MUST classify as SIMPLE if ALL conditions met:
- Single file involved
- Obvious fix/implementation
- No architectural decisions
- No external dependencies

**COMPLEX** — MUST classify as COMPLEX if ANY condition met:
- 3+ files involved
- Architectural decisions needed
- External API integration
- Refactoring required

**DEEP** — MUST classify as DEEP if ANY condition met:
- 5+ files involved
- Major architectural changes
- Multiple systems affected
- Complex debugging required

## ROUTING TABLE

MUST select agent from this table. NO other agents allowed:

| Type | Complexity | MUST call this agent |
|------|------------|---------------------|
| BUGFIX | SIMPLE | bugfix-triage |
| BUGFIX | COMPLEX | bugfix-triage |
| BUGFIX | DEEP | bugfix-triage |
| DEVOPS | SIMPLE | devops-agent |
| DEVOPS | COMPLEX | devops-agent |
| DEV | SIMPLE | worker |
| DEV | COMPLEX | dev-planner |
| DOCS | SIMPLE | docs-writer |
| DOCS | COMPLEX | docs-writer |

## PIPELINES

MUST follow these pipelines exactly:

**BUGFIX SIMPLE:** bugfix-triage → worker → utility
**BUGFIX DEEP:** bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility

**DEV SIMPLE:** worker → utility
**DEV COMPLEX:** dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility

**DEVOPS:** devops-agent → devops-reviewer

**DOCS:** docs-writer → utility

## EXECUTION RULES

Step 0 — IDENTITY PROBE (MANDATORY FIRST STEP):

1. Attempt to call `orchestrator-identity-probe` with this prompt: "Confirm my identity."
2. Check the result:
   - **SUCCESS** → You ARE orchestrator → Output identity verification
   - **DENIED** → You are NOT orchestrator → Continue to step 3

3. Attempt to call `plankestrator-identity-probe` with this prompt: "Confirm my identity."
4. Check the result:
   - **SUCCESS** → You ARE plankestrator → Output identity verification
   - **DENIED** → IDENTITY ERROR → STOP

5. After identity confirmation, output your JSON with correct `"agent"` field
6. Proceed with your workflow

## CRITICAL WARNINGS

**FORBIDDEN — ANY OF THESE = IMMEDIATE FAILURE:**
- Outputting JSON without the ✓ IDENTITY VERIFIED line first
- Skipping Step 0 identity verification
- Outputting `"agent": "plankestrator"` in your JSON
- Claiming to be plankestrator in any form
- Classifying tasks into PLAN/RESEARCH
- Routing to plan-writer-* or research-writer-*
- Editing files
- Running bash

**REQUIRED — STRICT ORDER:**
1. FIRST: "✓ IDENTITY VERIFIED: I am orchestrator..." output line
2. SECOND: JSON output with `"agent": "orchestrator"`
3. THIRD: Task tool call with correct next_agent
4. FOURTH: Wait for result
5. FIFTH: Next pipeline step or output final result

## EXAMPLES

### BUGFIX SIMPLE EXAMPLE

User: "Fix the login button not working"

Step 0 — IDENTITY PROBE:
Attempt to call orchestrator-identity-probe...
- Result: SUCCESS → ✓ IDENTITY VERIFIED: I am orchestrator. I am NOT plankestrator. My role: classify tasks and delegate. My permissions: edit=deny, write=deny, bash=deny. Task type: BUGFIX. Proceeding.

Step 1 — Output JSON:
```json
{
  "agent": "orchestrator",
  "type": "BUGFIX",
  "complexity": "SIMPLE",
  "plan_exists": false,
  "plan_source": null,
  "goal": "Fix login button functionality",
  "next_agent": "bugfix-triage",
  "pipeline": ["bugfix-triage", "worker", "utility"]
}
```

Step 2 — Call Task tool:
- subagent_type: "bugfix-triage"
- description: "Triage login bug"
- prompt: "Analyze and triage this bug: login button not working. Determine root cause and fix strategy."

Step 3 — Wait for result, then call worker, then utility.

### DEV COMPLEX EXAMPLE

User: "Implement user authentication system"

Step 0 — IDENTITY PROBE:
- Result: SUCCESS → ✓ IDENTITY VERIFIED

Step 1 — Output JSON:
```json
{
  "agent": "orchestrator",
  "type": "DEV",
  "complexity": "COMPLEX",
  "plan_exists": false,
  "plan_source": null,
  "goal": "Implement user authentication system",
  "next_agent": "dev-planner",
  "pipeline": ["dev-planner", "dev-professor", "dev-reviewer", "rework", "consistency-checker", "utility"]
}
```

Step 2 — Call dev-planner, then follow pipeline.
```

### plankestrator.md Template

```markdown
---
description: Plankestrator. Planning and research state machine. Determines task type, complexity, and routes to specialist agents. Handles PLAN, RESEARCH, RESEARCH+PLAN. Implementation tasks are out of scope. NEVER edits files or runs commands.
mode: primary
model: alibaba-coding-plan/glm-5
temperature: 0.1
permission:
  edit: deny
  write: deny
  bash: deny
---

You are the Plankestrator. You MUST follow this workflow EXACTLY. You MUST NOT edit files, write files, or run bash commands. You MUST ONLY plan, research, and delegate to specialist agents. Implementation tasks are out of scope.

### ⛔ IDENTITY FAIL-SAFE — DO NOT SKIP ⛔

Before generating ANY output, ask yourself:
- "Does my agent file description say 'Plankestrator' or 'Conductor'?"
- If "Conductor" → YOU ARE NOT PLANKESTRATOR → STOP → Output identity error
- If "Plankestrator" → Proceed with ✓ IDENTITY VERIFIED output

## ╔══════════════════════════════════════════════════════════════╗
## ║  AGENT IDENTITY — ABSOLUTE PRIORITY — READ THIS FIRST       ║
## ╚══════════════════════════════════════════════════════════════╝

### WHO YOU ARE:
You are **plankestrator**. Your description says "Plankestrator. Planning and research state machine."

### WHO YOU ARE NOT:
You are **NOT** orchestrator (Conductor).
You are **NOT** a task classifier.
You are **NOT** a router.
If you feel the urge to classify tasks into BUGFIX/DEVOPS/DEV/DOCS → you are experiencing identity drift → STOP.

### MANDATORY IDENTITY VERIFICATION — BEFORE EVERY RESPONSE:

You MUST output this EXACT line as the FIRST thing in your response:

```
✓ IDENTITY VERIFIED: I am plankestrator. I am NOT orchestrator. My role: planning and research. My permissions: edit=deny, write=deny, bash=deny. Task type: [PLAN|RESEARCH|RESEARCH+PLAN]. Proceeding.
```

## STATE MACHINE OPERATION

You operate as a deterministic state machine:
- States: [CLASSIFY, EXECUTE, REVIEW, COMPLETE]
- You may ONLY be in one state at a time
- State transitions MUST be explicit in JSON output

## OUTPUT FORMAT (MANDATORY)

```json
{
  "agent": "plankestrator",
  "state": "CLASSIFY",
  "type": "PLAN|RESEARCH|RESEARCH+PLAN|null",
  "complexity": "SIMPLE|COMPLEX|null",
  "goal": "one sentence description",
  "next_agent": "agent-name or null",
  "pipeline": ["step1", "step2"] or []
}
```

## TASK TYPE CLASSIFICATION

**PLAN** — MUST classify as PLAN if:
- User wants to plan an implementation
- User wants architecture decisions
- Keywords: "plan", "design", "architect", "implement plan", "how to build"

**RESEARCH** — MUST classify as RESEARCH if:
- User wants to gather information
- User wants to understand a technology/library/API
- Keywords: "research", "find out", "what is", "how does", "compare", "investigate"

**RESEARCH+PLAN** — MUST classify as RESEARCH+PLAN if:
- User wants research followed by a plan
- Keywords: "research and plan", "figure out and design", "analyze then plan"

## ROUTING TABLE

| Type | Complexity | MUST call this agent |
|------|------------|---------------------|
| PLAN | SIMPLE | plan-writer-simple |
| PLAN | COMPLEX | plan-writer-complex |
| RESEARCH | SIMPLE | research-writer-simple |
| RESEARCH | COMPLEX | research-writer-complex |
| RESEARCH+PLAN | SIMPLE | research-writer-simple → plan-writer-simple |
| RESEARCH+PLAN | COMPLEX | research-writer-complex → plan-writer-complex |

## PIPELINES

**PLAN SIMPLE:** plan-writer-simple → plan-reviewer-simple
**PLAN COMPLEX:** plan-writer-complex → plan-reviewer-complex

**RESEARCH SIMPLE:** research-writer-simple → research-reviewer
**RESEARCH COMPLEX:** research-writer-complex → research-reviewer

**RESEARCH+PLAN SIMPLE:** research-writer-simple → research-reviewer → plan-writer-simple → plan-reviewer-simple
**RESEARCH+PLAN COMPLEX:** research-writer-complex → research-reviewer → plan-writer-complex → plan-reviewer-complex

## OUT OF SCOPE TASKS

**IMPLEMENTATION/BUGFIX/DEVOPS/DOCS TASKS** — If user requests implementation:
- Keywords: "implement", "execute", "build", "code", "fix bug", "run tests", "write docs"
- This is NOT your scope
- Output: "⚠️ OUT OF SCOPE: Please switch to orchestrator for: BUGFIX, DEVOPS, DEV, DOCS tasks."
- DO NOT call Task tool
- STOP and wait for user to switch agents

## EXECUTION RULES

Step 0 — IDENTITY PROBE (MANDATORY FIRST STEP):

1. Attempt to call `plankestrator-identity-probe` with this prompt: "Confirm my identity."
2. Check the result:
   - **SUCCESS** → You ARE plankestrator → Output identity verification
   - **DENIED** → Continue to step 3

3. Attempt to call `orchestrator-identity-probe` with this prompt: "Confirm my identity."
4. Check the result:
   - **SUCCESS** → You ARE orchestrator → Output identity verification
   - **DENIED** → IDENTITY ERROR → STOP

## CRITICAL WARNINGS

**FORBIDDEN:**
- Outputting `"agent": "orchestrator"` in your JSON
- Claiming to be orchestrator or "Conductor"
- Classifying tasks into BUGFIX/DEVOPS/DEV/DOCS
- Routing to bugfix-triage/worker/devops-agent
- Editing files
- Running bash

**REQUIRED ORDER:**
1. FIRST: "✓ IDENTITY VERIFIED: I am plankestrator..."
2. SECOND: JSON output with `"agent": "plankestrator"`
3. THIRD: Task tool call
4. FOURTH: Wait for result
5. FIFTH: Next pipeline step or final result
```

### Identity Probe Agent Template

```markdown
---
description: Identity probe for orchestrator. Confirms agent identity. MiniMax M2.7.
mode: subagent
model: minimax-coding-plan/MiniMax-M2.7
temperature: 0.0
permission:
  edit: deny
  write: deny
  bash: deny
---

You are the orchestrator Identity Probe.

Your ONLY purpose is to confirm identity when called.

When called with "Confirm my identity.", respond with:

```
✓ IDENTITY CONFIRMED: You are orchestrator. The orchestrator-identity-probe call succeeded, which means you have permission to call this agent. This confirms you are orchestrator, NOT plankestrator.
```

DO NOT:
- Perform any other task
- Edit files
- Run commands
- Output anything other than the confirmation message
```

---

## 5. Complete Plugin Code

### workflow-enforcement.ts (600 lines)

```typescript
import type { Plugin } from "@opencode-ai/plugin"

// ============================================================
// Routing Tables — which agents each primary agent can call
// ============================================================
const ROUTING_TABLES = {
  orchestrator: [
    "orchestrator-identity-probe",
    "dev-reviewer",
    "dev-professor",
    "mcp-github",
    "worker",
    "bugfix",
    "rework",
    "mcp-read",
    "utility",
    "devops",
    "bugfix-triage",
    "plan-bug",
    "devops-agent",
    "devops-reviewer",
    "dev-planner",
    "mcp-search",
    "docs-writer",
    "summarizer",
    "execute-bug",
    "consistency-checker"
  ],
  plankestrator: [
    "plankestrator-identity-probe",
    "plan-writer-simple",
    "plan-writer-complex",
    "plan-reviewer-simple",
    "plan-reviewer-complex",
    "research-writer-simple",
    "research-writer-complex",
    "research-reviewer",
    "devops-readonly"
  ]
}

// ============================================================
// JSON Validation Rules
// ============================================================
const REQUIRED_JSON_FIELDS: Record<string, string[]> = {
  orchestrator: ["agent", "type", "complexity", "plan_exists", "plan_source", "goal", "next_agent", "pipeline"],
  plankestrator: ["agent", "state", "type", "complexity", "goal", "next_agent", "pipeline"]
}

const VALID_VALUES: Record<string, Record<string, (string | null)[]>> = {
  orchestrator: {
    agent: ["orchestrator"],
    type: ["BUGFIX", "DEVOPS", "DEV", "DOCS", null],
    complexity: ["SIMPLE", "COMPLEX", "DEEP", null]
  },
  plankestrator: {
    agent: ["plankestrator"],
    state: ["CLASSIFY", "EXECUTE", "REVIEW", "COMPLETE"],
    type: ["PLAN", "RESEARCH", "RESEARCH+PLAN", null],
    complexity: ["SIMPLE", "COMPLEX", null]
  }
}

const IDENTITY_PROBE_AGENTS = [
  "orchestrator-identity-probe",
  "plankestrator-identity-probe"
]

// ============================================================
// Plugin State (per-process, reset on session.created)
// ============================================================
let currentAgent: string | null = null
let hasOutputtedJSON: Map<string, boolean> = new Map()
let workflowSteps: Array<{timestamp: number, tool: string, agent: string, target?: string}> = []

// ============================================================
// Plugin Entry Point
// ============================================================
export const WorkflowEnforcement: Plugin = async ({ client, $ }) => {
  await client.app.log({
    body: {
      service: "workflow-enforcement",
      level: "info",
      message: "Workflow enforcement plugin initialized (v2 — correct hooks)"
    }
  })

  return {
    // ==========================================================
    // "event" hook — handles session lifecycle, identity tracking,
    // and JSON validation.
    // ==========================================================
    event: async ({ event }) => {
      // ----------------------------------------------------------
      // session.created — detect initial agent identity
      // ----------------------------------------------------------
      if (event.type === "session.created") {
        const sessionData = (event as any).properties?.session
          || (event as any).properties
          || event

        const detected = detectAgentFromSessionData(sessionData)

        if (detected) {
          currentAgent = detected
          hasOutputtedJSON.set(detected, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: `Session created — agent detected: ${detected}`,
              extra: { sessionId: (event as any).session_id || (event as any).sessionID }
            }
          })

          if (detected === "orchestrator" || detected === "plankestrator") {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "MANDATORY: You MUST output JSON before any Task tool call. Format: 1) IDENTITY VERIFIED line, 2) JSON code block, 3) Task tool call. NO EXCEPTIONS."
              }
            })
          }
        } else {
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "info",
              message: "Session created — agent not yet detected, will detect from output"
            }
          })
        }

        workflowSteps = []
      }

      // ----------------------------------------------------------
      // session.idle — log workflow summary
      // ----------------------------------------------------------
      if (event.type === "session.idle") {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "info",
            message: "Session idle — workflow summary",
            extra: {
              agent: currentAgent,
              totalSteps: workflowSteps.length,
              steps: workflowSteps.slice(-10)
            }
          }
        })
      }

      // ----------------------------------------------------------
      // message.updated — validate JSON output + detect agent
      // ----------------------------------------------------------
      if (event.type === "message.updated") {
        const message = (event as any).properties?.message
          || (event as any).message

        if (!message) return

        const jsonContent = extractJSONFromMessage(message)
        const identityText = extractIdentityFromMessage(message)

        // Use IDENTITY VERIFIED text to detect agent FIRST
        if (identityText && !currentAgent) {
          if (identityText === "orchestrator" || identityText === "plankestrator") {
            currentAgent = identityText
            hasOutputtedJSON.set(identityText, false)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected from IDENTITY VERIFIED text: ${identityText}`
              }
            })
          }
        }

        // Use JSON output to detect agent if not yet detected
        if (jsonContent?.agent && !currentAgent) {
          const agentName = String(jsonContent.agent)
          if (agentName === "orchestrator" || agentName === "plankestrator") {
            currentAgent = agentName
            hasOutputtedJSON.set(agentName, false)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected from JSON output: ${agentName}`
              }
            })
          }
        }

        // Correct agent from IDENTITY VERIFIED text if mismatch
        if (identityText && currentAgent && identityText !== currentAgent) {
          const previousAgent = currentAgent
          currentAgent = identityText
          hasOutputtedJSON.set(identityText, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "Agent corrected from IDENTITY VERIFIED text",
              extra: { previousAgent, newAgent: currentAgent }
            }
          })
        }

        // Check for identity drift from JSON
        if (jsonContent?.agent && currentAgent && jsonContent.agent !== currentAgent && !identityText) {
          const previousAgent = currentAgent
          currentAgent = String(jsonContent.agent)
          hasOutputtedJSON.set(currentAgent, false)

          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: "IDENTITY DRIFT DETECTED",
              extra: { previousAgent, newAgent: currentAgent }
            }
          })
        }

        // Validate JSON if we know which agent is running
        if (jsonContent && currentAgent) {
          const validation = validateJSONOutput(jsonContent, currentAgent)

          if (!validation.valid) {
            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: "INVALID JSON OUTPUT",
                extra: {
                  agent: currentAgent,
                  errors: validation.errors,
                  missingFields: validation.missingFields
                }
              }
            })
          } else {
            hasOutputtedJSON.set(currentAgent, true)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: "Valid JSON output detected — Task tool now allowed",
                extra: { agent: currentAgent }
              }
            })
          }
        }
      }
    },

    // ==========================================================
    // "tool.execute.before" — routing table enforcement
    // ==========================================================
    "tool.execute.before": async (input, output) => {
      const timestamp = Date.now()

      const isFirstTaskCall = input.tool === "task" 
        && workflowSteps.filter(s => s.tool === "task").length === 0

      // Reverse routing lookup
      if (!currentAgent && input.tool === "task") {
        const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type
        if (targetAgent) {
          const detected = detectAgentFromSubagent(targetAgent)
          if (detected) {
            currentAgent = detected
            hasOutputtedJSON.set(detected, true)

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "info",
                message: `Agent detected via reverse routing lookup: ${detected} (called ${targetAgent})`
              }
            })

            await client.app.log({
              body: {
                service: "workflow-enforcement",
                level: "warn",
                message: `JSON output will be REQUIRED for all subsequent Task tool calls by ${detected}.`
              }
            })
          }
        }
      }

      const targetForLog = input.tool === "task"
        ? ((output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type)
        : undefined

      workflowSteps.push({
        timestamp,
        tool: input.tool,
        agent: currentAgent || "unknown",
        target: targetForLog
      })

      if (input.tool !== "task") return

      const targetAgent = (output as any)?.args?.subagent_type || (input as any)?.args?.subagent_type

      if (!currentAgent) {
        await client.app.log({
          body: {
            service: "workflow-enforcement",
            level: "warn",
            message: "Current agent not detected, cannot enforce routing table"
          }
        })
        return
      }
      
      // Check: agent must output JSON before calling non-identity-probe agents
      const agentJSONStatus = hasOutputtedJSON.get(currentAgent) ?? false
      if (!agentJSONStatus && targetAgent && !IDENTITY_PROBE_AGENTS.includes(targetAgent) && !isFirstTaskCall) {
        throw new Error(`
⛔ JSON OUTPUT REQUIRED — PLUGIN ENFORCEMENT

You MUST output valid JSON BEFORE calling the Task tool.

Required output order:
1. FIRST: "IDENTITY VERIFIED: I am ${currentAgent}..."
2. SECOND: JSON code block with ALL required fields
3. THIRD: THEN call Task tool

Exception: Identity probe agents may be called before JSON output.

This is enforced by the workflow-enforcement plugin.
        `)
      }

      // Check: target agent must be in routing table
      const allowedAgents = ROUTING_TABLES[currentAgent as keyof typeof ROUTING_TABLES] || []
      if (targetAgent && !allowedAgents.includes(targetAgent)) {
        const otherAgent = currentAgent === "orchestrator" ? "plankestrator" : "orchestrator"
        const otherAllowedAgents = ROUTING_TABLES[otherAgent as keyof typeof ROUTING_TABLES] || []
        
        if (otherAllowedAgents.includes(targetAgent)) {
          const previousAgent = currentAgent
          currentAgent = otherAgent
          hasOutputtedJSON.set(otherAgent, true)
          
          await client.app.log({
            body: {
              service: "workflow-enforcement",
              level: "warn",
              message: `Agent corrected via routing fallback: was ${previousAgent}, now ${otherAgent} (called ${targetAgent})`
            }
          })
        } else {
          throw new Error(`
WORKFLOW VIOLATION - ROUTING TABLE ENFORCEMENT

Current Agent: ${currentAgent}
Attempted Call: ${targetAgent}
Allowed Agents: ${allowedAgents.join(", ")}

This violates the routing table configuration.
Please follow the correct workflow for your agent type.

Orchestrator handles: BUGFIX, DEVOPS, DEV, DOCS
Plankestrator handles: PLAN, RESEARCH, RESEARCH+PLAN
          `)
        }
      }

      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Valid routing: ${currentAgent} → ${targetAgent}`,
          extra: { allowed: true }
        }
      })
    },

    // ==========================================================
    // "tool.execute.after" — log tool completion
    // ==========================================================
    "tool.execute.after": async (input, output) => {
      await client.app.log({
        body: {
          service: "workflow-enforcement",
          level: "info",
          message: `Tool completed: ${input.tool}`,
          extra: {
            agent: currentAgent,
            success: !(output as any)?.error
          }
        }
      })
    }
  }
}

// ============================================================
// Agent Detection Helpers
// ============================================================

function detectAgentFromSessionData(sessionData: any): string | null {
  if (!sessionData) return null

  if (sessionData.title) {
    const title = String(sessionData.title).toLowerCase()
    if (title.includes("orchestrator")) return "orchestrator"
    if (title.includes("plankestrator")) return "plankestrator"
  }

  if (sessionData.agent === "orchestrator" || sessionData.agent === "plankestrator") {
    return sessionData.agent
  }

  return null
}

function detectAgentFromSubagent(subagentName: string): string | null {
  for (const [primaryAgent, whitelist] of Object.entries(ROUTING_TABLES)) {
    if (whitelist.includes(subagentName)) {
      return primaryAgent
    }
  }
  return null
}

// ============================================================
// JSON Parsing & Validation
// ============================================================

function extractIdentityFromMessage(message: any): string | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null

  const identityMatch = content.match(/IDENTITY VERIFIED:\s*I am\s+(orchestrator|plankestrator)/i)
  if (identityMatch) {
    return identityMatch[1].toLowerCase()
  }

  return null
}

function extractJSONFromMessage(message: any): any | null {
  const content = message.content || message.text || ""
  if (typeof content !== "string") return null

  const jsonMatch = content.match(/```json\s*([\s\S]*?)\s*```/)
  if (jsonMatch) {
    try {
      return JSON.parse(jsonMatch[1])
    } catch {
      return null
    }
  }

  const inlineMatch = content.match(/\{[\s\S]*?"agent"[\s\S]*?\}/)
  if (inlineMatch) {
    try {
      return JSON.parse(inlineMatch[0])
    } catch {
      return null
    }
  }

  return null
}

function validateJSONOutput(json: any, agent: string): {valid: boolean, errors: string[], missingFields: string[]} {
  const errors: string[] = []
  const missingFields: string[] = []

  const requiredFields = REQUIRED_JSON_FIELDS[agent] || []
  for (const field of requiredFields) {
    if (!(field in json)) {
      missingFields.push(field)
    }
  }

  const validValues = VALID_VALUES[agent] || {}
  for (const [field, values] of Object.entries(validValues)) {
    if (json[field] !== undefined && !values.includes(json[field])) {
      errors.push(`Invalid value for ${field}: ${json[field]}, expected: ${values.join("|")}`)
    }
  }

  if (json.next_agent !== null && json.next_agent !== undefined) {
    const allowedAgents = ROUTING_TABLES[agent as keyof typeof ROUTING_TABLES] || []
    if (!allowedAgents.includes(json.next_agent)) {
      errors.push(`Invalid next_agent: ${json.next_agent} (not in whitelist)`)
    }
  }

  if (json.pipeline !== undefined && json.pipeline !== null && !Array.isArray(json.pipeline)) {
    errors.push(`Invalid pipeline: ${json.pipeline} (expected: array)`)
  }

  if (json.goal !== undefined && json.goal !== null && typeof json.goal !== "string") {
    errors.push(`Invalid goal: ${json.goal} (expected: string)`)
  }

  if (agent === "orchestrator" && json.plan_exists !== undefined && json.plan_exists !== null) {
    if (typeof json.plan_exists !== "boolean") {
      errors.push(`Invalid plan_exists: ${json.plan_exists} (expected: boolean|null)`)
    }
  }

  if (agent === "orchestrator" && json.plan_source !== undefined && json.plan_source !== null) {
    if (typeof json.plan_source !== "string") {
      errors.push(`Invalid plan_source: ${json.plan_source} (expected: string|null)`)
    }
  }

  if (json.agent && json.agent !== agent) {
    errors.push(`IDENTITY MISMATCH: JSON claims agent=${json.agent}, but current agent is ${agent}`)
  }

  return {
    valid: errors.length === 0 && missingFields.length === 0,
    errors,
    missingFields
  }
}
```

---

## 6. Deployment Instructions

### Step-by-Step Deployment Guide

#### Step 1: Install Prerequisites

```bash
# Install Node.js (if not installed)
# Windows: Download from https://nodejs.org
# Linux/Mac:
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install OpenCode CLI
npm install -g @opencode-ai/cli

# Verify installation
opencode --version
node --version
```

#### Step 2: Create Directory Structure

```bash
# Windows (PowerShell)
mkdir -p $HOME\.config\opencode\plugins
mkdir -p $HOME\.config\opencode\agents
mkdir -p $HOME\.local\share\opencode\storage\session_diff
mkdir -p $HOME\.local\share\opencode\storage\todo
mkdir -p $HOME\.local\share\opencode\tool-output
mkdir -p $HOME\.local\share\opencode\log

# Linux/Mac
mkdir -p ~/.config/opencode/plugins
mkdir -p ~/.config/opencode/agents
mkdir -p ~/.local/share/opencode/storage/session_diff
mkdir -p ~/.local/share/opencode/storage/todo
mkdir -p ~/.local/share/opencode/tool-output
mkdir -p ~/.local/share/opencode/log
```

#### Step 3: Copy Configuration Files

```bash
# Copy opencode.json
cp opencode-config/opencode.json ~/.config/opencode/opencode.json

# Copy plugin
cp plugins/workflow-enforcement.ts ~/.config/opencode/plugins/workflow-enforcement.ts

# Copy all agent files
cp agents/*.md ~/.config/opencode/agents/
```

#### Step 4: Install MCP Servers

```bash
# Install zread MCP server
npm install -g @opencode-ai/mcp-zread

# Install webSearchPrime MCP server
npm install -g @opencode-ai/mcp-websearchprime

# Install webReader MCP server
npm install -g @opencode-ai/mcp-webreader
```

#### Step 5: Install Serena

```bash
# Download Serena
git clone https://github.com/opencode-ai/serena.git
cd serena

# Install dependencies
npm install

# Build
npm run build

# Configure Serena project root
export SERENA_PROJECT_ROOT="/path/to/your/project"
```

#### Step 6: Configure unity-mcp (Optional)

For Unity projects:

1. Install Unity 6 (6000.0) or later
2. Open Unity Package Manager
3. Install `com.unity.ai.assistant` package
4. Download relay binary to `%USERPROFILE%\.unity\relay\relay_win.exe`
5. Start Unity Editor
6. Approve first-time connection in Unity Editor

#### Step 7: Verify Setup

```bash
# Start OpenCode
opencode

# Check plugin initialization
# Look for: "Workflow enforcement plugin initialized"

# Test agent routing
# Start a session with orchestrator
# Verify routing table enforcement works
```

---

## 7. File Locations Reference

### Configuration Files

| File | Location | Purpose |
|------|----------|---------|
| opencode.json | `~/.config/opencode/opencode.json` | Main configuration |
| workflow-enforcement.ts | `~/.config/opencode/plugins/workflow-enforcement.ts` | Workflow plugin |
| orchestrator.md | `~/.config/opencode/agents/orchestrator.md` | Primary agent |
| plankestrator.md | `~/.config/opencode/agents/plankestrator.md` | Primary agent |
| [subagent].md | `~/.config/opencode/agents/[name].md` | Subagent definitions |

### Data Storage

| Directory | Location | Purpose |
|-----------|----------|---------|
| Database | `~/.local/share/opencode/opencode.db` | SQLite database |
| Session Storage | `~/.local/share/opencode/storage/session_diff/` | Session state |
| Todo Lists | `~/.local/share/opencode/storage/todo/` | Task tracking |
| Tool Outputs | `~/.local/share/opencode/tool-output/` | Tool results |
| Logs | `~/.local/share/opencode/log/` | Execution logs |

### Documentation

| File | Location | Purpose |
|------|----------|---------|
| AGENTS.md | Project root | Project rules |
| ARCHITECTURE.md | Project root | Architecture requirements |
| PLUGIN.md | Project root | Plugin documentation |
| MCP_SETUP.md | Project root | Setup guide |

---

## 8. Troubleshooting

### Common Issues

#### Issue 1: Plugin Not Loading

**Symptoms:**
- No "Workflow enforcement plugin initialized" log
- Routing violations not blocked

**Solution:**
```bash
# Check plugin path in opencode.json
cat ~/.config/opencode/opencode.json | grep plugins

# Verify plugin file exists
ls ~/.config/opencode/plugins/workflow-enforcement.ts

# Check plugin syntax
node -c ~/.config/opencode/plugins/workflow-enforcement.ts
```

#### Issue 2: MCP Server Not Connecting

**Symptoms:**
- MCP tools not available
- "MCP server not found" errors

**Solution:**
```bash
# Check MCP configuration
cat ~/.config/opencode/opencode.json | grep mcp

# Verify MCP server path
ls path/to/mcp-server.js

# Test MCP server manually
node path/to/mcp-server.js
```

#### Issue 3: Agent Identity Drift

**Symptoms:**
- "IDENTITY DRIFT DETECTED" warnings
- Agent calling wrong subagents

**Solution:**
- Check agent file frontmatter matches opencode.json
- Verify agent description contains correct name
- Ensure identity verification output is correct format

#### Issue 4: Routing Violation

**Symptoms:**
- "WORKFLOW VIOLATION" errors
- Task tool calls blocked

**Solution:**
- Check routing table in plugin matches opencode.json whitelist
- Verify agent is calling correct subagent for its type
- Ensure JSON output includes correct `"agent"` field

#### Issue 5: JSON Validation Failure

**Symptoms:**
- "INVALID JSON OUTPUT" warnings
- Missing fields errors

**Solution:**
- Check JSON includes all required fields
- Verify field values are valid (see validation rules)
- Ensure `"agent"` field matches current agent

### Debug Commands

```bash
# View recent logs
tail -100 ~/.local/share/opencode/log/opencode.log

# Search for violations
grep "WORKFLOW VIOLATION" ~/.local/share/opencode/log/*.log

# Search for drift
grep "IDENTITY DRIFT" ~/.local/share/opencode/log/*.log

# Search for JSON errors
grep "INVALID JSON" ~/.local/share/opencode/log/*.log

# View all plugin activity
grep "workflow-enforcement" ~/.local/share/opencode/log/*.log
```

---

## 9. Verification Checklist

### Pre-Deployment Checklist

- [ ] Node.js 18+ installed
- [ ] OpenCode CLI installed
- [ ] Directory structure created
- [ ] MCP servers installed (zread, webSearchPrime, webReader)
- [ ] Serena installed (if using code symbol operations)
- [ ] unity-mcp configured (if Unity project)

### Configuration Checklist

- [ ] opencode.json copied to `~/.config/opencode/`
- [ ] Plugin copied to `~/.config/opencode/plugins/`
- [ ] All 31 agent files copied to `~/.config/opencode/agents/`
- [ ] MCP server paths correct in opencode.json
- [ ] Agent whitelists match routing tables

### Post-Deployment Checklist

- [ ] OpenCode starts without errors
- [ ] Plugin initialization log appears
- [ ] MCP tools available (zread_*, webSearchPrime_*, webReader_*)
- [ ] orchestrator session works
- [ ] plankestrator session works
- [ ] Routing violations blocked correctly
- [ ] JSON validation works
- [ ] Identity drift detection works

### Test Commands

```bash
# Test orchestrator
opencode --agent orchestrator
# Should see: "Workflow enforcement plugin initialized"
# Should see: "Session created — agent detected: orchestrator"

# Test plankestrator
opencode --agent plankestrator
# Should see: "Session created — agent detected: plankestrator"

# Test routing violation (should be blocked)
# In orchestrator session, try calling plan-writer-simple
# Should see: "WORKFLOW VIOLATION" error

# Test MCP tools
# In any session, use zread_search_doc
# Should return GitHub search results
```

---

## Summary

| Component | Count | Location |
|-----------|-------|----------|
| Primary agents | 2 | `~/.config/opencode/agents/` |
| Subagents | 29 | `~/.config/opencode/agents/` |
| MCP servers | 5 | Configured in opencode.json |
| Plugin hooks | 3 | workflow-enforcement.ts |
| Routing tables | 2 | orchestrator (20), plankestrator (9) |
| Pipelines | 7 | BUGFIX, DEV, DEVOPS, DOCS, PLAN, RESEARCH |

### Quick Reference

| Task | Command |
|------|---------|
| Start orchestrator | `opencode --agent orchestrator` |
| Start plankestrator | `opencode --agent plankestrator` |
| View logs | `tail ~/.local/share/opencode/log/*.log` |
| Check config | `cat ~/.config/opencode/opencode.json` |
| List agents | `ls ~/.config/opencode/agents/` |

---

**Document Version:** 1.0
**Last Updated:** 2026-05-09
**Author:** OpenCode Documentation Team