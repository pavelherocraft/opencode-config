# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **voice-synthesizer: TTS-модель заменена на доступную LLM (bifrost-litellm/MiniMax-M3)**: каталожная модель `bifrost-litellm/voice/xiaomi/mimo-v2.5-tts` недоступна через bifrost-litellm (`Param Incorrect`) — TTS-модели работают через специализированный TTS API, а не как обычные LLM. voice-synthesizer стал LLM-агентом (MiniMax-M3, tier executor-cheap), оркестрирующим skill audio-synthesize через bash (TTS-модели вызываются только скриптами скилла). Синхронно: frontmatter voice-synthesizer.md (live + deploy) + IMPORTANT-инструкция; ARCHITECTURE.md ×4 (Subagent Models, Model Roles: executor-cheap +voice-synthesizer, роль voice-synth удалена); MCP_SETUP.md ×3 (Models Distribution: MiniMax-M3 10→11, строка voice/xiaomi/mimo-v2.5-tts удалена; Subagents Full Table; Models 11→10); opencode.json ×2 (секция provider `voice/xiaomi/mimo-v2.5-tts` удалена; asr/voiceclone/voicedesign сохранены для скилла); pipelines_and_models.md (11→10 моделей); integrity-check (ExpectedModels 11→10). Restart required.

### Added

- **voice-synthesizer** agent (MiMo-V2.5-TTS: standard/clone/design modes)
- **audio-synthesize** skill (TTS synthesis via MiMo-V2.5-TTS models)
- New role `voice-synth` (tier: low) in Model Roles table
- orchestrator whitelist: 25 → 26 agents
- Total agents: 37 → 38
- Unique models: 10 → 11 (voice/xiaomi/mimo-v2.5-tts)
- **DEV Complexity Classification (plan: `PLAN_DEV_CLASSIFICATION.md`; backup: `backup/2026-09-22_dev_classification/`)**: decision tree Q1–Q5 + 🚫 CRITICAL RULE (`SUPERCOMPLEX` + `plan_exists: false` = INVALID) + DECOMPOSITION PROTOCOL (pre-classification `dev-planner MODE: DECOMPOSITION` turn pair) in orchestrator.md (live + deploy); PIPELINE TABLE row 5 `plan_exists` true→false (DEV COMPLEX implies plan_exists=false); superseded rule «unplanned COMPLEX DEV → plankestrator» removed — unplanned multi-step DEV stays with orchestrator (Q3: decompose first). Sync (one commit): ARCHITECTURE.md ×3 + live — new §2 subsection «DEV Complexity Classification» + SUPERCOMPLEX trigger (DECOMPOSITION path) + DEV SIMPLE PLAN EXISTS OVERRIDE + DEV COMPLEX precondition; AGENTS.md ×3 + live — trigger sentence + COMPLEX/SIMPLE notes; MCP_SETUP.md ×2 (+live trigger lines) — Pipeline Logic rows + decision rules. Plugin/opencode.json unchanged (no combination validation exists). Restart required (new sessions only).
- **Model Roles — централизованное управление моделями (OMP P1-2)** (source: `RESEARCH_OMP_FEATURES.md` P1-2; plan: `PLAN_OMP_P0_P1.md` Phase 5): ARCHITECTURE.md ×3 — новая секция §Model Roles (13 ролей → 37 агентов, single source of truth; prewalk-правило tier(planner) ≥ tier(executor); миграция на role-алиасы заблокирована до поддержки рантаймом); consistency-checker — Check 11 Model Role Compliance (checks_performed 10→11, frontmatter-drift report-only); AGENTS.md ×3 + PLUGIN.md ×3 — pointer-секции. Fallback-цепочки — платформенное требование (PLAN_LLM_FALLBACK.md).
- **Step-based advisor-агент (OMP P1-1)** (source: `RESEARCH_OMP_FEATURES.md` P1-1 / Advisor Watchdog; plan: `PLAN_OMP_P0_P1.md` Phase 4): новый subagent `advisor` (Kimi K3, strictly read-only: read/grep/glob + read-only serena; edit/write/bash/unity-mcp deny) — step-boundary pre-reviewer в DEV COMPLEX (`dev-professor → advisor → dev-reviewer`) и BUGFIX DEEP (`execute-bug → advisor → dev-reviewer`); JSON-контракт severity notes + emission guard (max 4 non-blocker/run, дедуп, фильтр пустых фраз) + NIT_ONLY_MODE (immuneTurns=3 после blocker); whitelist orchestrator 24→25 (plugin ×3, opencode.json ×2, ARCHITECTURE ×3 — Grand Total **35**/**37**, AGENTS ×3, PLUGIN ×3, MCP_SETUP ×2 — Subagents 35/Total 37); учёт агентов 36→37 (verify.ps1, README, DEPLOYMENT_GUIDE, snapshots); отдельный учёт стоимости — ack-логи (per-agent token accounting платформой не предоставляется — ограничение). Restart required.
- **Per-адресат контекстные файлы (OMP P0-3)** (source: `RESEARCH_OMP_FEATURES.md` P0-3; plan: `PLAN_OMP_P0_P1.md` Phase 3): `REVIEW_CONTEXT.md` ×2 уровня (project root + user-level `~/.config/opencode/`) — инструкции только для reviewer-агентов (аналог OMP WATCHDOG.md); секции CONTEXT FILE в 6 reviewer-промптах (dev-reviewer, consistency-checker, devops-reviewer, plan-reviewer-simple, plan-reviewer-complex, research-reviewer); plugin v5 context injection (CONTEXT_FILE_AGENTS, префикс [CONTEXT FILE] в Task-prompt, warn-only с промпт-уровневым fallback); ARCHITECTURE.md ×3 §8 «Per-Audience Context Files»; AGENTS.md ×3 pointer-секция; PLUGIN.md ×3 «Context File Injection (v5)».
- **v5 — Severity-таксономия reviewer-агентов (OMP P0-1)** (source: `RESEARCH_OMP_FEATURES.md` P0-1; plan: `PLAN_OMP_P0_P1.md` Phase 1; backup: `backup/2026-09-21_omp_p0p1/phase0/`): `severity: nit|concern|blocker` в JSON dev-reviewer (новый OUTPUT FORMAT) и consistency-checker; orchestrator SEVERITY RULES (nit → rework skip; blocker → ⚠️ triggered turn + эскалация; missing → concern fail-closed); plugin v5: SEVERITY_AGENTS warn-only валидация, emission-guard (дедуп seenFindings, EMPTY_FINDING_PHRASES, бюджет 4 non-blocker/update); ARCHITECTURE.md ×3 §3 «Reviewer Severity Field»; AGENTS.md ×3 «Severity Taxonomy»; PLUGIN.md ×3 «Reviewer Severity Validation (v5)». Restart required (новая сессия).
- **`subagent_depth: 3`** в `opencode.json` — разрешение вложенных вызовов субагентов (primary → research-writer-complex → scout). Документация: https://opencode.ai/docs/config
- **Phase 5 (OMP plan Rev 2, 2026-09-20) — new subagent `scout` (local FS
  reconnaissance)** (source: `RESEARCH_OMP_ORCHESTRATION.md` — omp's dedicated
  cheap-model scout replacing builtin explore; plan:
  `PLAN_OMP_IMPLEMENTATION.md` Phase 5; user decision: Variant C — scout +
  task permissions for BOTH primaries' branches; backup:
  `backup/2026-09-19_omp_p0p1p2/phase5/`):
  - **New agent** `agents/scout.md`: mode subagent, model
    `bifrost-litellm/MiniMax-M2.7`, temperature 0.1, strictly read-only
    (read/glob/grep allow; edit/write/bash/webfetch/patch/todowrite/question/
    task deny). Response contract: "pointer, not transcript" (file:line +
    ≤3-line excerpt + relevance); analysis/synthesis/recommendations
    PROHIBITED — the calling agent (strong model) synthesizes. No
    `opencode.json` section by design: the frontmatter is the sole
    authoritative permission source (Permission Authority).
  - **Task permissions**: `"scout": "allow"` granted to 7 caller agents —
    plankestrator branch (research-writer-simple, research-writer-complex,
    plan-writer-simple, plan-writer-complex) and orchestrator branch
    (dev-planner, bugfix-triage, plan-bug) — in live `opencode.json` and its
    `deploy-package/opencode.json` mirror; frontmatter task-blocks updated
    only for research-writer-simple/complex (the other five define task
    permissions in JSON only).
  - **Agent accounting 35→36**: `ARCHITECTURE.md` ×3 copies (Grand Total
    `**34** | **36**`, Note documenting scout as out-of-routing, Subagent
    Models +`scout` = 34 rows), root `MCP_SETUP.md` (Subagents 34, Total 36,
    MiniMax-M2.7 distribution 5→6, Subagents Full Table +scout row and
    +scout in task-extras of the 7 caller rows, file lists 36),
    `deploy-package` (README, DEPLOYMENT_GUIDE, verify.ps1 → 36 + scout in
    `$requiredAgents`, `agents/scout.md` snapshot).
  - **Routing tables NOT changed** (orchestrator 24, plankestrator 10, sum 34;
    `workflow-enforcement.ts` untouched): scout is never a pipeline step —
    only internal Task calls from whitelisted subagents.
  - **Restart required**: the agent and permissions take effect only in a new
    session.

- **v4 — plankestrator self-work prevention** (source:
  `RESEARCH_PLANKESTRATOR_ISSUE.md`, plan: `PLANKESTRATOR_FIX_PLAN.md`;
  backup: `backup/2026-09-07_plankestrator_selfwork_fix/` + HASHES.txt).
  Eliminates the structural asymmetry that let plankestrator do plan/research
  work itself instead of delegating:
  - **Plugin (`workflow-enforcement.ts`), 13 ops:** inspection budget
    (`INSPECTION_BUDGET = 3` per session, Turn 1 only); post-pipeline
    inspection ban (`⛔ INSPECTION AFTER PIPELINE START`, Turns 2..N — same
    rule orchestrator follows); self-work content markers
    (`SELF_WORK_MARKERS`: `## Findings`, `## Analysis`, `Executive Summary`,
    …) detected in plankestrator's own assistant messages → next
    read/grep/glob throws (`⛔ SELF-WORK CONTENT DETECTED`); JSON-gate
    tightened — no `isFirstTaskCall` grace for locked agents, auxiliary
    targets (identity probes, view-image) exempt; `INVALID JSON OUTPUT`
    log warn→error; parent/child session attribution — `parentID` guard
    (child sessions do NOT reset parent lock) + `activeTaskDepth` depth-guards
    in `tool.execute.before`/`message.updated` (subagent calls/messages are
    not the parent's; keeps Gate A from blocking writer agents' `edit`).
  - **Prompt (`agents/plankestrator.md`), 10 ops:** ack line
    (`→ DELEGATED to <agent> for: <goal>`, Turn 1 + Turns 2..N); few-shot
    EXAMPLES section (correct vs. self-work Turn 1); complexity from REQUEST
    TEXT ONLY (RESEARCH+PLAN always COMPLEX); MAX 2 inspection calls;
    Turns 2..N inspection prohibitions; narrowed COMPLETE summary (max 3
    lines, no content recap); positive role frame ("ROUTER, not a writer…
    Your ONLY outputs are…"); new description ("NEVER investigates or
    answers directly"; keeps "Plankestrator" for session detectors, no
    "orchestrator" substring).
  - **Docs synced:** ARCHITECTURE.md (defense in depth 3→4 layers incl.
    Inspection gate v4; Plankestrator Delegation Rule — Inspection limits;
    §9 hook purposes), AGENTS.md (plankestrator section Inspection limits;
    plugin Functionality list), PLUGIN.md (§3 hooks incl. depth-guard/
    parentID-guard/INSPECTION GATE/self-work check; §5 three new error
    messages; §6 JSON gate v4 changes; §10 new known issues #6–#7; §11 v4
    state & constants).
  - **Deliberate non-sync (op. 3.8):** `deploy-package\` and
    `opencode-config\` snapshots were NOT updated — they are dated
    deployment snapshots (like `backup\*`); they will be rebuilt from live
    configs at the next deploy-package build. Not a drift violation.
  - Phase 5 (structural removal of read/grep/glob from plankestrator,
    Rec. 11) intentionally NOT executed — conditional on ≥2 violations in
    ≥5 real sessions after v4 (decision is the user's).

- **Registry-independent agents (upstream race workaround v2)** — the
  `skills.paths` config did not survive verification: after the next restart
  the skill registry was empty again in multiple project instances
  (Рефакторинг + ai-presa), while the config/schema both verifiably support
  `skills.paths` in v1.18.27. Root cause (from log forensics): ~300ms apart
  at startup, one instance initializes with a populated config (12 items)
  and others with an empty one (1 item = builtin only); the empty InstanceState
  cache is sticky for the process lifetime. Race between config loading and
  first skill-state initialization — upstream bug in opencode 1.18.27.
  Fix on our side: agent prompts no longer depend on the skill registry.
  `git-commit`, `generate-image`, `generate-image-gpt` now treat the skill
  tool as optional ("if not found — ignore and continue; the script path is
  complete on its own; NEVER report skill unavailability as a blocker").
  Routing itself works — the ai-presa session successfully invoked the
  git-commit agent (visible in opencode.log); only the skill load failed.

- **Deterministic commit routing (hard enforcement)** — prompted by the
  bifrost incident: a week-old build session (P:\Programming\bifrost) ignored
  the global AGENTS.md routing rule and ran `git commit` + `git push` via
  bash directly (confirmed in opencode.log, 14:43 UTC). Session history
  (dozens of past direct commits) outweighed system instructions. Fixes:
  - `opencode.json` top-level `permission.bash` now denies `git commit*` and
    `git push*` globally (per decision: no `git tag`, no worker/devops
    exceptions). Blocks build/plan/general and every project.
  - 10 bash-capable agents (worker, utility, rework, dev-professor,
    devops-agent, devops-reviewer, execute-bug, generate-image,
    generate-image-gpt, view-image) converted from blanket `bash: allow` to
    an ordered map: `"*": allow` first, `git commit*`/`git push*` deny after
    (findLast semantics — deny wins, everything else allowed). Redundant
    `"bash": "allow"` duplicates removed from 7 JSON agent entries.
  - `git-commit` agent keeps blanket `bash: allow` (frontmatter merges after
    global rules) — the ONLY agent exempt.
  - Global AGENTS.md hardened: Git rule renamed to HARD RULE, moved to top,
    explicit "even if session history contains past direct commits", plus
    recovery line: a permission denial on git commit/push is the signal to
    delegate via task, not to work around.
  - `git-commit` agent description sharpened: "the ONLY agent allowed to run
    git commit/push", trigger words incl. Russian phrasings.

- **Global `~/.config/opencode/AGENTS.md`** — auto-loaded in ALL projects.
  Fixes routing discovered in a neighboring session: a commit+push request in
  another project did NOT invoke the `git-commit` agent because no global
  instruction existed (the agent itself was available — 35 agents in the
  global dir load everywhere). Now MANDATORY rules live globally: git
  commits/pushes → `git-commit` agent only; image generation →
  `generate-image`/`generate-image-gpt` agents only. Also absorbs the
  MCP-first rules from `instructions.md`, which was never wired into
  opencode.json (dead file). Mirror: `AGENTS.global.md` (hash-verified).
- **`.gitignore`**: ignore `generated-images/`, `*.7z`, `opencode.db*`,
  `log/`, `tool-output/` artifacts (see below — creation was interrupted).

- **Agent `git-commit`** (`~/.config/opencode/agents/git-commit.md`, synced to
  repo `agents/`): gated conventional-commit agent.
  - Model MiniMax-M3 @ 0.1; permissions: bash/read/glob/grep allow,
    edit/write/task/webfetch/MCP deny; sees exactly one skill (`git-commit`).
  - Default path = skill script; fallback = plain git (silent, variant A).
  - Scope: commit; `-Push` only when explicitly requested. No PR support.
- **Skill `git-commit`** (`~/.config/opencode/skills/git-commit/`):
  - `scripts/commit.ps1 -Analyze` — dry-run: status, staged/unstaged stats,
    recent conventional-commit style, hygiene (large files >5MB, sensitive
    filenames, secrets in staged diff, conflict markers, git identity).
  - `-Message "..." -Files <list> | -StagedOnly [-Push]` — gated commit.
  - BLOCK gates: secrets (sk-/gh*_ /AKIA/PRIVATE KEY/xox-/AIza/Bearer),
    sensitive filenames (.env*, *.pem, *.key, id_rsa*, …), conflict markers,
    missing identity, blind commit without explicit staging.
  - `{env:VAR}` placeholders pass (not secrets). Never --no-verify/amend/force.
- **Skill `image-gen`** (`~/.config/opencode/skills/image-gen/`): unified image
  generation & editing via Bifrost LiteLLM.
  - Models: `gemini/gemini-3.1-flash-image` (default), `gemini/gemini-3-pro-image`,
    `gpt-image-2` (explicit GPT/DALL-E requests).
  - Modes: generate + edit (`--mode edit --input <path>` — source passed by path).
  - Scripts: `scripts/generate.py` (cross-platform, stdlib only) and
    `scripts/generate.ps1` (Windows-native, auto-compresses edit source to ≤300 KB).
  - Saves to project-local `./generated-images/` and prints `SAVED: <path>` only.
  - **Context safety rules** (root-cause fix for the 413/compaction loop):
    never `read` generated images, never embed base64 in replies, verify via
    file metadata or the `view-image` subagent.
- **`opencode.json` — `attachment.image` limits** (hard cap against HTTP 413
  "Request Entity Too Large" on bifrost):
  `auto_resize: true`, `max_width: 1600`, `max_height: 1600`,
  `max_base64_bytes: 262144` (256 KB).
- **`opencode.json` — provider `bifrost-litellm.models`**: three new models
  - `AlibabaTokenPlan/deepseek-v4-flash-0731` — context 1048576 / output 393216
  - `atlas/deepseek-v4-flash-0731` — context 1048576 / output 393216
  - `qwen3.8-max` — context 1048576 / output 131072, modalities `text/image/video`, attachment enabled
- **`plugins/package.json`**: added `"type": "module"` to silence Node.js
  `[MODULE_TYPELESS_PACKAGE_JSON]` warning emitted by
  `workflow-enforcement.ts` (was being reparsed as ES module on every load).

### Fixed

- **TRUE root cause of empty skill registry — my own YAML bug** (user's
  suspicion confirmed): both SKILL.md files had unquoted `description:`
  values containing `": "` sequences (`(-Analyze: status`, `"SAVED: <path>"`),
  so YAML decoded description as a nested map. In opencode's `add()`
  (packages/opencode/src/skill/index.ts) a parse failure is converted to a
  value by tryPromise's catch and `isSkillFrontmatter` then silently drops
  the skill — zero log lines. The earlier "startup race" theory was wrong;
  `skills.paths` was fine all along. Fixes: descriptions single-quoted in
  both SKILL.md files; verified live — registry went from builtin-only to
  containing `git-commit` + `image-gen`, and the V1 skill tool loads the
  skill after `POST /instance/dispose?directory=...` (no app restart
  needed).
- **Discovery path workaround**: `~/.agents/skills/` now holds REAL COPIES
  of both skills (external-dir scan uses dot:true and works); an NTFS
  junction was tried first and is NOT followed by opencode's glob — copies
  are required. NOTE: after editing skills in `~/.config/opencode/skills`,
  re-copy to `~/.agents/skills/` (or dispose + the copies go stale).
- **skills/ mirrored to the repo** (was missing).
- **Server API access documented**: desktop server listens on a rotating
  localhost port with basic auth from env `OPENCODE_SERVER_USERNAME/
  OPENCODE_SERVER_PASSWORD`; useful endpoints: GET /config, GET /skill,
  GET /path, POST /instance/dispose?directory=..., GET /doc (route list).
- **Upstream issue draft rewritten** (`ISSUE-opencode-silent-skill-drop.md`):
  silent frontmatter drop (no logging), junctions not followed, no live
  rebuild — replaces the withdrawn race theory.

- **Flaky skill registry on startup** (opencode 1.18.27 race): after a
  restart, task-instance skill discovery ran "successfully empty" — registry
  degraded to the built-in skill only, so `git-commit` agents got
  `Skill "git-commit" not found. Available skills: customize-opencode` with
  identical config/files that worked on the previous boot. Live config edits
  (removing/adding AGENTS.md) did not rebuild the poisoned InstanceState —
  only a restart re-runs discovery. Workaround: explicit
  `"skills": { "paths": ["~/.config/opencode/skills"] }` in opencode.json
  adds an independent discovery source bypassing the flaky config-dir scan.
  Post-restart verification: skill loads via skill tool (MiniMax-M3,
  mode=subagent). Candidate for an upstream issue.
- **Skill visibility punch-through** (root-caused in opencode source): the
  global `permission.skill = {"*": "deny"}` is merged AFTER .md frontmatter
  permissions (`Permission.merge(defaults, specific, user)` + `evaluate` =
  `findLast`), so per-agent frontmatter allows could never win. Fix: added
  `agent.<name>.permission.skill` allows in `opencode.json` for
  `generate-image` / `generate-image-gpt` (`image-gen`) and `git-commit`
  (`git-commit`) — `cfg.agent` entries merge last and override the global
  deny. Embedded skills (`customize-opencode`) bypass the filter by design.
- **`git-commit.md` frontmatter YAML bug**: unquoted `gated: secrets` (colon
  + space) in description broke frontmatter parsing — the agent silently ran
  on defaults (global model, `mode=all`, global permissions, no skill tool).
  Description is now quoted; agent runs as `subagent` on MiniMax-M3.
- **`image-gen/scripts/generate.ps1` extension bug**: gemini path pre-assigned
  `.jpg` while the actual payload MIME was `image/png`, and the post-hoc
  rename regexes (`\.png$` on a `.jpg`-named file) never matched — PNG bytes
  in a `.jpg` wrapper; an external normalizer then renamed files on disk,
  breaking the reported SAVED paths. Now the extension is derived from the
  actual data-URI MIME before the file is named.
- **PowerShell 5.1 byte[] splatting in edit mode**: `New-Object
  ByteArrayContent ($bytes)` splats the array into per-byte constructor
  arguments ("Cannot find an overload ... argument count 55983"). Fixed with
  the `(,$imgBytes)` wrap in `generate.ps1` and in the inline EDIT snippets
  of both `generate-image` / `generate-image-gpt` agents.

### Changed

- **Reverse-миграция `git-commit`: `bifrost-litellm/mimo-v2.5` → `bifrost-litellm/MiniMax-M3`** (отмена части model-migration `2026-09-11` для этого агента; `generate-image` / `generate-image-gpt` остаются на `mimo-v2.5`) — backfill-запись: миграция была применена ранее (live и deploy frontmatter уже на MiniMax-M3), но не документирована. Rationale: mimo-v2.5 показал себя недостаточно надёжным на склейке conventional-commit сообщений из разнородного `git status` (диффы с кириллицей, конфликт-маркеры); MiniMax-M3 (tier executor-cheap, 1M ctx) переживает большие diff'ы и держит формат. Задокументировано в: ARCHITECTURE.md ×3 (Subagent Models + tier `executor-cheap`), MCP_SETUP.md ×2 (Distribution + Full Table), `pipelines_and_models.md` (сводная таблица моделей).
- **Полная синхронизация deploy-package ↔ live-конфиг** (`~/.config/opencode/`): live → deploy для 6 агентов (`consistency-checker`, `docs-writer`, `plan-writer-complex`, `plan-writer-simple`, `research-writer-complex`, `research-writer-simple` — deploy отставал: File Output Behavior, scout-permissions, parallel scout waves); live `ARCHITECTURE.md` и `MCP_SETUP.md` приведены к repo-версиям (живые копии отставали: worker/plan-bug/rework/advisor/models-строки); `opencode-config/PLUGIN.md` — пре-v4 копия заменена актуальной; исправлен pre-existing дрейф MCP_SETUP Full Table (Kimi K2.7/GLM-5.2 → Kimi K3/GLM-5.3 (res) по frontmatter, + префикс `openrouter/` в `deepseek-v4.1-flash`); счётчики MCP_SETUP Summary (Subagents 34→35, Routing tables orchestrator 24→25, Plugin hooks 3→6, агентные файлы 36→37). `opencode.json` и `workflow-enforcement.ts` — live == deploy (SHA256), без изменений.

- **Prewalk-инверсия BUGFIX DEEP (OMP P0-2)** (source: `RESEARCH_OMP_FEATURES.md` P0-2; plan: `PLAN_OMP_P0_P1.md` Phase 2): plan-bug `MiniMax-M3 → qwen3.8-max` (сильный планировщик; description исправлен с устаревшего «Qwen3.7 Plus»), execute-bug `GLM-5.3 (res) → MiniMax-M3` (дешёвый исполнитель); контракт self-contained plan в plan-bug.md; escape hatch `plan_gap: true` в JSON execute-bug; ARCHITECTURE.md ×3 (Subagent Models + «Prewalk pattern» в §2 BUGFIX DEEP); MCP_SETUP.md ×2 (Distribution + Full Table; попутно исправлен pre-existing дрейф GLM-5.2 в строке execute-bug). Restart required.
- **Model migration `2026-09-11`: agents `generate-image`, `generate-image-gpt`, `git-commit` → `bifrost-litellm/mimo-v2.5`** (was `bifrost-litellm/MiniMax-M3`). Rationale: these agents do minimal LLM work — `generate-image*` orchestrate the `image-gen` skill (text-to-image / edit) and `git-commit` runs the gated conventional-commits script. MiniMax-M3 (1M ctx, 131K output, thinking) is sufficient and reserves flagship capacity for code-heavy agents (`worker`, `plan-bug`, `devops-agent`, `devops-readonly`, which stay on MiniMax-M3).
  - **Frontmatter (6 files)**: `model:` line 4 changed in live agents (`C:\Users\Admin\.config\opencode\agents\{generate-image,generate-image-gpt,git-commit}.md`) and their deploy-package snapshots (`deploy-package/agents/{generate-image,generate-image-gpt,git-commit}.md`).
  - **`ARCHITECTURE.md` ×3 copies** (`root/`, `opencode-config/`, `deploy-package/project-files/`): Subagent Models table — rows for `git-commit`, `generate-image`, `generate-image-gpt` updated to `bifrost-litellm/mimo-v2.5`. Rows for `worker`, `plan-bug`, `devops-agent`, `devops-readonly` preserved on MiniMax-M3 (4 agents remain).
  - **`MCP_SETUP.md`**: Models Distribution fully re-synced (old: 7 rows, sum 32, missing the 3 image/git-commit agents; new: 11 rows, sum 35 = 2 primary + 33 subagents). Detailed Subagents—Full Table: +3 new rows for `git-commit` / `generate-image` / `generate-image-gpt` (model, temperature, edit/write/read/bash permissions copied from frontmatter; task whitelist `–` since all three have `task: deny`). Summary row "Models" updated `6 → 11` with full list of the 11 bifrost-litellm models.
  - **`pipelines_and_models.md`**: +1 row in the model table near `mimo-v2.5-pro` entry, keeping mimo models grouped.
  - **Files NOT touched (per plan):** historical/fallback docs (`RESEARCH_LLM_FALLBACK.md`, `PLAN_LLM_FALLBACK.md`, `IMPLEMENTATION_PLAN.md`, `REMEDIATION_PLAN_V2.md`, `VALIDATION_REPORT.md`, `VIEW_IMAGE_RESEARCH.md`), `AGENTS.md`, `PLUGIN.md`, both `opencode.json` files (no per-agent model field).
  - Backup: `backup/2026-09-11_mimo_migration/` — 12 source files in 6 subfolders (`live-agents/`, `deploy-package-agents/`, `root/`, `opencode-config/`, `deploy-package-project/`, `docs/`) + `HASHES.txt` (SHA256 of each file).
  - **Restart required:** opencode picks up new frontmatter `model:` on next session start.

- **Orchestrator routing table expanded 21 → 24 agents** (+`generate-image`,
  +`generate-image-gpt`, +`git-commit`) — synchronized across every source of
  truth:
  - live + repo `workflow-enforcement.ts` `ROUTING_TABLES.orchestrator`
    (fixes pre-existing drift: image agents were missing from the plugin);
  - live + repo `agents/orchestrator.md` (`OPENCODE_ROUTING_TABLE` array and
    the numbered whitelist table);
  - live + repo `agents/consistency-checker.md` expectations (24/9);
  - repo docs: `AGENTS.md`, `ARCHITECTURE.md` (incl. count summary 33/35),
    `PLUGIN.md` (table + 2 code samples), `MCP_SETUP.md` (3 spots).
  - `opencode.json` orchestrator `permission.task` += `git-commit`.
  - Skipped intentionally: `deploy-package/`, `opencode-config/` snapshots,
    historical plans (`FIX_*.md`, `dev_plan.md`).
- **Image generation routing: agents-only, skill as their default path.**
  Primary sessions (build/plan/general/orchestrator/plankestrator) and all
  non-image subagents no longer see ANY skills:
  - `opencode.json` top-level `permission.skill = { "*": "deny" }` (Skill
    Discovery is a permission-filtered registry, so denied skills are not
    advertised in the system prompt at all).
  - `generate-image` / `generate-image-gpt` frontmatter punches through with
    `skill: { "*": "deny", "image-gen": "allow" }` (deny-first ordering,
    last-match-wins) — they see exactly one skill.
  - Both agents now run the skill scripts (`generate.ps1` / `generate.py`) as
    the DEFAULT path (`-Model gpt-image-2` always explicit in the GPT agent);
    the inline PowerShell snippets remain as a silent fallback when the user
    explicitly opts out OR the script fails after one retry (variant A:
    reliability over transparency).
  - `image-gen` SKILL.md description re-targeted as internal toolkit for the
    image agents.
  - Caveat: any future skill will be invisible to all agents until it gets a
    per-agent allow.
- **`qwen3.8-max`**: enabled `options.thinking.type = "enabled"` in
  `provider.bifrost-litellm.models` so that all agents routed to it
  (`dev-planner`, `plan-writer-complex`, `devops-reviewer`) reason by default.
- **9 agents migrated** to stronger models. Both the markdown frontmatter
  (`~/.config/opencode/agents/<name>.md`) and the JSON block
  (`opencode.json` → `agent.<name>.model`) were updated in lock-step:

  | Agent | From | To |
  |---|---|---|
  | `research-writer-complex` | `GLM-5.2` | `Kimi K3` |
  | `research-reviewer` | `Kimi K2.7` | `GLM-5.2` |
  | `plan-writer-complex` | `GLM-5.2` | `qwen3.8-max` |
  | `plan-reviewer-simple` | `Kimi K2.7` | `GLM-5.2` |
  | `plan-reviewer-complex` | `Kimi K2.7` | `Kimi K3` |
  | `devops-reviewer` | `QWEN3.7-plus` | `qwen3.8-max` |
  | `dev-planner` | `QWEN3.7-plus` | `qwen3.8-max` |
  | `rework` | `GLM-5.2` | `Kimi K3` |
  | `dev-reviewer` | `Kimi K2.7` | `Kimi K3` |

  Rationale: `Kimi K3` brings long-output (1M) and reasoning for complex
  review/rework/research work; `qwen3.8-max` brings 1M context for planning
  and DevOps review.
- **Agents `generate-image` / `generate-image-gpt`**: added the read-back
  prohibition rule (callers must not `read` saved images; visual checks go to
  `view-image`) to prevent base64 leaking into session history.

### Removed

- **Skill `gemini-image-gen`** — superseded by `image-gen` (same gateway,
  plus GPT path, edit mode, project-local output, context-safety rules).

### Notes

- `bifrost-litellm.models` now contains 32 entries (was 29).
- No existing models were removed.
- Provider `bailian-token-plan`, MCP servers, commands and shell settings
  were not affected by these changes.
- Diagnosis behind the skill rework: session "Презентация о плюсах ИИ в
  разработке игр" (Kimi K3) looped in auto-compaction because inline base64
  PNG file-parts in history made every request exceed the gateway body limit
  (HTTP 413), which opencode treats as context overflow. Fix = path-only
  image workflow + 256 KB attachment cap + fresh session for the poisoned one.