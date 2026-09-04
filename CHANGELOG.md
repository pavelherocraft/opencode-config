# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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