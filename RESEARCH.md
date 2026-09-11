# Validation Research: Primary Agent Configs

**Date:** 2026-09-07
**Files validated:**
- `C:\Users\Admin\.config\opencode\agents\orchestrator.md` (125 lines)
- `C:\Users\Admin\.config\opencode\agents\plankestrator.md` (117 lines)
- `C:\Users\Admin\.config\opencode\plugins\workflow-enforcement.ts` (1020 lines)
- `C:\Users\Admin\.config\opencode\opencode.json` (1588 lines)
- `P:\Programming\Рефакторинг\ARCHITECTURE.md` (668 lines)

## Executive Summary

The pipeline-first rewrite is **substantially valid**: JSON templates match the plugin contract exactly, routing tables are identical across all three sources, identity lines match the plugin regex, state machines are singular and deterministic, and both edge-case pipelines (BUGFIX two-stage, RESEARCH+PLAN) are correctly specified. However, **6 issues** were found — the most serious being a permission-layer contradiction (`todowrite`/`question` — plus a same-class batch of dead `serena_*`/`unity-mcp.*` grants — allowed in config but denied in ARCHITECTURE.md and blocked by the plugin at runtime) and a plankestrator task-allowlist in opencode.json that includes agents outside its plugin routing table, which can trigger the plugin's routing fallback and silently flip the session identity to orchestrator.

## 1. Plugin Contract Compliance

Plugin source of truth (`workflow-enforcement.ts`):

- `REQUIRED_JSON_FIELDS.orchestrator` (L50): `["agent", "type", "complexity", "plan_exists", "plan_source", "goal", "next_agent", "pipeline"]`
- `REQUIRED_JSON_FIELDS.plankestrator` (L51): `["agent", "state", "type", "complexity", "goal", "next_agent", "pipeline"]`
- `VALID_VALUES` (L54–66), `FORBIDDEN_VOCAB` (L88–99), `PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}` (L466)

### orchestrator.md

- ✅ Required fields: JSON template (L82–93) contains all 8 fields — `agent`, `type`, `complexity`, `plan_exists`, `plan_source`, `goal`, `next_agent`, `pipeline`. Exact match.
- ✅ Valid values: `type: "BUGFIX|DEVOPS|DEV|DOCS|null"` ✅; `complexity: "SIMPLE|COMPLEX|DEEP|SUPERCOMPLEX|null"` ✅; `agent: "orchestrator"` ✅; `plan_exists: true|false|null` (boolean|null per plugin L974) ✅; `plan_source: string|null` ✅; `pipeline` array ✅.
- ✅ `next_agent` constrained to routing table (L90: "agent from routing table or null") — matches plugin whitelist validation (L956–961).
- ⚠️ Forbidden vocab: no `"I am plankestrator"`, `"research-writer-"`, `"plan-writer-"`, `"research-reviewer"`, `"plan-reviewer-"` tokens present. **BUT** line 109 contains the literal tokens `"## PLAN"` and `"# Implementation Plan"` (inside the `plan_exists=true` detection rule). Both are on the orchestrator `FORBIDDEN_VOCAB` list (plugin L91–92). If the model ever quotes this rule verbatim in a message, the plugin logs a `FORBIDDEN VOCABULARY DETECTED` **error** (L414–432). The plugin does not throw on vocab violations, so impact is noisy error logs + false-positive drift signals, not a hard block. See Issue #5.

### plankestrator.md

- ✅ Required fields: JSON template (L80–90) contains all 7 fields — `agent`, `state`, `type`, `complexity`, `goal`, `next_agent`, `pipeline`. Exact match.
- ✅ Valid values: `state: "CLASSIFY|EXECUTE|REVIEW|COMPLETE"` ✅ (plugin L62); `type: "PLAN|RESEARCH|RESEARCH+PLAN|null"` ✅; `complexity: "SIMPLE|COMPLEX|null"` ✅; `agent: "plankestrator"` ✅.
- ✅ Forbidden vocab: no occurrences of `"I am orchestrator"`, `"I am the Conductor"`, `"I am the Task classifier"`, `"Task classifier and router"`, `"bugfix-triage"`, `"execute-bug"`, `"devops-agent"`, `"consistency-checker"`. Line 36 says "I am NOT orchestrator" (does not match substring `"I am orchestrator"`). Line 117 mentions `"Conductor"` / `"Task classifier"` only inside a prohibition, not as exact forbidden phrases. Clean.

## 2. Cross-File Consistency

Pipeline tables compared across `orchestrator.md`, `plankestrator.md`, and `ARCHITECTURE.md` §2:

| Pipeline | orchestrator.md / plankestrator.md | ARCHITECTURE.md | Status |
|---|---|---|---|
| BUGFIX SIMPLE | `bugfix-triage` → `["worker","utility"]` (row 1 + continuation L56) | `bugfix-triage → worker → utility` (L226) | ✅ |
| BUGFIX DEEP | continuation `["plan-bug","execute-bug","dev-reviewer","rework","consistency-checker","utility"]` (L57) | identical (L232) | ✅ |
| DEVOPS | `["devops-agent","devops-reviewer"]` (row 2) | `devops-agent → devops-reviewer` (L289) | ✅ |
| DEV SIMPLE (no plan) | `["worker","utility"]` (row 3) | `worker → utility` (L252) | ✅ |
| DEV SIMPLE (with plan) | `["worker","consistency-checker","utility"]` (row 4) | `worker → consistency-checker → [rework loop] → utility` (L253) | ⚠️ chain matches; rework-loop coverage differs (Issue #4) |
| DEV COMPLEX | `["dev-planner","dev-professor","dev-reviewer","rework","consistency-checker","utility"]` (row 5) | identical (L262) | ✅ |
| DEV SUPERCOMPLEX | per step `["dev-planner","dev-professor","dev-reviewer","consistency-checker","utility"]` (row 6) | identical per-step chain (L270–272) | ✅ |
| DOCS SIMPLE | `["docs-writer","utility"]` (row 7) | `docs-writer → utility` (L295) | ✅ |
| DOCS DEEP | `["docs-planner","docs-writer","dev-reviewer","rework","consistency-checker","utility"]` (row 8) | identical (L296–302) | ✅ |
| PLAN SIMPLE/COMPLEX | `plan-writer-* → plan-reviewer-*` (rows 1–2) | `plan-writer-* → plan-reviewer-*` (L329) | ✅ |
| RESEARCH SIMPLE/COMPLEX | `research-writer-* → research-reviewer` (rows 3–4) | `research-writer-* → research-reviewer` (L335) | ✅ |
| RESEARCH+PLAN | research-writer-* → research-reviewer → plan-writer-* → plan-reviewer-* (rows 5–6) | delegation table shows `research-writer-* → plan-writer-*` (L214), reviewers implied by PLAN/RESEARCH sections | ✅ (plankestrator.md is more precise; no contradiction) |
| Auto-DOCS hook | after final `utility`, if `requires_docs_update: true` → `["docs-writer","utility"]` (orchestrator L61) | identical (L305–324) | ✅ |
| Rework loop, max 3 | orchestrator L59 | L244, L257, L265, L282 | ⚠️ row coverage mismatch (Issue #4) |

Routing tables: `OPENCODE_ROUTING_TABLE` in orchestrator.md (L26) = plugin `ROUTING_TABLES.orchestrator` (24 agents) = ARCHITECTURE.md §1 (24 agents) — **identical, order included**. plankestrator.md (L26) = plugin (9 agents) = ARCHITECTURE.md (9 agents) — **identical**.

## 3. Identity Block Validation

### orchestrator.md

- ✅ RUNTIME IDENTITY block (L21–29): `OPENCODE_AGENT_NAME = orchestrator`, `MODE = primary`, routing table matches plugin exactly, `HANDLE_SCOPE = [BUGFIX, DEVOPS, DEV, DOCS]`, `FORBIDDEN_SCOPE = [PLAN, RESEARCH, RESEARCH+PLAN]`. Matches ARCHITECTURE.md §7 role table (L574).
- ✅ Identity line (L36): `✓ IDENTITY VERIFIED: I am orchestrator (Conductor). I am NOT plankestrator. ...` — matches plugin regex `/IDENTITY VERIFIED:\s*I am\s+(orchestrator|plankestrator)/i` (L892). Conforms to ARCHITECTURE.md §10 format. Required on **every** response (L33: "Every response MUST start with this exact first line") — satisfies the "identity line every turn" requirement.
- ✅ Fatal-refusal clause present (L31).
- ⚠️ Forbidden vocab: see Issue #5 (`"## PLAN"` / `"# Implementation Plan"` literals on L109).
- ✅ Legacy IDENTITY PROBE step fully removed; probe agents remain only in the routing table (needed for the plugin's `IDENTITY_PROBE_AGENTS` JSON-gate exception, L68–71).

### plankestrator.md

- ✅ RUNTIME IDENTITY block (L21–29): name, mode, 9-agent routing table, scopes — all match plugin and ARCHITECTURE.md.
- ✅ Identity line (L36): `✓ IDENTITY VERIFIED: I am plankestrator. I am NOT orchestrator. ...` — matches plugin regex; explicitly required "every turn, no exceptions" (L33).
- ✅ Fatal-refusal clause present (L31).
- ✅ No forbidden vocabulary anywhere in the file.
- ✅ Legacy probe step removed; explicit prohibition against describing itself as "Conductor" / "Task classifier" (L117) reinforces the lock.

## 4. State Machine Coherence

### orchestrator.md

- ✅ Single `## TURN ALGORITHM` section (L63–78); no duplicate state machine descriptions anywhere in the file.
- ✅ Deterministic flow: Turn 1 CLASSIFY → Turns 2..N EXECUTE PIPELINE (fixed pipeline, `next_agent` = next element) → completion turn (`next_agent: null` + one-line summary, L76).
- ✅ Only two sanctioned mutations: one-time BUGFIX continuation (L54–57) and the rework loop (L59) — both also sanctioned by ARCHITECTURE.md.
- ✅ No `state` field — correct, the plugin does not require one for orchestrator.

### plankestrator.md

- ✅ Single `## TURN ALGORITHM` section (L54–76); no duplicates.
- ✅ Deterministic state mapping (L65–68): writer agent → `EXECUTE`; reviewer agent → `REVIEW`; Turn 1 → `CLASSIFY`; pipeline exhausted → `COMPLETE` (L73–76). Exactly the four plugin-valid states, each with an unambiguous trigger.
- ✅ "A subagent result arriving is your next turn — advance one pipeline element, don't analyze" (L71) prevents re-classification drift.
- ✅ No contradictions with the plugin: plugin validates `state` values only, and all four emitted values are in `VALID_VALUES.plankestrator.state`.

## 5. Prohibitions Completeness

### orchestrator.md (L118–125)

| Rule | Status |
|---|---|
| No edit/write/patch/bash/webfetch/question | ✅ (L120) |
| No self-work (investigating bugs, reading code for context, explaining root causes) | ✅ (L121) |
| No prose between identity line and JSON; no analysis after ack | ✅ (L122) |
| No pipeline changes after Turn 1 (except BUGFIX continuation + rework loop) | ✅ (L123) |
| No read/glob/grep during pipeline execution (Turns 2..N) | ✅ (L124) — stricter than plankestrator, appropriate |
| No routing to plankestrator / outside routing table | ✅ (L125) |
| No skipping reviewers | ⚠️ Implicit only — dev-reviewer/consistency-checker are pipeline elements protected by L123, but there is no explicit "reviewers are mandatory" rule like plankestrator has (minor, see Recommendations) |
| One Task call per turn | ⚠️ Implicit (turn algorithm structure), not stated as a prohibition (minor) |

### plankestrator.md (L108–117)

| Rule | Status |
|---|---|
| No edit/write/patch/bash/webfetch | ✅ (L110) |
| No self-work (no plan content / research findings in own message text) | ✅ (L111) |
| No skipping reviewers (mandatory pipeline elements) | ✅ (L112, also L52) |
| One Task call per turn | ✅ (L113) |
| No pipeline changes after Turn 1 / no re-classification | ✅ (L114) |
| No prose between identity line and JSON / between JSON and Task | ✅ (L115) |
| No routing to orchestrator / outside routing table | ✅ (L116) |
| No cross-identity self-description | ✅ (L117) |

plankestrator's PROHIBITIONS are fully complete. orchestrator's are complete on all critical rules but lack two explicit statements that plankestrator has.

## 6. Frontmatter vs opencode.json

| Check | orchestrator | plankestrator |
|---|---|---|
| `mode: primary` frontmatter = JSON | ✅ both `primary` | ✅ both `primary` |
| `model` in frontmatter only (`bifrost-litellm/QWEN3.7-plus`), absent from JSON agent section | ✅ no dead config | ✅ no dead config |
| `temperature: 0.1` in both | ✅ | ✅ |
| No `prompt` field in JSON (markdown body wins) | ✅ | ✅ |
| edit/write/patch/bash/webfetch denied in both layers | ✅ | ✅ |
| read/grep/glob allowed in both layers | ✅ | ✅ |
| JSON `task` allowlist = plugin routing table | ✅ exact 24-agent match (plus explicit `plankestrator-identity-probe: deny`) | ❌ **JSON allowlist (L1428–1443) includes `view-image`, `generate-image`, `generate-image-gpt` — none are in the plugin's plankestrator routing table or the .md `OPENCODE_ROUTING_TABLE`** (Issue #2) |
| `question` / `todowrite` | ❌ frontmatter **and** JSON say `todowrite: allow`, `question: deny` — but ARCHITECTURE.md lockdown table (L166–178) says `todowrite: ❌ deny` for both primaries (Issue #1) | ❌ frontmatter **and** JSON say `todowrite: allow`, `question: allow` — ARCHITECTURE.md says both `❌ deny` (Issue #1) |

**Additional contradiction:** the plugin runtime gate (`PRIMARY_AGENT_ALLOWED_TOOLS = {task, read, glob, grep}`, L466) blocks `todowrite` and `question` for locked primary agents with a thrown error — so the config *grants* tools that the plugin then *blocks at runtime*. Meanwhile the global `AGENTS.md` tool-allowance table lists `todowrite, question` as allowed for primary agents, siding with the config against ARCHITECTURE.md. Three layers disagree (details in Issue #1).

**Same contradiction class, additional tools (reviewer addendum):** both opencode.json primary sections also grant `unity-mcp.*` and seven `serena_*` tools (orchestrator L1232–1239, plankestrator L1420–1427). None are in `PRIMARY_AGENT_ALLOWED_TOOLS`, so the plugin hard gate blocks every one of them at runtime for locked primaries. The project `AGENTS.md` globally mandates "Serena tools are PRIMARY for code operations", increasing the chance a primary agent actually attempts one and hits the `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception. ARCHITECTURE.md's lockdown table does not list serena/unity-mcp keys at all — the config grants ~9 dead tools per primary. Also: neither agent's PROHIBITIONS list mentions `todowrite` (orchestrator.md L120 bans `question` but not `todowrite`; plankestrator.md L110 bans neither), so the prompt gives no signal that these are off-limits. Finally, ARCHITECTURE.md L183 claims enforcement "layer 2" is a `tools:` frontmatter field — no such field exists in either agent file.

Note: ARCHITECTURE.md L187 justifies the v3 lockdown by saying the old config's `todowrite: "allow"` / `question: "allow"` caused primary agents to do work themselves — yet `todowrite: "allow"` is still present in both frontmatter blocks and both opencode.json sections today, and plankestrator still carries `question: "allow"` (orchestrator has `question: deny`).

## 7. Edge Cases

| Edge case | Finding | Status |
|---|---|---|
| BUGFIX two-stage (orchestrator) | Row 1 sends `["bugfix-triage"]` with `complexity: null`, `plan_exists: null`; continuation extends pipeline ONCE on `TRIAGE_RESULT: SIMPLE` → `["worker","utility"]` or `DEEP` → `["plan-bug","execute-bug","dev-reviewer","rework","consistency-checker","utility"]` (L45, L54–57). Plan-file handoff instructions included (L69, L75: "Write the plan to bug_plan.md" / "Read bug_plan.md"). Matches ARCHITECTURE.md L235–242 exactly. | ✅ |
| RESEARCH+PLAN (plankestrator) | Rows 5–6 correctly sequence research-writer-* → research-reviewer → plan-writer-* → plan-reviewer-*, with deterministic EXECUTE/REVIEW state per step. File instructions passed verbatim ("Write the research to RESEARCH.md" / "Write the plan to PLAN.md", L60). | ✅ |
| OUT OF SCOPE (orchestrator) | `type=null` for plan/research/investigate/design; outputs null-field JSON + "⚠️ OUT OF SCOPE: ... Please switch to plankestrator."; no Task call (L107). Also covers identity tests/small talk/meta. | ✅ |
| OUT OF SCOPE (plankestrator) | `type=null` for implement/fix/bug/deploy/docs/run-tests keywords; null-field JSON + "⚠️ OUT OF SCOPE: ... Please switch to orchestrator for: BUGFIX, DEVOPS, DEV, DOCS tasks."; no Task call (L102). | ✅ |
| DEV COMPLEX without plan | Classification rule L116: `plan_exists=false + complexity=COMPLEX` → OUT OF SCOPE to plankestrator. But pipeline row 5 says `plan_exists: any` — row 5 is in practice only reachable with `plan_exists=true`. The table's "any" is misleading (Issue #6). | ⚠️ |
| SUPERCOMPLEX step counting | orchestrator may `read` the plan file once to count steps — explicitly the only sanctioned direct file read (L114). Consistent with ARCHITECTURE.md trigger conditions (L276–278) and the "SUPERCOMPLEX beats plan_exists→SIMPLE" override (L284). | ✅ |
| JSON-before-Task gate | Both files mandate identity line → JSON → Task ordering, satisfying the plugin's `hasOutputtedJSON` gate (L602–617). First-call grace period is a plugin-side safety net, not relied upon by the prompts. | ✅ |

## Issues Found

1. **Permission-layer contradiction on `todowrite`/`question` (medium severity).** ARCHITECTURE.md "Primary Agent Tool Lockdown (v3)" (L166–178) and its rationale (L187) mandate `todowrite: deny` and `question: deny` for both primary agents. Actual state: both frontmatter blocks and both opencode.json agent sections set `todowrite: allow`; plankestrator additionally sets `question: allow`. The global `AGENTS.md` allowance table also lists them as allowed. The plugin runtime gate (L466–510) blocks both tools for locked primaries anyway — so the model sees the tools in its toolset, calls one, and gets a hard `⛔ PRIMARY AGENT FORBIDDEN ACTION TOOL` exception. Config, docs, and runtime disagree. **Scope note (reviewer addendum):** the same contradiction applies to the `unity-mcp.*` and `serena_*` grants in both opencode.json primary sections — config-allowed, plugin-blocked, absent from ARCHITECTURE.md's table. Compounding this, neither PROHIBITIONS list names `todowrite` (and plankestrator's names neither `todowrite` nor `question`), so the prompts provide no defense-in-depth against calling them.

2. **plankestrator opencode.json task allowlist exceeds its routing table (medium-high severity).** `opencode.json` L1440–1442 grants plankestrator `task` access to `view-image`, `generate-image`, `generate-image-gpt`. None of these are in the plugin's `ROUTING_TABLES.plankestrator` (9 agents) or in plankestrator.md's `OPENCODE_ROUTING_TABLE`. All three **are** in orchestrator's whitelist — so if plankestrator ever calls one, the plugin's routing fallback (L643–656) matches the *other* agent's table and **mutates `currentAgent` to `orchestrator`**, silently rebinding the session identity. **Precision note (reviewer addendum):** the fallback mutates only `currentAgent`, not `lockedAgentName` — the hard action-tool gate and vocab check still reference the original agent. The practical damage remains: all subsequent Task calls validate against orchestrator's 24-agent routing table (plankestrator could then legally call `worker`, `bugfix-triage`, etc.), and plankestrator's JSON gets validated against orchestrator's schema (missing `plan_exists`/`plan_source` → persistent "INVALID JSON OUTPUT" warnings).

3. **Plugin routing fallback ignores the identity lock (medium severity, plugin-side).** The fallback at `tool.execute.before` L643–656 switches `currentAgent` when the target subagent is in the other primary's whitelist, without checking `identityLocked`. This contradicts the v3 lock guarantee ("the agent cannot be re-bound after this point", ARCHITECTURE.md L541) that the `message.updated` drift handler (L337–353) does enforce. Issue #2 is the realistic trigger for this latent bug.

4. **orchestrator.md rework-loop note omits rows 4 and 6 (low-medium severity).** L59 scopes the rework loop to "rows 1-DEEP, 5, 8". ARCHITECTURE.md gives a rework loop to DEV SIMPLE with-plan (row 4 — "task returns to **worker** for fixes", L257) and to DEV SUPERCOMPLEX (row 6 — per-step loop "returns to `rework`", L282). The parenthetical "(or the agent named in its `escalate_to`)" partially covers row 4's worker target, but a literal reading of the note excludes both rows from looping at all.

5. **orchestrator.md L109 contains literal forbidden-vocabulary tokens (low severity).** The `plan_exists=true` detection rule quotes `"## PLAN"` and `"# Implementation Plan"` — both on the orchestrator `FORBIDDEN_VOCAB` list. If the model cites this rule in a message, the plugin logs a false-positive `FORBIDDEN VOCABULARY DETECTED` error (logged only, not thrown).

6. **orchestrator.md row 5 `plan_exists: any` contradicts classification rule L116 (trivial).** L116 routes `plan_exists=false + COMPLEX` to plankestrator as OUT OF SCOPE, so row 5 (DEV COMPLEX) is unreachable with `plan_exists=false`. The cell should read `true`, not `any`.

## Recommendations

1. **Align the `todowrite`/`question` layers (Issue #1).** Decide the intended policy and apply it uniformly. Recommended: set `todowrite: deny` and `question: deny` in both frontmatter blocks and both opencode.json agent sections (matching ARCHITECTURE.md and the plugin gate), and remove them from the global `AGENTS.md` allowed list. If they are intentionally kept, update ARCHITECTURE.md's lockdown table and add them to `PRIMARY_AGENT_ALLOWED_TOOLS` in the plugin instead. **Also (reviewer addendum):** remove the `unity-mcp.*` and `serena_*` keys from both primary sections of opencode.json (primaries should delegate those operations via Task), add `todowrite`/`question` to both PROHIBITIONS lists (orchestrator.md already bans `question`; add `todowrite`; plankestrator.md needs both), and correct ARCHITECTURE.md L183 — either drop the fictional `tools:` frontmatter "layer 2" or actually add the field.
2. **Trim plankestrator's JSON task allowlist (Issue #2).** Remove `view-image`, `generate-image`, `generate-image-gpt` from `opencode.json` L1440–1442 so the JSON allowlist equals the plugin routing table (9 agents). If image generation from planning sessions is a desired feature, add those agents to `ROUTING_TABLES.plankestrator` in the plugin *and* to plankestrator.md's `OPENCODE_ROUTING_TABLE` instead.
3. **Guard the routing fallback with the identity lock (Issue #3).** In `workflow-enforcement.ts` L643, skip the agent-switch when `identityLocked === true` and throw the routing-table violation instead. This makes the v3 lock airtight across both enforcement hooks.
4. **Fix the rework-loop note (Issue #4).** Change orchestrator.md L59 to cover all rows containing `consistency-checker`: e.g. "Rework loop (rows 1-DEEP, 4, 5, 6, 8): if consistency-checker reports critical issues, return to the agent named in its `escalate_to` (default `rework`; `worker` for row 4), max 3 iterations, then `utility`."
5. **Defuse the literal tokens (Issue #5).** Reword orchestrator.md L109 to avoid the exact strings, e.g. `a top-level markdown PLAN heading ("## P"+"LAN" style)` or describe it as "an H2 heading whose text is PLAN". Functionally identical, no false-positive vocab hits.
6. **Correct row 5's `plan_exists` cell (Issue #6).** Change `any` → `true` in orchestrator.md L49 to reflect the L116 classification rule.
7. **Optional hardening (orchestrator prohibitions).** Add two explicit bullets mirroring plankestrator: "No skipping dev-reviewer / consistency-checker — they are mandatory pipeline elements" and "No more than ONE Task call per turn."

---
*Research conducted by direct file analysis of all five sources listed above. No external sources required — this was a closed-system consistency validation.*
