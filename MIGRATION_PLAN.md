# OpenCode Full Architecture Migration Plan

**Version:** 1.0  
**Date:** 2026-06-02  
**Purpose:** Complete transfer of the OpenCode dual-primary-agent orchestration system to another computer

---

## Table of Contents

1. [Overview](#1-overview)
2. [Complete File and Directory Inventory](#2-complete-file-and-directory-inventory)
3. [Migration Folder Structure](#3-migration-folder-structure)
4. [Pre-Migration Checklist](#4-pre-migration-checklist)
5. [Step-by-Step: Source Computer — Export](#5-step-by-step-source-computer--export)
6. [Step-by-Step: Target Computer — Deployment](#6-step-by-step-target-computer--deployment)
7. [Post-Migration Verification Checklist](#7-post-migration-verification-checklist)
8. [Potential Issues and Troubleshooting](#8-potential-issues-and-troubleshooting)
9. [Backup Recommendations](#9-backup-recommendations)

---

## 1. Overview

### System Architecture Summary

| Component | Count | Description |
|-----------|-------|-------------|
| Primary agents | 2 | orchestrator, plankestrator |
| Subagents | 31 | All specialized worker agents |
| MCP servers | 6 | zread, webSearchPrime, webReader, serena, unity-mcp, zai-mcp-server |
| Plugin hooks | 3 | event, tool.execute.before, tool.execute.after |
| Routing tables | 2 | orchestrator (21 agents), plankestrator (10 agents) |
| Pipelines | 12 | BUGFIX, DEV, DEVOPS, DOCS, PLAN, RESEARCH variants |
| Custom commands | 5 | read-url, document, github, summarize, search |
| Models/Providers | 5 | alibaba, zai-coding, kimi-for-coding, minimax-coding-plan |

### Migration Strategy

```
SOURCE COMPUTER                              TARGET COMPUTER
┌──────────────────────┐                     ┌──────────────────────┐
│ OpenCode running     │  ── Export to ──►   │ Migration folder     │
│ with full config     │     USB/Cloud/       │ received            │
│                      │     Network          │                      │
│ Export all files     │                     │ Deploy script        │
│ to migration folder  │                     │ restores everything  │
└──────────────────────┘                     └──────────────────────┘
```

---

## 2. Complete File and Directory Inventory

### 2.1 Global Configuration (`~/.config/opencode/`)

These files define the OpenCode system itself and are machine-specific.

| # | Path (Windows) | Type | Required | Description |
|---|----------------|------|----------|-------------|
| 1 | `%USERPROFILE%\.config\opencode\opencode.json` | File | **CRITICAL** | Main configuration: providers, MCP servers, agents, commands, permissions |
| 2 | `%USERPROFILE%\.config\opencode\opencode.jsonc` | File | If exists | JSONC variant of config (if used instead of .json) |
| 3 | `%USERPROFILE%\.config\opencode\plugins\workflow-enforcement.ts` | File | **CRITICAL** | Workflow enforcement plugin (routing tables, JSON validation, pipeline enforcement) |
| 4 | `%USERPROFILE%\.config\opencode\agents\orchestrator.md` | File | **CRITICAL** | Primary agent — operational tasks |
| 5 | `%USERPROFILE%\.config\opencode\agents\plankestrator.md` | File | **CRITICAL** | Primary agent — planning/research |
| 6 | `%USERPROFILE%\.config\opencode\agents\orchestrator-identity-probe.md` | File | Required | Identity verification for orchestrator |
| 7 | `%USERPROFILE%\.config\opencode\agents\plankestrator-identity-probe.md` | File | Required | Identity verification for plankestrator |
| 8 | `%USERPROFILE%\.config\opencode\agents\worker.md` | File | **CRITICAL** | Implementation agent (bash: allow) |
| 9 | `%USERPROFILE%\.config\opencode\agents\bugfix.md` | File | Required | Bug fixing agent |
| 10 | `%USERPROFILE%\.config\opencode\agents\bugfix-triage.md` | File | Required | Bug triage agent |
| 11 | `%USERPROFILE%\.config\opencode\agents\plan-bug.md` | File | Required | Bug fix planning agent |
| 12 | `%USERPROFILE%\.config\opencode\agents\execute-bug.md` | File | Required | Bug fix execution agent |
| 13 | `%USERPROFILE%\.config\opencode\agents\dev-planner.md` | File | Required | Development planning agent |
| 14 | `%USERPROFILE%\.config\opencode\agents\dev-professor.md` | File | Required | Development guidance agent |
| 15 | `%USERPROFILE%\.config\opencode\agents\dev-reviewer.md` | File | Required | Code review agent |
| 16 | `%USERPROFILE%\.config\opencode\agents\rework.md` | File | Required | Rework agent |
| 17 | `%USERPROFILE%\.config\opencode\agents\consistency-checker.md` | File | **CRITICAL** | Architecture consistency validation |
| 18 | `%USERPROFILE%\.config\opencode\agents\docs-writer.md` | File | Required | Documentation writing agent |
| 19 | `%USERPROFILE%\.config\opencode\agents\utility.md` | File | Required | Validation agent |
| 20 | `%USERPROFILE%\.config\opencode\agents\mcp-github.md` | File | Required | GitHub operations agent |
| 21 | `%USERPROFILE%\.config\opencode\agents\mcp-read.md` | File | Required | File reading agent |
| 22 | `%USERPROFILE%\.config\opencode\agents\mcp-search.md` | File | Required | Web search agent |
| 23 | `%USERPROFILE%\.config\opencode\agents\summarizer.md` | File | Required | Summarization agent |
| 24 | `%USERPROFILE%\.config\opencode\agents\devops.md` | File | Required | Legacy DevOps agent |
| 25 | `%USERPROFILE%\.config\opencode\agents\devops-agent.md` | File | Required | DevOps operations agent |
| 26 | `%USERPROFILE%\.config\opencode\agents\devops-reviewer.md` | File | Required | DevOps review agent |
| 27 | `%USERPROFILE%\.config\opencode\agents\devops-readonly.md` | File | Required | DevOps read-only agent |
| 28 | `%USERPROFILE%\.config\opencode\agents\plan-writer-simple.md` | File | Required | Simple planning agent |
| 29 | `%USERPROFILE%\.config\opencode\agents\plan-writer-complex.md` | File | Required | Complex planning agent |
| 30 | `%USERPROFILE%\.config\opencode\agents\plan-reviewer-simple.md` | File | Required | Simple plan review agent |
| 31 | `%USERPROFILE%\.config\opencode\agents\plan-reviewer-complex.md` | File | Required | Complex plan review agent |
| 32 | `%USERPROFILE%\.config\opencode\agents\research-writer-simple.md` | File | Required | Simple research agent |
| 33 | `%USERPROFILE%\.config\opencode\agents\research-writer-complex.md` | File | Required | Complex research agent |
| 34 | `%USERPROFILE%\.config\opencode\agents\research-reviewer.md` | File | Required | Research review agent |
| 35 | `%USERPROFILE%\.config\opencode\agents\view-image.md` | File | Required | Image analysis agent |

**Agent file count: 34 files** (33 unique agents + possibly view-image)

### 2.2 Data Storage (`~/.local/share/opencode/`)

These contain session history, database, and logs.

| # | Path (Windows) | Type | Required | Description |
|---|----------------|------|----------|-------------|
| 36 | `%USERPROFILE%\.local\share\opencode\opencode.db` | File | **MIGRATE** | SQLite database (sessions, messages) |
| 37 | `%USERPROFILE%\.local\share\opencode\storage\session_diff\` | Dir | Optional | Session state differences (JSON) |
| 38 | `%USERPROFILE%\.local\share\opencode\storage\todo\` | Dir | Optional | Todo lists (JSON) |
| 39 | `%USERPROFILE%\.local\share\opencode\tool-output\` | Dir | Optional | Tool execution results |
| 40 | `%USERPROFILE%\.local\share\opencode\log\` | Dir | Optional | Execution logs (.log files) |

### 2.3 Project-Level Files (in project root)

These files live in the git repository and define project-specific rules.

| # | Path | Type | Required | Description |
|---|------|------|----------|-------------|
| 41 | `AGENTS.md` | File | **CRITICAL** | Project rules loaded as instructions for all agents |
| 42 | `ARCHITECTURE.md` | File | **CRITICAL** | Single source of truth for architecture requirements |
| 43 | `PLUGIN.md` | File | **CRITICAL** | Workflow enforcement plugin documentation |
| 44 | `MCP_SETUP.md` | File | **CRITICAL** | Full setup guide for deployment |
| 45 | `.opencode\package.json` | File | Required | Plugin dependency (`@opencode-ai/plugin`) |
| 46 | `.opencode\package-lock.json` | File | Required | Locked dependencies |
| 47 | `plugins\workflow-enforcement.ts` | File | **CRITICAL** | Plugin source (project-local copy) |
| 48 | `.serena\project.yml` | File | Required | Serena project configuration |
| 49 | `.serena\project.local.yml` | File | If exists | Local Serena overrides |
| 50 | `.serena\.gitignore` | File | Required | Serena cache exclusions |
| 51 | `.serena\cache\` | Dir | Optional | Serena LSP cache (can be regenerated) |
| 52 | `.opencode\.gitignore` | File | Required | OpenCode node_modules exclusion |

### 2.4 opencode-config Directory (Reference Copies)

These are reference/template copies of configuration files stored in the project repo.

| # | Path | Type | Required | Description |
|---|------|------|----------|-------------|
| 53 | `opencode-config\AGENTS.md` | File | Optional | Reference copy of project AGENTS.md |
| 54 | `opencode-config\ARCHITECTURE.md` | File | Optional | Reference copy of ARCHITECTURE.md |
| 55 | `opencode-config\PLUGIN.md` | File | Optional | Reference copy of PLUGIN.md |

### 2.5 Agent Definitions (Project-Local Copies)

Agent .md files stored in the project repo (can differ from global `~/.config/opencode/agents/`).

| # | Path | Type | Required | Description |
|---|------|------|----------|-------------|
| 56-64 | `agents\*.md` (9 files) | Files | Optional | Plankestrator-related agent definitions |

### 2.6 External Tool Configurations

| # | Path | Type | Required | Description |
|---|------|------|----------|-------------|
| 65 | `%USERPROFILE%\.local\bin\serena.exe` | Binary | **CRITICAL** | Serena MCP server executable |

---

## 3. Migration Folder Structure

The migration folder organizes all files for easy transfer and deployment.

```
opencode-migration/
│
├── README.txt                          ← This migration plan + quick instructions
├── MIGRATION_PLAN.md                   ← Full migration plan (this file)
│
├── 01-global-config/                   ← Files for ~/.config/opencode/
│   ├── opencode.json                   ← Main configuration
│   ├── opencode.jsonc                  ← (if exists) JSONC variant
│   ├── plugins/
│   │   └── workflow-enforcement.ts     ← Workflow enforcement plugin
│   └── agents/
│       ├── orchestrator.md
│       ├── plankestrator.md
│       ├── orchestrator-identity-probe.md
│       ├── plankestrator-identity-probe.md
│       ├── worker.md
│       ├── bugfix.md
│       ├── bugfix-triage.md
│       ├── plan-bug.md
│       ├── execute-bug.md
│       ├── dev-planner.md
│       ├── dev-professor.md
│       ├── dev-reviewer.md
│       ├── rework.md
│       ├── consistency-checker.md
│       ├── docs-writer.md
│       ├── utility.md
│       ├── mcp-github.md
│       ├── mcp-read.md
│       ├── mcp-search.md
│       ├── summarizer.md
│       ├── devops.md
│       ├── devops-agent.md
│       ├── devops-reviewer.md
│       ├── devops-readonly.md
│       ├── plan-writer-simple.md
│       ├── plan-writer-complex.md
│       ├── plan-reviewer-simple.md
│       ├── plan-reviewer-complex.md
│       ├── research-writer-simple.md
│       ├── research-writer-complex.md
│       ├── research-reviewer.md
│       └── view-image.md
│
├── 02-data/                            ← Files for ~/.local/share/opencode/
│   ├── opencode.db                     ← SQLite database
│   ├── storage/
│   │   ├── session_diff/               ← Session differences (JSON)
│   │   └── todo/                       ← Todo lists (JSON)
│   ├── tool-output/                    ← Tool execution results
│   └── log/                            ← Execution logs
│
├── 03-project-files/                   ← Files for project root (git repo)
│   ├── AGENTS.md
│   ├── ARCHITECTURE.md
│   ├── PLUGIN.md
│   ├── MCP_SETUP.md
│   ├── MIGRATION_PLAN.md
│   ├── plugins/
│   │   └── workflow-enforcement.ts
│   ├── agents/                         ← Project-local agent copies
│   │   ├── plankestrator.md
│   │   ├── plan-writer-simple.md
│   │   ├── plan-writer-complex.md
│   │   ├── plan-reviewer-simple.md
│   │   ├── plan-reviewer-complex.md
│   │   ├── research-writer-simple.md
│   │   ├── research-writer-complex.md
│   │   ├── research-reviewer.md
│   │   └── devops-readonly.md
│   ├── opencode-config/
│   │   ├── AGENTS.md
│   │   ├── ARCHITECTURE.md
│   │   └── PLUGIN.md
│   ├── .opencode/
│   │   ├── package.json
│   │   ├── package-lock.json
│   │   └── .gitignore
│   └── .serena/
│       ├── project.yml
│       ├── project.local.yml
│       └── .gitignore
│
├── 04-tools/                           ← External tools
│   └── serena.exe                      ← Serena binary (if portable)
│
└── deploy.ps1                          ← Automated deployment script
```

---

## 4. Pre-Migration Checklist

### 4.1 Source Computer — Before Export

#### Verify OpenCode is Working

- [ ] OpenCode starts without errors: `opencode --version`
- [ ] orchestrator session works: `opencode --agent orchestrator`
- [ ] plankestrator session works: `opencode --agent plankestrator`
- [ ] Plugin loads correctly (check for "Workflow enforcement plugin initialized" in logs)
- [ ] MCP servers are accessible (zread, webSearchPrime, webReader, serena)
- [ ] unity-mcp works (if Unity project — only when Unity Editor is running)

#### Verify File Integrity

- [ ] `~/.config/opencode/opencode.json` exists and is valid JSON
- [ ] `~/.config/opencode/plugins/workflow-enforcement.ts` exists
- [ ] All 34 agent `.md` files exist in `~/.config/opencode/agents/`
- [ ] `~/.local/share/opencode/opencode.db` exists (check file size > 0)
- [ ] Project files exist: `AGENTS.md`, `ARCHITECTURE.md`, `PLUGIN.md`, `MCP_SETUP.md`

#### Verify API Keys Are Known

- [ ] Alibaba/bailian-token-plan API key is available (starts with `sk-sp-`)
- [ ] Z.AI API key is available
- [ ] Note: API keys will need to be manually entered on target computer

#### Check Target Computer Compatibility

- [ ] Target OS is Windows (or adjust paths for Linux/macOS)
- [ ] Node.js 18+ can be installed on target
- [ ] Python 3.10+ can be installed on target (for Serena)
- [ ] Target has internet access (for npm, npx, API calls)
- [ ] Transfer medium identified (USB drive, cloud storage, network share)

---

## 5. Step-by-Step: Source Computer — Export

### Phase 1: Create Migration Folder Structure

```powershell
# Create migration root
$migrationRoot = "C:\opencode-migration"
New-Item -ItemType Directory -Force -Path $migrationRoot

# Create subdirectories
New-Item -ItemType Directory -Force -Path "$migrationRoot\01-global-config\plugins"
New-Item -ItemType Directory -Force -Path "$migrationRoot\01-global-config\agents"
New-Item -ItemType Directory -Force -Path "$migrationRoot\02-data\storage\session_diff"
New-Item -ItemType Directory -Force -Path "$migrationRoot\02-data\storage\todo"
New-Item -ItemType Directory -Force -Path "$migrationRoot\02-data\tool-output"
New-Item -ItemType Directory -Force -Path "$migrationRoot\02-data\log"
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-project-files\plugins"
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-project-files\agents"
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-project-files\opencode-config"
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-project-files\.opencode"
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-project-files\.serena"
New-Item -ItemType Directory -Force -Path "$migrationRoot\04-tools"
```

### Phase 2: Export Global Configuration

```powershell
$migrationRoot = "C:\opencode-migration"
$configSrc = "$env:USERPROFILE\.config\opencode"

# Copy main configuration
Copy-Item "$configSrc\opencode.json" "$migrationRoot\01-global-config\" -ErrorAction SilentlyContinue
Copy-Item "$configSrc\opencode.jsonc" "$migrationRoot\01-global-config\" -ErrorAction SilentlyContinue

# Copy plugin
Copy-Item "$configSrc\plugins\workflow-enforcement.ts" "$migrationRoot\01-global-config\plugins\"

# Copy all agent files
Copy-Item "$configSrc\agents\*.md" "$migrationRoot\01-global-config\agents\"

# Verify agent count
$agentCount = (Get-ChildItem "$migrationRoot\01-global-config\agents\*.md").Count
Write-Host "Agent files copied: $agentCount (expected: 34)"
```

### Phase 3: Export Data Storage

```powershell
$migrationRoot = "C:\opencode-migration"
$dataSrc = "$env:USERPROFILE\.local\share\opencode"

# Copy database
Copy-Item "$dataSrc\opencode.db" "$migrationRoot\02-data\"

# Copy session storage (if exists)
if (Test-Path "$dataSrc\storage\session_diff") {
    Copy-Item "$dataSrc\storage\session_diff\*" "$migrationRoot\02-data\storage\session_diff\" -Recurse -ErrorAction SilentlyContinue
}
if (Test-Path "$dataSrc\storage\todo") {
    Copy-Item "$dataSrc\storage\todo\*" "$migrationRoot\02-data\storage\todo\" -Recurse -ErrorAction SilentlyContinue
}

# Copy tool outputs (if exists)
if (Test-Path "$dataSrc\tool-output") {
    Copy-Item "$dataSrc\tool-output\*" "$migrationRoot\02-data\tool-output\" -Recurse -ErrorAction SilentlyContinue
}

# Copy logs (if exists)
if (Test-Path "$dataSrc\log") {
    Copy-Item "$dataSrc\log\*" "$migrationRoot\02-data\log\" -Recurse -ErrorAction SilentlyContinue
}
```

### Phase 4: Export Project Files

```powershell
$migrationRoot = "C:\opencode-migration"
$projectRoot = "P:\Programming\Рефакторинг"

# Copy project root documentation files
Copy-Item "$projectRoot\AGENTS.md" "$migrationRoot\03-project-files\"
Copy-Item "$projectRoot\ARCHITECTURE.md" "$migrationRoot\03-project-files\"
Copy-Item "$projectRoot\PLUGIN.md" "$migrationRoot\03-project-files\"
Copy-Item "$projectRoot\MCP_SETUP.md" "$migrationRoot\03-project-files\"

# Copy project-local plugins
Copy-Item "$projectRoot\plugins\workflow-enforcement.ts" "$migrationRoot\03-project-files\plugins\"

# Copy project-local agent definitions
if (Test-Path "$projectRoot\agents") {
    Copy-Item "$projectRoot\agents\*.md" "$migrationRoot\03-project-files\agents\" -ErrorAction SilentlyContinue
}

# Copy opencode-config directory
if (Test-Path "$projectRoot\opencode-config") {
    Copy-Item "$projectRoot\opencode-config\*" "$migrationRoot\03-project-files\opencode-config\" -Recurse
}

# Copy .opencode directory (package files only, NOT node_modules)
Copy-Item "$projectRoot\.opencode\package.json" "$migrationRoot\03-project-files\.opencode\"
Copy-Item "$projectRoot\.opencode\package-lock.json" "$migrationRoot\03-project-files\.opencode\"
Copy-Item "$projectRoot\.opencode\.gitignore" "$migrationRoot\03-project-files\.opencode\" -ErrorAction SilentlyContinue

# Copy .serena directory
Copy-Item "$projectRoot\.serena\project.yml" "$migrationRoot\03-project-files\.serena\"
Copy-Item "$projectRoot\.serena\project.local.yml" "$migrationRoot\03-project-files\.serena\" -ErrorAction SilentlyContinue
Copy-Item "$projectRoot\.serena\.gitignore" "$migrationRoot\03-project-files\.serena\" -ErrorAction SilentlyContinue
```

### Phase 5: Export Serena Binary

```powershell
$migrationRoot = "C:\opencode-migration"

# Copy Serena executable
Copy-Item "$env:USERPROFILE\.local\bin\serena.exe" "$migrationRoot\04-tools\" -ErrorAction SilentlyContinue

if (-not (Test-Path "$migrationRoot\04-tools\serena.exe")) {
    Write-Host "WARNING: serena.exe not found at expected path. You may need to download it separately." -ForegroundColor Yellow
    Write-Host "Download from: https://github.com/oraios/serena/releases" -ForegroundColor Yellow
}
```

### Phase 6: Create Deployment Script

Create `deploy.ps1` in the migration root (see Section 6 for full script content).

### Phase 7: Create README.txt

```powershell
$migrationRoot = "C:\opencode-migration"
@"
OpenCode Migration Package
==========================
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $env:COMPUTERNAME

QUICK START:
1. Ensure Node.js 18+, Python 3.10+, and Git are installed
2. Install OpenCode CLI: npm install -g opencode
3. Copy serena.exe from 04-tools/ to %USERPROFILE%\.local\bin\
4. Run deploy.ps1 as Administrator
5. Enter API keys when prompted
6. Run 'opencode --agent orchestrator' to verify

CONTENTS:
- 01-global-config/  → Copy to ~/.config/opencode/
- 02-data/           → Copy to ~/.local/share/opencode/
- 03-project-files/  → Copy to project root (git repo)
- 04-tools/          → External tools (serena.exe)
- deploy.ps1         → Automated deployment script
- MIGRATION_PLAN.md  → Full documentation

API KEYS NEEDED:
- Alibaba/bailian-token-plan (sk-sp-*)
- Z.AI API key

See MIGRATION_PLAN.md for detailed instructions.
"@ | Out-File -FilePath "$migrationRoot\README.txt" -Encoding UTF8
```

### Phase 8: Final Verification Before Transfer

```powershell
$migrationRoot = "C:\opencode-migration"

# Verify critical files exist
$criticalFiles = @(
    "$migrationRoot\01-global-config\opencode.json",
    "$migrationRoot\01-global-config\plugins\workflow-enforcement.ts",
    "$migrationRoot\03-project-files\AGENTS.md",
    "$migrationRoot\03-project-files\ARCHITECTURE.md"
)

Write-Host "`n=== Critical Files Check ===" -ForegroundColor Cyan
foreach ($file in $criticalFiles) {
    $exists = Test-Path $file
    $status = if ($exists) { "OK" } else { "MISSING!" }
    $color = if ($exists) { "Green" } else { "Red" }
    Write-Host "  $status - $file" -ForegroundColor $color
}

# Verify agent count
$agentCount = (Get-ChildItem "$migrationRoot\01-global-config\agents\*.md").Count
Write-Host "`n  Agent files: $agentCount (expected: 34)" -ForegroundColor $(if ($agentCount -eq 34) { "Green" } else { "Yellow" })

# Verify database
$dbExists = Test-Path "$migrationRoot\02-data\opencode.db"
$dbSize = if ($dbExists) { (Get-Item "$migrationRoot\02-data\opencode.db").Length } else { 0 }
Write-Host "  Database: $(if ($dbExists) { "$dbSize bytes" } else { "MISSING" })" -ForegroundColor $(if ($dbExists) { "Green" } else { "Red" })

# Total size
$totalSize = (Get-ChildItem $migrationRoot -Recurse | Measure-Object -Property Length -Sum).Sum
Write-Host "`n  Total migration size: $([math]::Round($totalSize / 1MB, 2)) MB" -ForegroundColor Cyan
```

---

## 6. Step-by-Step: Target Computer — Deployment

### Phase 1: Install Prerequisites

```powershell
# 1. Install Node.js 18+ (download from https://nodejs.org or use winget)
winget install OpenJS.NodeJS.LTS

# 2. Install Python 3.10+ (download from https://python.org or use winget)
winget install Python.Python.3.12

# 3. Install Git
winget install Git.Git

# 4. Verify installations
node --version     # Should be v18+ 
python --version   # Should be 3.10+
git --version      # Should be 2.x
```

### Phase 2: Install OpenCode CLI

```powershell
npm install -g opencode

# Verify
opencode --version
```

### Phase 3: Deploy Serena

```powershell
# Create bin directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin"

# Copy serena.exe from migration package
Copy-Item "C:\opencode-migration\04-tools\serena.exe" "$env:USERPROFILE\.local\bin\"

# Add to PATH (if not already)
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$env:USERPROFILE\.local\bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$env:USERPROFILE\.local\bin", "User")
    $env:Path = "$env:Path;$env:USERPROFILE\.local\bin"
}

# Verify
serena --version
```

### Phase 4: Deploy Global Configuration

```powershell
$migrationRoot = "C:\opencode-migration"
$configDest = "$env:USERPROFILE\.config\opencode"

# Create directory structure
New-Item -ItemType Directory -Force -Path "$configDest\plugins"
New-Item -ItemType Directory -Force -Path "$configDest\agents"

# Copy main config
Copy-Item "$migrationRoot\01-global-config\opencode.json" "$configDest\"
Copy-Item "$migrationRoot\01-global-config\opencode.jsonc" "$configDest\" -ErrorAction SilentlyContinue

# Copy plugin
Copy-Item "$migrationRoot\01-global-config\plugins\workflow-enforcement.ts" "$configDest\plugins\"

# Copy all agent files
Copy-Item "$migrationRoot\01-global-config\agents\*.md" "$configDest\agents\"

# Verify agent count
$agentCount = (Get-ChildItem "$configDest\agents\*.md").Count
Write-Host "Agents deployed: $agentCount (expected: 34)"
```

### Phase 5: Configure API Keys

API keys are embedded in `opencode.json`. Edit the file to replace placeholders:

```powershell
# Open opencode.json for editing
notepad "$configDest\opencode.json"
```

**Keys to update:**

| Location in opencode.json | Field | Replace With |
|--------------------------|-------|-------------|
| `provider.bailian-token-plan.options.apiKey` | `"sk-sp-..."` | Your Alibaba API key |
| `provider.zai-coding-plan.options.apiKey` | `"..."` | Your Z.AI API key |
| `mcp.zread.headers.Authorization` | `"Bearer ..."` | `"Bearer YOUR_Z_AI_KEY"` |
| `mcp.webSearchPrime.headers.Authorization` | `"Bearer ..."` | `"Bearer YOUR_Z_AI_KEY"` |
| `mcp.webReader.headers.Authorization` | `"Bearer ..."` | `"Bearer YOUR_Z_AI_KEY"` |
| `mcp.zai-mcp-server.environment.Z_AI_API_KEY` | `"..."` | Your Z.AI API key |

### Phase 6: Fix Machine-Specific Paths

Some paths in `opencode.json` are machine-specific and must be updated:

```powershell
# Check serena path in opencode.json
# The serena command in mcp.serena must point to the correct serena.exe location
# Current: "C:\\Users\\Admin\\.local\\bin\\serena.exe"
# Update to: "C:\\Users\\YOUR_USERNAME\\.local\\bin\\serena.exe"

# Example fix:
$config = Get-Content "$configDest\opencode.json" -Raw
$config = $config -replace 'C:\\\\Users\\\\Admin', "C:\\\\Users\\\\$env:USERNAME"
$config | Set-Content "$configDest\opencode.json" -Encoding UTF8
```

### Phase 7: Deploy Data Storage

```powershell
$migrationRoot = "C:\opencode-migration"
$dataDest = "$env:USERPROFILE\.local\share\opencode"

# Create directory structure
New-Item -ItemType Directory -Force -Path "$dataDest\storage\session_diff"
New-Item -ItemType Directory -Force -Path "$dataDest\storage\todo"
New-Item -ItemType Directory -Force -Path "$dataDest\tool-output"
New-Item -ItemType Directory -Force -Path "$dataDest\log"

# Copy database (STOP OpenCode first!)
Copy-Item "$migrationRoot\02-data\opencode.db" "$dataDest\" -ErrorAction SilentlyContinue

# Copy session data
Copy-Item "$migrationRoot\02-data\storage\session_diff\*" "$dataDest\storage\session_diff\" -Recurse -ErrorAction SilentlyContinue
Copy-Item "$migrationRoot\02-data\storage\todo\*" "$dataDest\storage\todo\" -Recurse -ErrorAction SilentlyContinue

# Copy tool outputs
Copy-Item "$migrationRoot\02-data\tool-output\*" "$dataDest\tool-output\" -Recurse -ErrorAction SilentlyContinue

# Copy logs
Copy-Item "$migrationRoot\02-data\log\*" "$dataDest\log\" -Recurse -ErrorAction SilentlyContinue
```

### Phase 8: Deploy Project Files

```powershell
$migrationRoot = "C:\opencode-migration"

# IMPORTANT: Project files go into the git repository root
# If repo doesn't exist yet, clone it first:
# git clone <repo-url> P:\Programming\Рефакторинг

$projectDest = "P:\Programming\Рефакторинг"  # Adjust to your path

# Copy documentation files
Copy-Item "$migrationRoot\03-project-files\AGENTS.md" "$projectDest\"
Copy-Item "$migrationRoot\03-project-files\ARCHITECTURE.md" "$projectDest\"
Copy-Item "$migrationRoot\03-project-files\PLUGIN.md" "$projectDest\"
Copy-Item "$migrationRoot\03-project-files\MCP_SETUP.md" "$projectDest\"

# Copy plugins
New-Item -ItemType Directory -Force -Path "$projectDest\plugins"
Copy-Item "$migrationRoot\03-project-files\plugins\*" "$projectDest\plugins\" -Recurse

# Copy project-local agent definitions
if (Test-Path "$migrationRoot\03-project-files\agents") {
    New-Item -ItemType Directory -Force -Path "$projectDest\agents"
    Copy-Item "$migrationRoot\03-project-files\agents\*" "$projectDest\agents\" -Recurse
}

# Copy opencode-config
if (Test-Path "$migrationRoot\03-project-files\opencode-config") {
    New-Item -ItemType Directory -Force -Path "$projectDest\opencode-config"
    Copy-Item "$migrationRoot\03-project-files\opencode-config\*" "$projectDest\opencode-config\" -Recurse
}

# Copy .opencode (package files)
New-Item -ItemType Directory -Force -Path "$projectDest\.opencode"
Copy-Item "$migrationRoot\03-project-files\.opencode\package.json" "$projectDest\.opencode\"
Copy-Item "$migrationRoot\03-project-files\.opencode\package-lock.json" "$projectDest\.opencode\"
Copy-Item "$migrationRoot\03-project-files\.opencode\.gitignore" "$projectDest\.opencode\" -ErrorAction SilentlyContinue

# Copy .serena config
New-Item -ItemType Directory -Force -Path "$projectDest\.serena"
Copy-Item "$migrationRoot\03-project-files\.serena\project.yml" "$projectDest\.serena\"
Copy-Item "$migrationRoot\03-project-files\.serena\project.local.yml" "$projectDest\.serena\" -ErrorAction SilentlyContinue
Copy-Item "$migrationRoot\03-project-files\.serena\.gitignore" "$projectDest\.serena\" -ErrorAction SilentlyContinue
```

### Phase 9: Install Plugin Dependencies

```powershell
# Navigate to .opencode directory and install dependencies
Set-Location "$projectDest\.opencode"
npm install

# This installs @opencode-ai/plugin which the workflow-enforcement.ts needs
```

### Phase 10: Automated Deployment Script (deploy.ps1)

The following script automates Phases 3-9. Save as `deploy.ps1` in the migration root:

```powershell
# deploy.ps1 — OpenCode Migration Deployment Script
# Run on target computer after copying migration folder

param(
    [string]$MigrationRoot = "C:\opencode-migration",
    [string]$ProjectDest = "P:\Programming\Рефакторинг"
)

$ErrorActionPreference = "Stop"
Write-Host "=== OpenCode Migration Deployment ===" -ForegroundColor Cyan
Write-Host "Migration source: $MigrationRoot" -ForegroundColor Gray
Write-Host "Project destination: $ProjectDest" -ForegroundColor Gray
Write-Host ""

# --- Phase 1: Check Prerequisites ---
Write-Host "--- Checking Prerequisites ---" -ForegroundColor Yellow

$prereqs = @(
    @{ Name = "Node.js"; Command = "node --version" },
    @{ Name = "Python"; Command = "python --version" },
    @{ Name = "Git"; Command = "git --version" },
    @{ Name = "OpenCode"; Command = "opencode --version" }
)

foreach ($prereq in $prereqs) {
    try {
        $result = Invoke-Expression $prereq.Command 2>&1
        Write-Host "  [OK] $($prereq.Name): $result" -ForegroundColor Green
    } catch {
        Write-Host "  [MISSING] $($prereq.Name) — install before continuing" -ForegroundColor Red
    }
}

Write-Host ""

# --- Phase 2: Deploy Serena ---
Write-Host "--- Deploying Serena ---" -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
$serenaSrc = "$MigrationRoot\04-tools\serena.exe"
if (Test-Path $serenaSrc) {
    Copy-Item $serenaSrc "$env:USERPROFILE\.local\bin\" -Force
    Write-Host "  [OK] serena.exe deployed" -ForegroundColor Green
} else {
    Write-Host "  [WARN] serena.exe not found in migration package" -ForegroundColor Yellow
}

# Add to PATH
$pathDir = "$env:USERPROFILE\.local\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$pathDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$pathDir", "User")
    Write-Host "  [OK] Added to PATH: $pathDir" -ForegroundColor Green
}
Write-Host ""

# --- Phase 3: Deploy Global Config ---
Write-Host "--- Deploying Global Configuration ---" -ForegroundColor Yellow
$configDest = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force -Path "$configDest\plugins" | Out-Null
New-Item -ItemType Directory -Force -Path "$configDest\agents" | Out-Null

Copy-Item "$MigrationRoot\01-global-config\opencode.json" "$configDest\" -Force
Copy-Item "$MigrationRoot\01-global-config\opencode.jsonc" "$configDest\" -Force -ErrorAction SilentlyContinue
Copy-Item "$MigrationRoot\01-global-config\plugins\*" "$configDest\plugins\" -Force
Copy-Item "$MigrationRoot\01-global-config\agents\*.md" "$configDest\agents\" -Force

$agentCount = (Get-ChildItem "$configDest\agents\*.md").Count
Write-Host "  [OK] Config deployed ($agentCount agents)" -ForegroundColor Green

# Fix machine-specific paths
$config = Get-Content "$configDest\opencode.json" -Raw
$config = $config -replace 'C:\\\\Users\\\\Admin', "C:\\Users\\$env:USERNAME"
$config = $config -replace 'C:\\Users\\Admin', "C:\\Users\\$env:USERNAME"
$config | Set-Content "$configDest\opencode.json" -Encoding UTF8
Write-Host "  [OK] Paths updated for $env:USERNAME" -ForegroundColor Green
Write-Host ""

# --- Phase 4: Deploy Data ---
Write-Host "--- Deploying Data Storage ---" -ForegroundColor Yellow
$dataDest = "$env:USERPROFILE\.local\share\opencode"
New-Item -ItemType Directory -Force -Path "$dataDest\storage\session_diff" | Out-Null
New-Item -ItemType Directory -Force -Path "$dataDest\storage\todo" | Out-Null
New-Item -ItemType Directory -Force -Path "$dataDest\tool-output" | Out-Null
New-Item -ItemType Directory -Force -Path "$dataDest\log" | Out-Null

Copy-Item "$MigrationRoot\02-data\opencode.db" "$dataDest\" -Force -ErrorAction SilentlyContinue
Copy-Item "$MigrationRoot\02-data\storage\session_diff\*" "$dataDest\storage\session_diff\" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$MigrationRoot\02-data\storage\todo\*" "$dataDest\storage\todo\" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$MigrationRoot\02-data\tool-output\*" "$dataDest\tool-output\" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$MigrationRoot\02-data\log\*" "$dataDest\log\" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  [OK] Data deployed" -ForegroundColor Green
Write-Host ""

# --- Phase 5: Deploy Project Files ---
Write-Host "--- Deploying Project Files ---" -ForegroundColor Yellow
if (-not (Test-Path $ProjectDest)) {
    Write-Host "  [WARN] Project directory not found: $ProjectDest" -ForegroundColor Yellow
    Write-Host "  Clone the repository first, then run this script again." -ForegroundColor Yellow
} else {
    Copy-Item "$MigrationRoot\03-project-files\AGENTS.md" "$ProjectDest\" -Force
    Copy-Item "$MigrationRoot\03-project-files\ARCHITECTURE.md" "$ProjectDest\" -Force
    Copy-Item "$MigrationRoot\03-project-files\PLUGIN.md" "$ProjectDest\" -Force
    Copy-Item "$MigrationRoot\03-project-files\MCP_SETUP.md" "$ProjectDest\" -Force

    # Plugins
    New-Item -ItemType Directory -Force -Path "$ProjectDest\plugins" | Out-Null
    Copy-Item "$MigrationRoot\03-project-files\plugins\*" "$ProjectDest\plugins\" -Recurse -Force

    # Agents
    if (Test-Path "$MigrationRoot\03-project-files\agents") {
        New-Item -ItemType Directory -Force -Path "$ProjectDest\agents" | Out-Null
        Copy-Item "$MigrationRoot\03-project-files\agents\*" "$ProjectDest\agents\" -Recurse -Force
    }

    # opencode-config
    if (Test-Path "$MigrationRoot\03-project-files\opencode-config") {
        New-Item -ItemType Directory -Force -Path "$ProjectDest\opencode-config" | Out-Null
        Copy-Item "$MigrationRoot\03-project-files\opencode-config\*" "$ProjectDest\opencode-config\" -Recurse -Force
    }

    # .opencode
    New-Item -ItemType Directory -Force -Path "$ProjectDest\.opencode" | Out-Null
    Copy-Item "$MigrationRoot\03-project-files\.opencode\package.json" "$ProjectDest\.opencode\" -Force
    Copy-Item "$MigrationRoot\03-project-files\.opencode\package-lock.json" "$ProjectDest\.opencode\" -Force

    # .serena
    New-Item -ItemType Directory -Force -Path "$ProjectDest\.serena" | Out-Null
    Copy-Item "$MigrationRoot\03-project-files\.serena\project.yml" "$ProjectDest\.serena\" -Force
    Copy-Item "$MigrationRoot\03-project-files\.serena\project.local.yml" "$ProjectDest\.serena\" -Force -ErrorAction SilentlyContinue
    Copy-Item "$MigrationRoot\03-project-files\.serena\.gitignore" "$ProjectDest\.serena\" -Force -ErrorAction SilentlyContinue

    # npm install
    Set-Location "$ProjectDest\.opencode"
    npm install 2>&1 | Out-Null
    Write-Host "  [OK] Plugin dependencies installed" -ForegroundColor Green

    Write-Host "  [OK] Project files deployed" -ForegroundColor Green
}
Write-Host ""

# --- Phase 6: API Keys ---
Write-Host "--- API Keys Configuration Required ---" -ForegroundColor Yellow
Write-Host "  IMPORTANT: You must manually update API keys in opencode.json:" -ForegroundColor Red
Write-Host "  File: $configDest\opencode.json" -ForegroundColor Gray
Write-Host ""
Write-Host "  Keys needed:" -ForegroundColor Gray
Write-Host "    1. provider.bailian-token-plan.options.apiKey  (Alibaba sk-sp-*)" -ForegroundColor Gray
Write-Host "    2. provider.zai-coding-plan.options.apiKey     (Z.AI)" -ForegroundColor Gray
Write-Host "    3. mcp.zread.headers.Authorization             (Bearer Z.AI key)" -ForegroundColor Gray
Write-Host "    4. mcp.webSearchPrime.headers.Authorization    (Bearer Z.AI key)" -ForegroundColor Gray
Write-Host "    5. mcp.webReader.headers.Authorization         (Bearer Z.AI key)" -ForegroundColor Gray
Write-Host "    6. mcp.zai-mcp-server.environment.Z_AI_API_KEY (Z.AI key)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Run: notepad `"$configDest\opencode.json`"" -ForegroundColor Cyan
Write-Host ""

# --- Done ---
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit API keys in opencode.json" -ForegroundColor White
Write-Host "  2. Test: opencode --agent orchestrator" -ForegroundColor White
Write-Host "  3. Test: opencode --agent plankestrator" -ForegroundColor White
Write-Host ""
Write-Host "See MIGRATION_PLAN.md Section 7 for full verification checklist." -ForegroundColor Gray
```

---

## 7. Post-Migration Verification Checklist

### 7.1 File Integrity

- [ ] `~/.config/opencode/opencode.json` exists and is valid JSON
- [ ] `~/.config/opencode/plugins/workflow-enforcement.ts` exists
- [ ] All 34 agent `.md` files exist in `~/.config/opencode/agents/`
- [ ] `~/.local/share/opencode/opencode.db` exists (if migrated)
- [ ] Project files exist: `AGENTS.md`, `ARCHITECTURE.md`, `PLUGIN.md`, `MCP_SETUP.md`
- [ ] `plugins/workflow-enforcement.ts` exists in project root
- [ ] `.opencode/package.json` exists in project root
- [ ] `.serena/project.yml` exists in project root

### 7.2 API Keys

- [ ] `provider.bailian-token-plan.options.apiKey` is set (not placeholder)
- [ ] `provider.zai-coding-plan.options.apiKey` is set (not placeholder)
- [ ] All MCP server `Authorization` headers use correct Bearer token
- [ ] `mcp.zai-mcp-server.environment.Z_AI_API_KEY` is set

### 7.3 Machine-Specific Paths

- [ ] Serena executable path in `opencode.json` matches target machine (`C:\\Users\\USERNAME\\.local\\bin\\serena.exe`)
- [ ] Shell setting is correct (`powershell` for Windows)
- [ ] Plugin path in opencode.json points to correct location (`./plugins/workflow-enforcement.ts`)

### 7.4 Plugin Verification

```powershell
# Start OpenCode and check for plugin initialization
opencode --agent orchestrator
# Expected log: "Workflow enforcement plugin initialized"
```

- [ ] Plugin loads without errors
- [ ] No TypeScript compilation errors
- [ ] Routing tables are enforced (orchestrator cannot call plankestrator agents)

### 7.5 MCP Server Verification

```powershell
# Test each MCP server by starting a session
opencode --agent orchestrator
```

| MCP Server | Test Command | Expected |
|-----------|-------------|----------|
| zread | Ask agent to search GitHub docs | Returns search results |
| webSearchPrime | Ask agent to search web | Returns web results |
| webReader | Ask agent to read a URL | Returns page content |
| serena | Ask agent to find a symbol | Returns symbol info |
| zai-mcp-server | Ask agent to analyze an image | Returns image description |
| unity-mcp | Open Unity Editor + start MCP server | Unity tools available |

### 7.6 Agent Verification

| Test | Command | Expected Result |
|------|---------|----------------|
| orchestrator starts | `opencode --agent orchestrator` | "IDENTITY VERIFIED: I am orchestrator" |
| plankestrator starts | `opencode --agent plankestrator` | "IDENTITY VERIFIED: I am plankestrator" |
| orchestrator delegates | Send a DEV SIMPLE task | Routes to worker → utility |
| plankestrator delegates | Send a PLAN task | Routes to plan-writer → plan-reviewer |
| Routing violation | orchestrator tries plan-writer-simple | "WORKFLOW VIOLATION" error |
| worker bash | worker runs `npm --version` | Returns version number |
| consistency-checker | Validates architecture | Returns check results |
| view-image | Analyze an image | Returns image description |

### 7.7 Pipeline Verification

| Pipeline | Test Task | Expected Agent Sequence |
|----------|-----------|------------------------|
| BUGFIX SIMPLE | "Fix a typo in readme" | bugfix-triage → worker → utility |
| BUGFIX DEEP | "Fix a complex bug with planning" | bugfix-triage → plan-bug → execute-bug → dev-reviewer → rework → consistency-checker → utility |
| DEV SIMPLE | "Create a new utility function" | worker → utility |
| DEV SIMPLE (with plan) | "Implement the plan from PLAN.md" | worker → consistency-checker → utility |
| DEV COMPLEX | "Refactor the entire module" | dev-planner → dev-professor → dev-reviewer → rework → consistency-checker → utility |
| DEVOPS | "Deploy to staging" | devops-agent → devops-reviewer |
| DOCS | "Write API documentation" | docs-writer → utility |
| PLAN | "Create a plan for feature X" | plan-writer → plan-reviewer |
| RESEARCH | "Research options for Y" | research-writer → research-reviewer |

---

## 8. Potential Issues and Troubleshooting

### 8.1 API Key Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Invalid API key | "401 Unauthorized" errors | Verify API key is correct and active |
| Missing API key | MCP servers fail to connect | Edit opencode.json and add keys |
| Expired key | Initially works, then stops | Regenerate key from provider dashboard |
| Wrong provider | Models not found errors | Check model names match provider config |

### 8.2 Path Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Serena path wrong | "serena not found" errors | Update `mcp.serena.command` in opencode.json |
| Windows username differs | Serena/MCP servers fail | Run path fix: replace `Admin` with actual username |
| Drive letter differs | Project not found | Clone repo to same path or update references |
| Spaces in path | Serena fails to start | Wrap path in quotes in opencode.json |

### 8.3 Plugin Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Plugin not loading | No "Workflow enforcement" log | Check path in opencode.json `plugins` field |
| TypeScript errors | Plugin crashes on load | Run `npm install` in `.opencode/` directory |
| Routing table mismatch | Valid calls are blocked | Verify plugin routing tables match opencode.json whitelist |
| Plugin conflict | Unexpected behavior | Try `OPENCODE_PURE=1` to disable plugins |

### 8.4 Agent Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Missing agent file | "Agent not found" error | Verify all 34 .md files exist in `~/.config/opencode/agents/` |
| Agent identity drift | "IDENTITY DRIFT DETECTED" warnings | Check agent .md frontmatter matches opencode.json |
| worker no bash | "bash is not available" | Verify worker has `bash: allow` in opencode.json |
| MCP tools denied | "Permission denied" errors | Check `unity-mcp.*: allow` and `serena_*: allow` in agent config |

### 8.5 Database Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Database locked | OpenCode fails to start | Stop all OpenCode instances before copying DB |
| Corrupted DB | Session history missing | Delete opencode.db and let OpenCode recreate it |
| Schema mismatch | Errors loading sessions | Use fresh DB (old sessions will be lost) |

### 8.6 MCP Server Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| zread offline | GitHub search fails | Check internet connection and Z.AI API key |
| serena startup | Serena MCP crashes | Verify Python 3.10+ installed, serena.exe in PATH |
| unity-mcp offline | Unity tools unavailable | Start Unity Editor and MCP server first |
| npx zai-mcp-server | zai-mcp-server fails | Run `npx -y @z_ai/mcp-server` manually to test |
| Port 8080 occupied | unity-mcp can't start | Close other services on port 8080 |

### 8.7 Escape Hatches

When configuration is broken and OpenCode won't start:

| Environment Variable | Purpose |
|---------------------|---------|
| `OPENCODE_DISABLE_PROJECT_CONFIG=1` | Skip local opencode.json |
| `OPENCODE_CONFIG=/path/to/file.json` | Load alternative config |
| `OPENCODE_CONFIG_CONTENT='{}'` | Inject inline JSON config |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS=1` | Skip default plugins |
| `OPENCODE_PURE=1` | Skip external plugins |
| `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` | Skip skills from ~/.claude/ |
| `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` | Skip skills from ~/.agents/ |

---

## 9. Backup Recommendations

### 9.1 Before Migration (Source Computer)

```powershell
# Create timestamped backup of entire config
$backupDir = "$env:USERPROFILE\opencode-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $backupDir

# Backup global config
Copy-Item "$env:USERPROFILE\.config\opencode" "$backupDir\config" -Recurse

# Backup data
Copy-Item "$env:USERPROFILE\.local\share\opencode" "$backupDir\data" -Recurse

# Backup project files
Copy-Item "P:\Programming\Рефакторинг\.opencode" "$backupDir\project-opencode" -Recurse
Copy-Item "P:\Programming\Рефакторинг\.serena" "$backupDir\project-serena" -Recurse
Copy-Item "P:\Programming\Рефакторинг\plugins" "$backupDir\project-plugins" -Recurse
Copy-Item "P:\Programming\Рефакторинг\*.md" "$backupDir\project-root-md\"

Write-Host "Backup created at: $backupDir" -ForegroundColor Green
```

### 9.2 After Deployment (Target Computer)

```powershell
# Create immediate post-deployment backup
$backupDir = "$env:USERPROFILE\opencode-postdeploy-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $backupDir
Copy-Item "$env:USERPROFILE\.config\opencode" "$backupDir\config" -Recurse
Copy-Item "$env:USERPROFILE\.local\share\opencode" "$backupDir\data" -Recurse
Write-Host "Post-deployment backup at: $backupDir" -ForegroundColor Green
```

### 9.3 Ongoing Backup Strategy

| What to Backup | Frequency | Method |
|---------------|-----------|--------|
| `~/.config/opencode/` | After config changes | Manual copy or git repo |
| `~/.local/share/opencode/opencode.db` | Daily | Scheduled task |
| Project files (AGENTS.md, etc.) | Per git commit | Git version control |
| API keys | Secure storage | Password manager (1Password, Bitwarden) |

### 9.4 What NOT to Backup

| Item | Reason |
|------|--------|
| `.opencode/node_modules/` | Regenerated by `npm install` |
| `.serena/cache/` | Regenerated by Serena LSP |
| `~/.local/share/opencode/log/` | Transient, not critical |
| `~/.local/share/opencode/tool-output/` | Transient, not critical |

---

## Appendix A: Complete File Checklist

### Files that MUST be migrated (critical)

| # | Source Path | Destination Path |
|---|-------------|------------------|
| 1 | `~/.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| 2 | `~/.config/opencode/plugins/workflow-enforcement.ts` | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| 3-35 | `~/.config/opencode/agents/*.md` (34 files) | `~/.config/opencode/agents/*.md` |
| 36 | `PROJECT/AGENTS.md` | `PROJECT/AGENTS.md` |
| 37 | `PROJECT/ARCHITECTURE.md` | `PROJECT/ARCHITECTURE.md` |
| 38 | `PROJECT/PLUGIN.md` | `PROJECT/PLUGIN.md` |
| 39 | `PROJECT/MCP_SETUP.md` | `PROJECT/MCP_SETUP.md` |
| 40 | `PROJECT/plugins/workflow-enforcement.ts` | `PROJECT/plugins/workflow-enforcement.ts` |
| 41 | `PROJECT/.opencode/package.json` | `PROJECT/.opencode/package.json` |
| 42 | `PROJECT/.serena/project.yml` | `PROJECT/.serena/project.yml` |
| 43 | `%USERPROFILE%\.local\bin\serena.exe` | `%USERPROFILE%\.local\bin\serena.exe` |

### Files that SHOULD be migrated (recommended)

| # | Source Path | Destination Path |
|---|-------------|-------------|
| 44 | `~/.local/share/opencode/opencode.db` | `~/.local/share/opencode/opencode.db` |
| 45 | `~/.local/share/opencode/storage/session_diff/` | `~/.local/share/opencode/storage/session_diff/` |
| 46 | `~/.local/share/opencode/storage/todo/` | `~/.local/share/opencode/storage/todo/` |
| 47 | `PROJECT/.opencode/package-lock.json` | `PROJECT/.opencode/package-lock.json` |
| 48 | `PROJECT/.serena/project.local.yml` | `PROJECT/.serena/project.local.yml` |

### Files that are OPTIONAL to migrate

| # | Source Path | Reason to Skip |
|---|-------------|----------------|
| 49 | `~/.local/share/opencode/tool-output/` | Transient data |
| 50 | `~/.local/share/opencode/log/` | Regenerated |
| 51 | `.serena/cache/` | Regenerated by LSP |
| 52 | `.opencode/node_modules/` | Regenerated by npm install |
| 53 | `opencode-config/` | Reference copies only |
| 54 | `PROJECT/agents/*.md` | May differ from global agents |
| 55 | `PLAN.md` | Temporary planning doc |
| 56 | `FIX_consistency_checker_bug_plan.md` | Temporary planning doc |

---

## Appendix B: Quick Reference Card

```
╔══════════════════════════════════════════════════════════════╗
║             OPENCODE MIGRATION QUICK REFERENCE              ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  SOURCE COMPUTER:                                            ║
║  1. Verify OpenCode works                                    ║
║  2. Run export scripts (Phases 1-7)                          ║
║  3. Copy migration folder to transfer media                  ║
║                                                              ║
║  TARGET COMPUTER:                                            ║
║  1. Install Node.js 18+, Python 3.10+, Git                  ║
║  2. npm install -g opencode                                  ║
║  3. Copy migration folder to C:\opencode-migration\          ║
║  4. Run deploy.ps1                                           ║
║  5. Edit API keys in opencode.json                           ║
║  6. npm install in .opencode/                                ║
║  7. Test: opencode --agent orchestrator                      ║
║  8. Test: opencode --agent plankestrator                     ║
║                                                              ║
║  KEY DIRECTORIES:                                            ║
║  Config:  %USERPROFILE%\.config\opencode\                    ║
║  Data:    %USERPROFILE%\.local\share\opencode\               ║
║  Serena:  %USERPROFILE%\.local\bin\serena.exe                ║
║  Project: (your git repo root)                               ║
║                                                              ║
║  KEY FILES:                                                  ║
║  opencode.json          — Main configuration                 ║
║  workflow-enforcement.ts — Plugin                            ║
║  agents/*.md            — 34 agent definitions               ║
║  AGENTS.md              — Project rules                      ║
║  ARCHITECTURE.md        — Architecture requirements          ║
║                                                              ║
║  TROUBLESHOOTING:                                            ║
║  Plugin not loading? → Check path in opencode.json           ║
║  MCP not working?    → Check API keys + internet             ║
║  Routing blocked?     → Check whitelist in plugin            ║
║  No bash?             → worker must have bash: allow         ║
║  Won't start?         → Try OPENCODE_PURE=1                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
```

---

**Document Version:** 1.0  
**Created:** 2026-06-02  
**Compatible with:** OpenCode dual-primary-agent architecture (33 agents, 6 MCP servers, 12 pipelines)