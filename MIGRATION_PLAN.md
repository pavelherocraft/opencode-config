# OpenCode Full Migration Plan

**Version:** 3.0  
**Date:** 2026-06-02  
**Purpose:** Transfer OpenCode global configuration, agents, MCP setup, AND project infrastructure templates to another computer for use with **multiple projects**

> **IMPORTANT:** This plan migrates BOTH global OpenCode architecture AND project infrastructure templates. The target computer can deploy the global config once, then use the included templates to set up any number of projects.

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
10. [Cross-Project Agent Behavior Guide](#10-cross-project-agent-behavior-guide)

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
+----------------------+                     +----------------------+
| OpenCode running     |  -- Export to -->   | Migration folder     |
| with full config     |     USB/Cloud/       | received            |
|                      |     Network          |                      |
| Export GLOBAL files  |                     | Deploy script        |
| to migration folder  |                     | restores global      |
| (NO project files)   |                     | configuration        |
+----------------------+                     +----------------------+
```

### What Gets Migrated vs. What Does NOT

| Migrated (Global) | Migrated (Templates) | NOT Migrated |
|-------------------|----------------------|--------------|
| `~/.config/opencode/` (all agents, config, plugin) | `AGENTS.md` (template with placeholders) | Source project code/files |
| `~/.local/share/opencode/` (database, logs, storage) | `ARCHITECTURE.md` (template with placeholders) | Build artifacts |
| `serena.exe` binary | `PLUGIN.md` (template) | `.git/` history |
| MCP server configurations in `opencode.json` | `MCP_SETUP.md` (template) | |
| API provider configurations | `.serena/project.yml` (template) | |
| Agent definitions (34 .md files) | `.opencode/package.json` (template) | |
| | `plugins/workflow-enforcement.ts` (per-project copy) | |

**Templates are deployed to each target project and customized with project-specific values.**

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

### 2.3 Project Infrastructure Templates (Migrated as Templates)

> **These files are INCLUDED as templates** in the migration package. They are deployed to each target project and customized during deployment.

| File | Purpose | Template Placeholders |
|------|---------|----------------------|
| `templates/AGENTS.md` | Project rules for agents | `{{PROJECT_NAME}}`, `{{PROJECT_TYPE}}` |
| `templates/ARCHITECTURE.md` | Architecture requirements | `{{PROJECT_NAME}}`, `{{LANGUAGES}}` |
| `templates/PLUGIN.md` | Plugin documentation | None (generic docs) |
| `templates/MCP_SETUP.md` | MCP setup instructions | `{{USERNAME}}`, `{{USERPROFILE}}` |
| `templates/plugins/workflow-enforcement.ts` | Project-local plugin copy | None (copied as-is) |
| `templates/.opencode/package.json` | Plugin dependencies | None (copied as-is) |
| `templates/.serena/project.yml` | Serena LSP configuration | `{{PROJECT_NAME}}`, `{{LANGUAGES}}` |

**Deployment:** The `deploy.ps1` script copies these templates to each specified project directory and substitutes placeholders.

### 2.4 External Tool Configurations

| # | Path | Type | Required | Description |
|---|------|------|----------|-------------|
| 65 | `%USERPROFILE%\.local\bin\serena.exe` | Binary | **CRITICAL** | Serena MCP server executable |

---

## 3. Migration Folder Structure

The migration folder organizes all files for easy transfer and deployment.

```
opencode-migration/
|
|-- README.txt                          <-- This migration plan + quick instructions
|-- MIGRATION_PLAN.md                   <-- Full migration plan (this file)
|
|-- 01-global-config/                   <-- Files for ~/.config/opencode/
|   |-- opencode.json                   <-- Main configuration
|   |-- opencode.jsonc                  <-- (if exists) JSONC variant
|   |-- plugins/
|   |   |-- workflow-enforcement.ts     <-- Workflow enforcement plugin
|   |-- agents/
|   |   |-- orchestrator.md
|   |   |-- plankestrator.md
|   |   |-- orchestrator-identity-probe.md
|   |   |-- plankestrator-identity-probe.md
|   |   |-- worker.md
|   |   |-- bugfix.md
|   |   |-- bugfix-triage.md
|   |   |-- plan-bug.md
|   |   |-- execute-bug.md
|   |   |-- dev-planner.md
|   |   |-- dev-professor.md
|   |   |-- dev-reviewer.md
|   |   |-- rework.md
|   |   |-- consistency-checker.md
|   |   |-- docs-writer.md
|   |   |-- utility.md
|   |   |-- mcp-github.md
|   |   |-- mcp-read.md
|   |   |-- mcp-search.md
|   |   |-- summarizer.md
|   |   |-- devops.md
|   |   |-- devops-agent.md
|   |   |-- devops-reviewer.md
|   |   |-- devops-readonly.md
|   |   |-- plan-writer-simple.md
|   |   |-- plan-writer-complex.md
|   |   |-- plan-reviewer-simple.md
|   |   |-- plan-reviewer-complex.md
|   |   |-- research-writer-simple.md
|   |   |-- research-writer-complex.md
|   |   |-- research-reviewer.md
|   |   |-- view-image.md
|
|-- 02-data/                            <-- Files for ~/.local/share/opencode/
|   |-- opencode.db                     <-- SQLite database
|   |-- storage/
|   |   |-- session_diff/               <-- Session differences (JSON)
|   |   |-- todo/                       <-- Todo lists (JSON)
|   |-- tool-output/                    <-- Tool execution results
|   |-- log/                            <-- Execution logs
|
|-- 03-tools/                           <-- External tools
|   |-- serena.exe                      <-- Serena binary (if portable)
|
|-- 04-templates/                       <-- Project infrastructure templates
|   |-- AGENTS.md.template
|   |-- ARCHITECTURE.md.template
|   |-- PLUGIN.md.template
|   |-- MCP_SETUP.md.template
|   |-- .serena/
|   |   |-- project.yml.template
|   |-- .opencode/
|   |   |-- package.json
|   |-- plugins/
|   |   |-- workflow-enforcement.ts
|
|-- deploy.ps1                          <-- Automated deployment script (global + multi-project)
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
- [ ] unity-mcp works (if Unity project -- only when Unity Editor is running)

#### Verify File Integrity

- [ ] `~/.config/opencode/opencode.json` exists and is valid JSON
- [ ] `~/.config/opencode/plugins/workflow-enforcement.ts` exists
- [ ] All 34 agent `.md` files exist in `~/.config/opencode/agents/`
- [ ] `~/.local/share/opencode/opencode.db` exists (check file size > 0)
- [ ] `~/.local/bin/serena.exe` exists (or note download URL)
- [ ] Project templates exist: `AGENTS.md`, `ARCHITECTURE.md`, `PLUGIN.md`, `MCP_SETUP.md`
- [ ] `.serena/project.yml` exists (for template)
- [ ] `.opencode/package.json` exists (for template)
- [ ] `plugins/workflow-enforcement.ts` exists in project root (for per-project copy)

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
- [ ] **Understand:** Target will have different projects; no project files will be migrated

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
New-Item -ItemType Directory -Force -Path "$migrationRoot\03-tools"
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

### Phase 4: Export Serena Binary

```powershell
$migrationRoot = "C:\opencode-migration"

# Copy Serena executable
Copy-Item "$env:USERPROFILE\.local\bin\serena.exe" "$migrationRoot\03-tools\" -ErrorAction SilentlyContinue

if (-not (Test-Path "$migrationRoot\03-tools\serena.exe")) {
    Write-Host "WARNING: serena.exe not found at expected path. You may need to download it separately." -ForegroundColor Yellow
    Write-Host "Download from: https://github.com/oraios/serena/releases" -ForegroundColor Yellow
}
```

### Phase 5: Export Project Templates

```powershell
$migrationRoot = "C:\opencode-migration"
$templateDir = "$migrationRoot\04-templates"

# Create template directories
New-Item -ItemType Directory -Force -Path "$templateDir\plugins"
New-Item -ItemType Directory -Force -Path "$templateDir\.serena"
New-Item -ItemType Directory -Force -Path "$templateDir\.opencode"

# Copy project files as templates
$projectRoot = "P:\Programming\Рефакторинг"  # Adjust to your project root

Copy-Item "$projectRoot\AGENTS.md" "$templateDir\AGENTS.md.template"
Copy-Item "$projectRoot\ARCHITECTURE.md" "$templateDir\ARCHITECTURE.md.template"
Copy-Item "$projectRoot\PLUGIN.md" "$templateDir\PLUGIN.md.template"
Copy-Item "$projectRoot\MCP_SETUP.md" "$templateDir\MCP_SETUP.md.template"
Copy-Item "$projectRoot\.serena\project.yml" "$templateDir\.serena\project.yml.template"
Copy-Item "$projectRoot\.opencode\package.json" "$templateDir\.opencode\package.json"
Copy-Item "$projectRoot\plugins\workflow-enforcement.ts" "$templateDir\plugins\workflow-enforcement.ts"

# Add template placeholders
$agentsTemplate = Get-Content "$templateDir\AGENTS.md.template" -Raw
$agentsTemplate = $agentsTemplate -replace 'Рефакторинг', '{{PROJECT_NAME}}'
$agentsTemplate | Set-Content "$templateDir\AGENTS.md.template" -Encoding UTF8

$serenaTemplate = Get-Content "$templateDir\.serena\project.yml.template" -Raw
$serenaTemplate = $serenaTemplate -replace 'project_name: "Рефакторинг"', 'project_name: "{{PROJECT_NAME}}"'
$serenaTemplate | Set-Content "$templateDir\.serena\project.yml.template" -Encoding UTF8

Write-Host "Templates exported to $templateDir"
```

### Phase 6: Create Deployment Script

Create `deploy.ps1` in the migration root (see Section 6, Phase 9 for full script content).

### Phase 7: Create README.txt

```powershell
$migrationRoot = "C:\opencode-migration"
@"
OpenCode Full Migration Package
=============================================
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: $env:COMPUTERNAME

QUICK START:
1. Ensure Node.js 18+, Python 3.10+, and Git are installed
2. Install OpenCode CLI: npm install -g opencode
3. Copy serena.exe from 03-tools/ to %USERPROFILE%\.local\bin\
4. Run deploy.ps1 as Administrator
5. Enter API keys when prompted
6. Run 'opencode --agent orchestrator' to verify

CONTENTS:
- 01-global-config/  --> Copy to ~/.config/opencode/
- 02-data/           --> Copy to ~/.local/share/opencode/
- 03-tools/          --> External tools (serena.exe)
- 04-templates/      --> Project infrastructure templates
- deploy.ps1         --> Automated deployment script (global + multi-project)
- MIGRATION_PLAN.md  --> Full documentation

TEMPLATES INCLUDED (deployed to each project):
- AGENTS.md, ARCHITECTURE.md, PLUGIN.md, MCP_SETUP.md
- .serena/project.yml, .opencode/package.json
- plugins/workflow-enforcement.ts

API KEYS NEEDED:
- Alibaba/bailian-token-plan
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
    "$migrationRoot\04-templates\AGENTS.md.template",
    "$migrationRoot\04-templates\ARCHITECTURE.md.template",
    "$migrationRoot\04-templates\.serena\project.yml.template"
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

# Verify serena binary
$serenaExists = Test-Path "$migrationRoot\03-tools\serena.exe"
Write-Host "  Serena binary: $(if ($serenaExists) { "OK" } else { "MISSING (optional)" })" -ForegroundColor $(if ($serenaExists) { "Green" } else { "Yellow" })

# Verify templates
$templateCount = (Get-ChildItem "$migrationRoot\04-templates\*" -Recurse -File).Count
Write-Host "  Template files: $templateCount (expected: 7)" -ForegroundColor $(if ($templateCount -ge 7) { "Green" } else { "Yellow" })

# Total size
$totalSize = (Get-ChildItem $migrationRoot -Recurse | Measure-Object -Property Length -Sum).Sum
Write-Host "`n  Total migration size: $([math]::Round($totalSize / 1MB, 2)) MB" -ForegroundColor Cyan

# Confirm no source code is included
$sourceFiles = Get-ChildItem "$migrationRoot" -Recurse -File | Where-Object {
    $_.Extension -in @(".cs", ".py", ".js", ".ts", ".java", ".cpp", ".go", ".rs") -and
    $_.DirectoryName -notlike "*node_modules*" -and
    $_.DirectoryName -notlike "*.git*"
}
if ($sourceFiles) {
    Write-Host "`n  WARNING: Source code files found in migration folder!" -ForegroundColor Red
    $sourceFiles | ForEach-Object { Write-Host "    $($_.FullName)" -ForegroundColor Red }
} else {
    Write-Host "`n  OK: No source code in migration folder" -ForegroundColor Green
}
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
Copy-Item "C:\opencode-migration\03-tools\serena.exe" "$env:USERPROFILE\.local\bin\"

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
# Parse JSON and update paths properly (more reliable than regex)
$configPath = "$configDest\opencode.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json -Depth 100

# Update Serena path if it exists
if ($config.mcp.serena.command) {
    $config.mcp.serena.command = $config.mcp.serena.command -replace 'C:\\Users\\[^\\]+', "C:\\Users\\$env:USERNAME"
}

# Save back
$config | ConvertTo-Json -Depth 100 | Set-Content $configPath -Encoding UTF8

Write-Host "Paths updated for user: $env:USERNAME"
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

> **Recommendation:** Consider starting with a fresh database on the target computer to avoid old path references and session history from the source. Delete `$dataDest\opencode.db` after copying and let OpenCode recreate it.

### Phase 8: Deploy Project Templates to Multiple Projects

The `deploy.ps1` script handles deployment to multiple projects. You can specify projects interactively or via parameter.

**Example project structure on target:**
```
C:\Projects\
|-- MyUnityGame\
|-- MyWebApp\
|-- MyPythonAPI\
```

**Deploy to all projects:**
```powershell
# Run deploy.ps1 with project paths
.\deploy.ps1 -ProjectPaths @("C:\Projects\MyUnityGame", "C:\Projects\MyWebApp", "C:\Projects\MyPythonAPI")
```

**Or run interactively:**
```powershell
.\deploy.ps1
# Script will prompt for project paths
```

**What gets deployed to each project:**
- `AGENTS.md` -- Customized with project name
- `ARCHITECTURE.md` -- Customized with project name and languages
- `PLUGIN.md` -- Generic plugin documentation
- `MCP_SETUP.md` -- Setup guide with target machine paths
- `.serena/project.yml` -- Serena config with project name and detected languages
- `.opencode/package.json` -- Plugin dependencies
- `plugins/workflow-enforcement.ts` -- Per-project plugin copy
- `npm install` runs automatically in `.opencode/`

### Phase 9: Automated Deployment Script (deploy.ps1)

The following script automates Phases 3-8. Save as `deploy.ps1` in the migration root:

```powershell
# deploy.ps1 -- OpenCode Full Migration Deployment Script
# Run on target computer after copying migration folder
# This script deploys global configuration AND project templates to multiple projects

param(
    [string]$MigrationRoot = "C:\opencode-migration",
    [string[]]$ProjectPaths = @(),
    [switch]$SkipGlobal = $false,
    [switch]$SkipTemplates = $false,
    [switch]$Interactive = $false
)

$ErrorActionPreference = "Stop"
Write-Host "=== OpenCode Full Migration Deployment ===" -ForegroundColor Cyan
Write-Host "Migration source: $MigrationRoot" -ForegroundColor Gray
Write-Host ""

# --- Helper Functions ---

function Test-Command {
    param([string]$Command)
    try {
        $null = Invoke-Expression $Command 2>&1
        return $true
    } catch {
        return $false
    }
}

function Update-TemplatePlaceholders {
    param(
        [string]$TemplatePath,
        [string]$OutputPath,
        [hashtable]$Replacements
    )
    $content = Get-Content $TemplatePath -Raw -Encoding UTF8
    foreach ($key in $Replacements.Keys) {
        $content = $content -replace [regex]::Escape($key), $Replacements[$key]
    }
    $content | Set-Content $OutputPath -Encoding UTF8
}

function Get-ProjectLanguages {
    param([string]$ProjectPath)
    $languages = @()
    if (Get-ChildItem $ProjectPath -Filter "*.cs" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "csharp" }
    if (Get-ChildItem $ProjectPath -Filter "*.ts" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "typescript" }
    if (Get-ChildItem $ProjectPath -Filter "*.js" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "typescript" }
    if (Get-ChildItem $ProjectPath -Filter "*.py" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "python" }
    if (Get-ChildItem $ProjectPath -Filter "*.cpp" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "cpp" }
    if (Get-ChildItem $ProjectPath -Filter "*.rs" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "rust" }
    if (Get-ChildItem $ProjectPath -Filter "*.go" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $languages += "go" }
    if ($languages.Count -eq 0) { $languages += "json" }
    return $languages | Select-Object -Unique
}

# --- Phase 1: Check Prerequisites ---
Write-Host "--- Checking Prerequisites ---" -ForegroundColor Yellow

$prereqs = @(
    @{ Name = "Node.js"; Command = "node --version" },
    @{ Name = "Python"; Command = "python --version" },
    @{ Name = "Git"; Command = "git --version" },
    @{ Name = "OpenCode"; Command = "opencode --version" }
)

$missingPrereqs = @()
foreach ($prereq in $prereqs) {
    if (Test-Command $prereq.Command) {
        $result = Invoke-Expression $prereq.Command 2>&1
        Write-Host "  [OK] $($prereq.Name): $result" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $($prereq.Name) -- install before continuing" -ForegroundColor Red
        $missingPrereqs += $prereq.Name
    }
}

if ($missingPrereqs.Count -gt 0) {
    Write-Host "`nERROR: Missing prerequisites: $($missingPrereqs -join ', ')" -ForegroundColor Red
    exit 1
}
Write-Host ""

# --- Phase 2: Deploy Serena ---
Write-Host "--- Deploying Serena ---" -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.local\bin" | Out-Null
$serenaSrc = "$MigrationRoot\03-tools\serena.exe"
if (Test-Path $serenaSrc) {
    Copy-Item $serenaSrc "$env:USERPROFILE\.local\bin\" -Force
    Write-Host "  [OK] serena.exe deployed" -ForegroundColor Green
} else {
    Write-Host "  [WARN] serena.exe not found in migration package" -ForegroundColor Yellow
    Write-Host "  Download from: https://github.com/oraios/serena/releases" -ForegroundColor Yellow
}

# Add to PATH
$pathDir = "$env:USERPROFILE\.local\bin"
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$pathDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$pathDir", "User")
    $env:Path = "$env:Path;$pathDir"
    Write-Host "  [OK] Added to PATH: $pathDir" -ForegroundColor Green
}
Write-Host ""

# --- Phase 3: Deploy Global Config ---
if (-not $SkipGlobal) {
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

    # Fix machine-specific paths using JSON parsing (more reliable than regex)
    $configPath = "$configDest\opencode.json"
    $config = Get-Content $configPath -Raw | ConvertFrom-Json -Depth 100
    
    # Update Serena command path if it exists
    if ($config.mcp.serena.command) {
        $config.mcp.serena.command = @($config.mcp.serena.command | ForEach-Object { 
            $_ -replace 'C:\\Users\\[^\\]+', "C:\\Users\\$env:USERNAME" 
        })
    }
    
    $config | ConvertTo-Json -Depth 100 | Set-Content $configPath -Encoding UTF8
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

    # --- Phase 5: API Keys ---
    Write-Host "--- API Keys Configuration Required ---" -ForegroundColor Yellow
    Write-Host "  IMPORTANT: You must update API keys in opencode.json:" -ForegroundColor Red
    Write-Host "  File: $configDest\opencode.json" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Keys needed:" -ForegroundColor Gray
    Write-Host "    1. provider.bailian-token-plan.options.apiKey  (Alibaba)" -ForegroundColor Gray
    Write-Host "    2. provider.zai-coding-plan.options.apiKey     (Z.AI)" -ForegroundColor Gray
    Write-Host "    3. mcp.zread.headers.Authorization             (Bearer Z.AI key)" -ForegroundColor Gray
    Write-Host "    4. mcp.webSearchPrime.headers.Authorization    (Bearer Z.AI key)" -ForegroundColor Gray
    Write-Host "    5. mcp.webReader.headers.Authorization         (Bearer Z.AI key)" -ForegroundColor Gray
    Write-Host "    6. mcp.zai-mcp-server.environment.Z_AI_API_KEY (Z.AI key)" -ForegroundColor Gray
    Write-Host ""
    
    # Interactive API key update
    $updateKeys = Read-Host "Do you want to update API keys now? (y/n)"
    if ($updateKeys -eq 'y') {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json -Depth 100
        
        $bailianKey = Read-Host "Enter Alibaba API key (or press Enter to skip)"
        if ($bailianKey) { $config.provider."bailian-token-plan".options.apiKey = $bailianKey }
        
        $zaiKey = Read-Host "Enter Z.AI API key (or press Enter to skip)"
        if ($zaiKey) { 
            $config.provider."zai-coding-plan".options.apiKey = $zaiKey
            $config.mcp.zread.headers.Authorization = "Bearer $zaiKey"
            $config.mcp.webSearchPrime.headers.Authorization = "Bearer $zaiKey"
            $config.mcp.webReader.headers.Authorization = "Bearer $zaiKey"
            $config.mcp."zai-mcp-server".environment.Z_AI_API_KEY = $zaiKey
        }
        
        $config | ConvertTo-Json -Depth 100 | Set-Content $configPath -Encoding UTF8
        Write-Host "  [OK] API keys updated" -ForegroundColor Green
    }
    Write-Host ""
} else {
    Write-Host "--- Skipping Global Configuration ---" -ForegroundColor Yellow
    Write-Host ""
}

# --- Phase 6: Deploy Project Templates ---
if (-not $SkipTemplates) {
    Write-Host "--- Deploying Project Templates ---" -ForegroundColor Yellow
    
    # Get project paths
    $projects = @()
    
    if ($Interactive -or $ProjectPaths.Count -eq 0) {
        Write-Host "Enter project paths (one per line, empty line to finish):" -ForegroundColor Cyan
        while ($true) {
            $path = Read-Host "Project path"
            if ([string]::IsNullOrWhiteSpace($path)) { break }
            if (Test-Path $path) {
                $projects += $path
                Write-Host "  Added: $path" -ForegroundColor Green
            } else {
                Write-Host "  Path not found: $path" -ForegroundColor Red
            }
        }
    } else {
        foreach ($path in $ProjectPaths) {
            if (Test-Path $path) {
                $projects += $path
            } else {
                Write-Host "  [WARN] Path not found: $path" -ForegroundColor Yellow
            }
        }
    }
    
    if ($projects.Count -eq 0) {
        Write-Host "  No projects specified. Skipping template deployment." -ForegroundColor Yellow
    } else {
        $templateDir = "$MigrationRoot\04-templates"
        
        foreach ($projectPath in $projects) {
            $projectName = Split-Path $projectPath -Leaf
            Write-Host "`n  Deploying to: $projectName" -ForegroundColor Cyan
            
            # Detect languages
            $languages = Get-ProjectLanguages $projectPath
            $langString = $languages -join '", "'
            Write-Host "    Detected languages: $($languages -join ', ')" -ForegroundColor Gray
            
            # Deploy AGENTS.md
            if (Test-Path "$templateDir\AGENTS.md.template") {
                $backup = "$projectPath\AGENTS.md.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
                if (Test-Path "$projectPath\AGENTS.md") {
                    Copy-Item "$projectPath\AGENTS.md" $backup
                    Write-Host "    [OK] Backed up existing AGENTS.md" -ForegroundColor Green
                }
                Update-TemplatePlaceholders `
                    -TemplatePath "$templateDir\AGENTS.md.template" `
                    -OutputPath "$projectPath\AGENTS.md" `
                    -Replacements @{
                        '{{PROJECT_NAME}}' = $projectName
                        '{{PROJECT_TYPE}}' = ($languages -join '/')
                    }
                Write-Host "    [OK] AGENTS.md deployed" -ForegroundColor Green
            }
            
            # Deploy ARCHITECTURE.md
            if (Test-Path "$templateDir\ARCHITECTURE.md.template") {
                $backup = "$projectPath\ARCHITECTURE.md.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
                if (Test-Path "$projectPath\ARCHITECTURE.md") {
                    Copy-Item "$projectPath\ARCHITECTURE.md" $backup
                }
                Update-TemplatePlaceholders `
                    -TemplatePath "$templateDir\ARCHITECTURE.md.template" `
                    -OutputPath "$projectPath\ARCHITECTURE.md" `
                    -Replacements @{
                        '{{PROJECT_NAME}}' = $projectName
                        '{{LANGUAGES}}' = $langString
                    }
                Write-Host "    [OK] ARCHITECTURE.md deployed" -ForegroundColor Green
            }
            
            # Deploy PLUGIN.md
            if (Test-Path "$templateDir\PLUGIN.md.template") {
                Copy-Item "$templateDir\PLUGIN.md.template" "$projectPath\PLUGIN.md" -Force
                Write-Host "    [OK] PLUGIN.md deployed" -ForegroundColor Green
            }
            
            # Deploy MCP_SETUP.md
            if (Test-Path "$templateDir\MCP_SETUP.md.template") {
                Update-TemplatePlaceholders `
                    -TemplatePath "$templateDir\MCP_SETUP.md.template" `
                    -OutputPath "$projectPath\MCP_SETUP.md" `
                    -Replacements @{
                        '{{USERNAME}}' = $env:USERNAME
                        '{{USERPROFILE}}' = $env:USERPROFILE
                    }
                Write-Host "    [OK] MCP_SETUP.md deployed" -ForegroundColor Green
            }
            
            # Deploy .serena/project.yml
            if (Test-Path "$templateDir\.serena\project.yml.template") {
                New-Item -ItemType Directory -Force -Path "$projectPath\.serena" | Out-Null
                Update-TemplatePlaceholders `
                    -TemplatePath "$templateDir\.serena\project.yml.template" `
                    -OutputPath "$projectPath\.serena\project.yml" `
                    -Replacements @{
                        '{{PROJECT_NAME}}' = $projectName
                        '{{LANGUAGES}}' = ($languages -join "`n  - ")
                    }
                Write-Host "    [OK] .serena/project.yml deployed" -ForegroundColor Green
            }
            
            # Deploy .opencode/package.json
            if (Test-Path "$templateDir\.opencode\package.json") {
                New-Item -ItemType Directory -Force -Path "$projectPath\.opencode" | Out-Null
                Copy-Item "$templateDir\.opencode\package.json" "$projectPath\.opencode\" -Force
                Write-Host "    [OK] .opencode/package.json deployed" -ForegroundColor Green
                
                # Run npm install
                Push-Location "$projectPath\.opencode"
                try {
                    npm install 2>&1 | Out-Null
                    Write-Host "    [OK] npm install completed" -ForegroundColor Green
                } catch {
                    Write-Host "    [WARN] npm install failed: $_" -ForegroundColor Yellow
                }
                Pop-Location
            }
            
            # Deploy plugins/workflow-enforcement.ts
            if (Test-Path "$templateDir\plugins\workflow-enforcement.ts") {
                New-Item -ItemType Directory -Force -Path "$projectPath\plugins" | Out-Null
                Copy-Item "$templateDir\plugins\workflow-enforcement.ts" "$projectPath\plugins\" -Force
                Write-Host "    [OK] plugins/workflow-enforcement.ts deployed" -ForegroundColor Green
            }
            
            Write-Host "  [OK] $projectName configured" -ForegroundColor Green
        }
    }
    Write-Host ""
} else {
    Write-Host "--- Skipping Project Templates ---" -ForegroundColor Yellow
    Write-Host ""
}

# --- Phase 7: Post-Deploy Summary ---
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify API keys in opencode.json if not updated interactively" -ForegroundColor White
Write-Host "  2. Test global config: opencode --agent orchestrator" -ForegroundColor White
Write-Host "  3. Test global config: opencode --agent plankestrator" -ForegroundColor White
Write-Host "  4. Test in a project directory with AGENTS.md/ARCHITECTURE.md" -ForegroundColor White
Write-Host ""
Write-Host "Deployed projects:" -ForegroundColor Cyan
foreach ($project in $projects) {
    Write-Host "  - $project" -ForegroundColor White
}
Write-Host ""
Write-Host "See MIGRATION_PLAN.md Section 7 for full verification checklist." -ForegroundColor Gray
```

---

## 7. Post-Migration Verification Checklist

### 7.1 Global File Integrity

- [ ] `~/.config/opencode/opencode.json` exists and is valid JSON
- [ ] `~/.config/opencode/plugins/workflow-enforcement.ts` exists
- [ ] All 34 agent `.md` files exist in `~/.config/opencode/agents/`
- [ ] `~/.local/share/opencode/opencode.db` exists (if migrated)
- [ ] `~/.local/bin/serena.exe` exists (or downloaded separately)
- [ ] Machine-specific paths updated (username, serena path)
- [ ] API keys are set (not placeholders)

### 7.2 Per-Project File Integrity

For each deployed project, verify:
- [ ] `AGENTS.md` exists in project root
- [ ] `ARCHITECTURE.md` exists in project root
- [ ] `PLUGIN.md` exists in project root
- [ ] `MCP_SETUP.md` exists in project root
- [ ] `.serena/project.yml` exists (if using Serena)
- [ ] `.opencode/package.json` exists and `node_modules/` populated
- [ ] `plugins/workflow-enforcement.ts` exists (if using per-project plugin)
- [ ] Template placeholders replaced with actual values (no `{{...}}` remaining)

### 7.3 API Keys

- [ ] `provider.bailian-token-plan.options.apiKey` is set (not placeholder)
- [ ] `provider.zai-coding-plan.options.apiKey` is set (not placeholder)
- [ ] All MCP server `Authorization` headers use correct Bearer token
- [ ] `mcp.zai-mcp-server.environment.Z_AI_API_KEY` is set

### 7.4 Machine-Specific Paths

- [ ] Serena executable path in `opencode.json` matches target machine (`C:\\Users\\USERNAME\\.local\\bin\\serena.exe`)
- [ ] Shell setting is correct (`powershell` for Windows)
- [ ] Plugin path in `opencode.json` uses absolute path to global plugin OR each project has its own `./plugins/workflow-enforcement.ts`

### 7.5 Plugin Verification

**Global Plugin:**
- [ ] `~/.config/opencode/plugins/workflow-enforcement.ts` loads without errors
- [ ] Routing tables are enforced

**Per-Project Plugin (if used):**
- [ ] Each project's `plugins/workflow-enforcement.ts` exists
- [ ] `npm install` completed in `.opencode/` directory
- [ ] No TypeScript compilation errors

### 7.6 Multi-Project Verification

| Test | Command | Expected Result |
|------|---------|----------------|
| Project 1 works | `cd C:\Projects\Project1; opencode --agent orchestrator` | Loads Project1's AGENTS.md |
| Project 2 works | `cd C:\Projects\Project2; opencode --agent orchestrator` | Loads Project2's AGENTS.md |
| Serena in Project1 | `serena find_symbol` in Project1 | Returns symbols from Project1 |
| Serena in Project2 | `serena find_symbol` in Project2 | Returns symbols from Project2 |
| Plugin enforcement | orchestrator calls worker in any project | Routing works consistently |

### 7.7 MCP Server Verification

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

### 7.8 Agent Verification

| Test | Command | Expected Result |
|------|---------|----------------|
| orchestrator starts | `opencode --agent orchestrator` | "IDENTITY VERIFIED: I am orchestrator" |
| plankestrator starts | `opencode --agent plankestrator` | "IDENTITY VERIFIED: I am plankestrator" |
| orchestrator delegates | Send a DEV SIMPLE task | Routes to worker -> utility |
| plankestrator delegates | Send a PLAN task | Routes to plan-writer -> plan-reviewer |
| Routing violation | orchestrator tries plan-writer-simple | "WORKFLOW VIOLATION" error |
| worker bash | worker runs `npm --version` | Returns version number |
| consistency-checker | Validates architecture | Returns check results (requires ARCHITECTURE.md in project) |
| view-image | Analyze an image | Returns image description |

### 7.9 Pipeline Verification

| Pipeline | Test Task | Expected Agent Sequence |
|----------|-----------|------------------------|
| BUGFIX SIMPLE | "Fix a typo in readme" | bugfix-triage -> worker -> utility |
| BUGFIX DEEP | "Fix a complex bug with planning" | bugfix-triage -> plan-bug -> execute-bug -> dev-reviewer -> rework -> consistency-checker -> utility |
| DEV SIMPLE | "Create a new utility function" | worker -> utility |
| DEV SIMPLE (with plan) | "Implement the plan from PLAN.md" | worker -> consistency-checker -> utility |
| DEV COMPLEX | "Refactor the entire module" | dev-planner -> dev-professor -> dev-reviewer -> rework -> consistency-checker -> utility |
| DEVOPS | "Deploy to staging" | devops-agent -> devops-reviewer |
| DOCS | "Write API documentation" | docs-writer -> utility |
| PLAN | "Create a plan for feature X" | plan-writer -> plan-reviewer |
| RESEARCH | "Research options for Y" | research-writer -> research-reviewer |

### 7.10 Cross-Project Verification

Since target projects differ from source, verify agents work correctly with new project types:

| Test | Scenario | Expected Behavior |
|------|----------|-------------------|
| No AGENTS.md | Run OpenCode in a folder without AGENTS.md | Agents work with default behavior; no project-specific rules loaded |
| No ARCHITECTURE.md | consistency-checker runs in folder without ARCHITECTURE.md | Agent reports file missing and skips architecture validation |
| Unity project | OpenCode in a Unity project | unity-mcp tools available when Unity Editor + MCP server running |
| Non-Unity project | OpenCode in a Python/JS project | unity-mcp commands fail gracefully; other tools work normally |
| Serena project | Folder with `.serena/project.yml` | Serena tools available; find_symbol, find_referencing_symbols work |
| Non-Serena project | Folder without `.serena/` | Serena commands fail gracefully with clear error message |
| Multiple projects | Switch between different project folders | Each project loads its own AGENTS.md/ARCHITECTURE.md if present |

**Important:** Agents may reference tools (Serena, unity-mcp) that require project-specific setup. Each project on the target computer must set up its own `.serena/project.yml` or Unity MCP server as needed.

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
| Windows username differs | Serena/MCP servers fail | Run deploy.ps1 which auto-fixes paths |
| Spaces in path | Serena fails to start | Wrap path in quotes in opencode.json |

### 8.3 Cross-Project Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Missing AGENTS.md | Agents don't know project rules | Create AGENTS.md in new project root |
| Missing ARCHITECTURE.md | consistency-checker fails | Create ARCHITECTURE.md or avoid consistency-checker pipeline |
| Missing .serena config | Serena MCP tools fail | Run `serena init` in project or create `.serena/project.yml` |
| Unity-specific agents | Agents reference Unity in non-Unity project | Agents adapt based on available tools; ignore Unity suggestions |
| Plugin not found | "Plugin path not found" error | Copy `plugins/workflow-enforcement.ts` to project root or disable plugin |
| npm not available | worker can't run npm | Ensure Node.js installed and worker has `bash: allow` |

### 8.4 Multi-Project Deployment Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Template placeholders not replaced | Files contain `{{PROJECT_NAME}}` | Re-run deploy.ps1 for that project |
| Wrong languages detected | .serena/project.yml has incorrect languages | Manually edit project.yml or specify languages in template |
| Existing files overwritten | Lost custom project configuration | Check `.backup-*` files created by deploy.ps1 |
| npm install fails | .opencode/node_modules missing | Check Node.js version; run `npm install` manually |
| Plugin path conflict | Global vs per-project plugin confusion | Use absolute path in opencode.json for global, or ensure each project has local copy |
| Serena project name collision | Multiple projects with same name | Manually edit `.serena/project.yml` project_name field |

### 8.5 Plugin Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Plugin not loading | No "Workflow enforcement" log | Check path in opencode.json `plugins` field |
| TypeScript errors | Plugin crashes on load | Run `npm install` in `.opencode/` directory (project-specific) |
| Routing table mismatch | Valid calls are blocked | Verify plugin routing tables match opencode.json whitelist |
| Plugin conflict | Unexpected behavior | Try `OPENCODE_PURE=1` to disable plugins |

**Note:** Plugin files (`workflow-enforcement.ts`) are project-specific and must exist in each project's `plugins/` directory. The global config references them with a relative path (`./plugins/workflow-enforcement.ts`).

### 8.6 Agent Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Missing agent file | "Agent not found" error | Verify all 34 .md files exist in `~/.config/opencode/agents/` |
| Agent identity drift | "IDENTITY DRIFT DETECTED" warnings | Check agent .md frontmatter matches opencode.json |
| worker no bash | "bash is not available" | Verify worker has `bash: allow` in opencode.json |
| MCP tools denied | "Permission denied" errors | Check `unity-mcp.*: allow` and `serena_*: allow` in agent config |

### 8.7 Database Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| Database locked | OpenCode fails to start | Stop all OpenCode instances before copying DB |
| Corrupted DB | Session history missing | Delete opencode.db and let OpenCode recreate it |
| Schema mismatch | Errors loading sessions | Use fresh DB (old sessions will be lost) |
| Old path references | Suggestions show source paths | Start with fresh DB or use SQLite to clean old records |

### 8.8 MCP Server Issues

| Problem | Symptoms | Solution |
|---------|----------|----------|
| zread offline | GitHub search fails | Check internet connection and Z.AI API key |
| serena startup | Serena MCP crashes | Verify Python 3.10+ installed, serena.exe in PATH |
| unity-mcp offline | Unity tools unavailable | Start Unity Editor and MCP server first |
| npx zai-mcp-server | zai-mcp-server fails | Run `npx -y @z_ai/mcp-server` manually to test |
| Port 8080 occupied | unity-mcp can't start | Close other services on port 8080 |

### 8.9 Escape Hatches

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

# Backup serena binary (if exists)
if (Test-Path "$env:USERPROFILE\.local\bin\serena.exe") {
    New-Item -ItemType Directory -Force -Path "$backupDir\tools"
    Copy-Item "$env:USERPROFILE\.local\bin\serena.exe" "$backupDir\tools\"
}

Write-Host "Backup created at: $backupDir" -ForegroundColor Green
Write-Host "Note: Project files are NOT backed up -- use git for project-level version control." -ForegroundColor Yellow
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
| `~/.local/bin/serena.exe` | After updates | Manual copy |
| API keys | Secure storage | Password manager (1Password, Bitwarden) |

**Note:** Project files (AGENTS.md, ARCHITECTURE.md, etc.) are maintained per-project via git. They are NOT part of the global OpenCode backup.

### 9.4 What NOT to Backup

| Item | Reason |
|------|--------|
| `.opencode/node_modules/` | Regenerated by `npm install` |
| `.serena/cache/` | Regenerated by Serena LSP |
| `~/.local/share/opencode/log/` | Transient, not critical |
| `~/.local/share/opencode/tool-output/` | Transient, not critical |

---

## 10. Cross-Project Agent Behavior Guide

Since the target computer will have **different projects**, it's important to understand how agents behave when project-specific files are missing or different.

### 10.1 How Agents Load Project Rules

When OpenCode starts in a directory, it looks for project-specific instruction files:

1. **`AGENTS.md`** -- If present, loaded as additional instructions for ALL agents
2. **`ARCHITECTURE.md`** -- If present, used by `consistency-checker` for validation
3. **`plugins/workflow-enforcement.ts`** -- If present, loaded as project-local plugin

If these files are **missing**, agents fall back to their global behavior (defined in `~/.config/opencode/agents/*.md`).

### 10.2 Agent Adaptability Matrix

| Agent | Requires AGENTS.md | Requires ARCHITECTURE.md | Works Without Project Files |
|-------|-------------------|-------------------------|----------------------------|
| orchestrator | No (uses global rules) | No | Yes |
| plankestrator | No (uses global rules) | No | Yes |
| worker | No | No | Yes |
| bugfix | No | No | Yes |
| dev-reviewer | No | No | Yes |
| docs-writer | No | No | Yes |
| consistency-checker | No | **Yes** for full validation | Partial (reports missing file) |
| mcp-github | No | No | Yes |
| mcp-search | No | No | Yes |
| view-image | No | No | Yes |

### 10.3 Unity-Specific Considerations

Several agents have Unity-specific instructions (e.g., "use unity-mcp for GameObjects"). When working on **non-Unity projects**:

- Agents will still try to use `unity-mcp` tools if configured in `opencode.json`
- If Unity Editor is not running, `unity-mcp` commands will fail gracefully
- Agents should adapt based on available tools, but may occasionally suggest Unity-specific solutions
- **Recommendation:** If target projects are never Unity, consider removing `unity-mcp` from `opencode.json` MCP servers

### 10.4 Serena-Specific Considerations

Serena requires a `.serena/project.yml` file in each project root:

- Without it, Serena MCP commands (`serena_find_symbol`, etc.) will fail
- The global `serena.exe` binary is migrated, but each project needs its own config
- To set up Serena for a new project: `serena init` or create `.serena/project.yml` manually
- **Recommendation:** Include Serena setup instructions in each target project's README

### 10.5 Plugin Behavior Without Project Files

The `workflow-enforcement.ts` plugin is referenced in `opencode.json` with a **relative path**:

```json
{
  "plugins": [
    "./plugins/workflow-enforcement.ts"
  ]
}
```

This means:
- **Every project** that wants plugin enforcement must have `plugins/workflow-enforcement.ts`
- If the file is missing, OpenCode may fail to start or skip the plugin
- **Two options:**
  1. Copy `workflow-enforcement.ts` to each project's `plugins/` directory
  2. Change `opencode.json` to use an absolute path to the global plugin: `C:/Users/.../.config/opencode/plugins/workflow-enforcement.ts`

### 10.6 Setting Up a New Project on Target

For each new project on the target computer:

```powershell
# Navigate to project root
cd C:\Projects\MyNewProject

# Optional: Create AGENTS.md for project-specific rules
@"
# MyNewProject Rules

## Tools
- Use built-in tools for file operations
- Use webSearchPrime for documentation lookups

## Code Style
- Follow PEP 8 for Python
- Use TypeScript strict mode
"@ | Out-File AGENTS.md -Encoding UTF8

# Optional: Create ARCHITECTURE.md for consistency-checker
@"
# Architecture Requirements

## Allowed Technologies
- Python 3.12, FastAPI, PostgreSQL
- React 18, TypeScript, Tailwind CSS

## Forbidden
- No jQuery
- No inline styles
"@ | Out-File ARCHITECTURE.md -Encoding UTF8

# Optional: Set up Serena
serena init

# Optional: Copy plugin if using workflow enforcement
New-Item -ItemType Directory -Force -Path plugins
Copy-Item "$env:USERPROFILE\.config\opencode\plugins\workflow-enforcement.ts" plugins/
```

### 10.7 Database Cleanup Recommendation

The migrated `opencode.db` contains session history from the source computer, including:
- References to old project paths (`P:\Programming\Рефакторинг`)
- Old conversation threads
- Cached tool outputs from old projects

**Options:**
1. **Migrate as-is** -- Session history is preserved, but old paths may appear in suggestions
2. **Start fresh** -- Delete `opencode.db` on target and let OpenCode recreate it (recommended for clean slate)
3. **Selective cleanup** -- Use SQLite to delete old session records

---

## Appendix A: Complete File Checklist

### Files that MUST be migrated (critical -- global only)

| # | Source Path | Destination Path |
|---|-------------|------------------|
| 1 | `~/.config/opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| 2 | `~/.config/opencode/plugins/workflow-enforcement.ts` | `~/.config/opencode/plugins/workflow-enforcement.ts` |
| 3-35 | `~/.config/opencode/agents/*.md` (34 files) | `~/.config/opencode/agents/*.md` |
| 36 | `%USERPROFILE%\.local\bin\serena.exe` | `%USERPROFILE%\.local\bin\serena.exe` |

### Files that SHOULD be migrated (recommended)

| # | Source Path | Destination Path |
|---|-------------|-------------|
| 37 | `~/.local/share/opencode/opencode.db` | `~/.local/share/opencode/opencode.db` |
| 38 | `~/.local/share/opencode/storage/session_diff/` | `~/.local/share/opencode/storage/session_diff/` |
| 39 | `~/.local/share/opencode/storage/todo/` | `~/.local/share/opencode/storage/todo/` |

### Files that are OPTIONAL to migrate

| # | Source Path | Reason to Skip |
|---|-------------|----------------|
| 40 | `~/.local/share/opencode/tool-output/` | Transient data |
| 41 | `~/.local/share/opencode/log/` | Regenerated |

### Project Infrastructure Templates (Migrated for Multi-Project Deployment)

These templates are INCLUDED in the migration package and deployed to each target project:

| # | Template | Deployed To | Purpose |
|---|----------|-------------|---------|
| 42 | `04-templates/AGENTS.md.template` | `{ProjectRoot}/AGENTS.md` | Project rules |
| 43 | `04-templates/ARCHITECTURE.md.template` | `{ProjectRoot}/ARCHITECTURE.md` | Architecture requirements |
| 44 | `04-templates/PLUGIN.md.template` | `{ProjectRoot}/PLUGIN.md` | Plugin documentation |
| 45 | `04-templates/MCP_SETUP.md.template` | `{ProjectRoot}/MCP_SETUP.md` | MCP setup guide |
| 46 | `04-templates/.serena/project.yml.template` | `{ProjectRoot}/.serena/project.yml` | Serena configuration |
| 47 | `04-templates/.opencode/package.json` | `{ProjectRoot}/.opencode/package.json` | Plugin dependencies |
| 48 | `04-templates/plugins/workflow-enforcement.ts` | `{ProjectRoot}/plugins/workflow-enforcement.ts` | Per-project plugin |

### Files that are EXCLUDED (not migrated)

| # | File | Reason for Exclusion |
|---|------|----------------------|
| -- | Source project source code (`.cs`, `.py`, `.js`, etc.) | Different projects on target |
| -- | Source project build artifacts | Regenerated |
| -- | Source project `.git/` | Use git clone/remote on target |
| -- | `node_modules/` | Regenerated by `npm install` |
| -- | `.serena/cache/` | Regenerated by Serena LSP |
| -- | `opencode-config/` reference copies | Templates are in `04-templates/` |

---

## Appendix B: Quick Reference Card

```
+==============================================================+
|             OPENCODE MIGRATION QUICK REFERENCE              |
+==============================================================+
|                                                              |
|  SOURCE COMPUTER:                                            |
|  1. Verify OpenCode works                                    |
|  2. Run export scripts (Phases 1-6)                          |
|  3. Copy migration folder to transfer media                  |
|                                                              |
|  TARGET COMPUTER:                                            |
|  1. Install Node.js 18+, Python 3.10+, Git                  |
|  2. npm install -g opencode                                  |
|  3. Copy migration folder to C:\opencode-migration\          |
|  4. Run deploy.ps1                                           |
|  5. Edit API keys in opencode.json                           |
|  6. Test: opencode --agent orchestrator                      |
|  7. Test: opencode --agent plankestrator                     |
|                                                              |
|  KEY DIRECTORIES:                                            |
|  Config:  %USERPROFILE%\.config\opencode\                    |
|  Data:    %USERPROFILE%\.local\share\opencode\               |
|  Serena:  %USERPROFILE%\.local\bin\serena.exe                |
|                                                              |
|  KEY FILES (Global -- Migrated):                             |
|  opencode.json          -- Main configuration                |
|  workflow-enforcement.ts -- Plugin (global copy)             |
|  agents/*.md            -- 34 agent definitions              |
|                                                              |
|  KEY FILES (Project -- Templates included):                  |
|  AGENTS.md              -- Project rules                     |
|  ARCHITECTURE.md        -- Architecture requirements         |
|                                                              |
|  TROUBLESHOOTING:                                            |
|  Plugin not loading? --> Check path in opencode.json         |
|  MCP not working?    --> Check API keys + internet           |
|  Routing blocked?     --> Check whitelist in plugin          |
|  No bash?             --> worker must have bash: allow       |
|  Won't start?         --> Try OPENCODE_PURE=1                |
|                                                              |
+==============================================================+
```

---

**Document Version:** 3.0 (Full Migration with Multi-Project Support)  
**Created:** 2026-06-02  
**Updated:** 2026-06-02  
**Compatible with:** OpenCode dual-primary-agent architecture (34 agents, 6 MCP servers, 12 pipelines)  
**Migration Scope:** Global configuration + Project infrastructure templates for multi-project deployment
