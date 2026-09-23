#!/usr/bin/env python3
"""
migrate.py - POSIX mirror of migrate.ps1

Migrate ONE agent to a new model across all 7 synchronized places:
live+deploy frontmatter, ARCHITECTURE.md x3 (Subagent Models + Model Roles),
MCP_SETUP.md x2 (Models Distribution + Full Table + Summary row).
Two-phase all-or-nothing write; validates the model key against live
opencode.json provider models; SHA256-verifies mirrors; optional commit+push.

Usage:
    python migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --plan-only
    python migrate.py --agent utility --model bifrost-litellm/qwen3.8-max --apply
        [--role R --tier T] [--commit] [--push]

Output:
    STATUS:/PLAN:/WARN:/BLOCK:/EDITED:/VERIFY:/COMMITTED:/PUSHED:/ERROR: lines

Exit codes:
    0 success / plan-only / no changes
    2 usage/environment error
    3 gate block (zero writes)
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

LINE_SPLIT = re.compile(r'(\r\n|\r|\n)')
ROLE_ROW = re.compile(r'^\| (.+?) \| (.+?) \| (.+?) \| (.*?) \|$')
DIST_ROW = re.compile(r'^\| `(.+?)` \| (.+?) \| (\d+) \| (.*?) \|$')
SECTION_END_KONTROL = r'^\u041A\u043E\u043D\u0442\u0440\u043E\u043B\u044C \u0441\u0443\u043C\u043C\u044B:'


def read_raw(p):
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


def write_raw(p, text, bom):
    Path(p).write_bytes(text.encode('utf-8-sig' if bom else 'utf-8'))


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def repo_root(script_dir):
    """<repo>/.opencode/skills/<skill>/scripts -> <repo>."""
    root = script_dir.resolve().parents[3]
    if (root / 'deploy-package').exists():
        return root
    try:
        out = subprocess.check_output(
            ['git', '-C', str(script_dir), 'rev-parse', '--show-toplevel'],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
        if out:
            return Path(out)
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return root


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], capture_output=True, text=True)


def split_model_key(full):
    if not full:
        return None
    idx = full.find('/')
    if idx < 1 or idx >= len(full) - 1:
        return None
    return full[:idx], full[idx + 1:]


def get_fm_model(text):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    mm = re.search(r'(?m)^model:[ \t]*(.*)$', m.group(1))
    if not mm:
        return None
    return mm.group(1).strip()


def set_fm_model(text, new):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    block = m.group(1)
    block2 = re.sub(r'(?m)^(model:.*?)(\r?)$', lambda mm: f'model: {new}' + mm.group(2),
                    block, count=1)
    return text[:m.start(1)] + block2 + text[m.end(1):]


def split_lines_keep_eol(text):
    """[content, eol, content, eol, ...] — content at even indices."""
    return LINE_SPLIT.split(text)


def find_section_span(lines, start_pat, end_pat):
    start = -1
    for i in range(0, len(lines), 2):
        if re.match(start_pat, lines[i]):
            start = i
            break
    if start < 0:
        return None
    for j in range(start + 2, len(lines), 2):
        if re.match(end_pat, lines[j]):
            return start, j
    return None


def split_tokens(cell):
    if not cell or not cell.strip():
        return []
    return [t.strip() for t in cell.split(',') if t.strip()]


def get_eol(lines, content_idx):
    if content_idx + 1 < len(lines):
        return lines[content_idx + 1]
    return ''


class EditError(Exception):
    pass


def edit_subagent_models_row(text, agent, new_model, old_model):
    """Returns (new_text, old_value, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^## Subagent Models', r'^## ')
    if not span:
        raise EditError('anchor: ## Subagent Models section not found')
    pat = re.compile(r'^\| ' + re.escape(agent) + r' \| (.+?) \|$')
    hits = [(i, m) for i in range(span[0], span[1], 2) for m in [pat.match(lines[i])] if m]
    if len(hits) != 1:
        raise EditError(f"anchor: Subagent Models row for '{agent}' found {len(hits)} times (expected 1)")
    idx, m = hits[0]
    old = m.group(1).strip()
    if old != old_model:
        warns.append(f'WARN:subagent-models row drift (row={old} frontmatter={old_model})')
    lines[idx] = f'| {agent} | {new_model} |'
    return ''.join(lines), old, warns


def edit_model_roles(text, agent, new_model, role, tier):
    """Returns (new_text, old_role, new_role_name, tier_map, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^## Model Roles', SECTION_END_KONTROL)
    if not span:
        raise EditError('anchor: ## Model Roles section not found')

    def parse_rows():
        rows = []
        for i in range(span[0], span[1], 2):
            m = ROLE_ROW.match(lines[i])
            if m and m.group(1).strip() != 'Role':
                rows.append({'idx': i, 'role': m.group(1).strip(), 'model': m.group(2).strip(),
                             'tier': m.group(3).strip(), 'agents': m.group(4).strip()})
        return rows

    rows = parse_rows()
    if not rows:
        raise EditError('anchor: Model Roles data rows not found')

    # REMOVE the agent from its current row (token-exact match).
    hits = [r for r in rows if agent in split_tokens(r['agents'])]
    if len(hits) == 0:
        raise EditError(f"agent '{agent}' not found in any Model Roles row")
    if len(hits) > 1:
        raise EditError(f"agent '{agent}' duplicated across {len(hits)} Model Roles rows")
    old_row = hits[0]
    old_role = old_row['role']
    rest = [t for t in split_tokens(old_row['agents']) if t != agent]
    if not rest:
        warns.append(f"WARN:role '{old_role}' now has 0 agents")
    lines[old_row['idx']] = (f"| {old_row['role']} | {old_row['model']} | {old_row['tier']} "
                             f"| {', '.join(rest)} |")

    # ADD the agent to the row with the new model (or create a new row).
    cands = [r for r in rows if r['model'] == new_model]
    new_role_name = None
    if len(cands) == 1:
        if role and role != cands[0]['role']:
            raise EditError(f"-Role '{role}' does not match the single role row '{cands[0]['role']}'")
        nr = cands[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = (f"| {nr['role']} | {nr['model']} | {nr['tier']} "
                            f"| {', '.join(toks)} |")
        new_role_name = nr['role']
    elif len(cands) > 1:
        if not role:
            raise EditError('ambiguous role rows: ' + ', '.join(r['role'] for r in cands))
        m2 = [r for r in cands if r['role'] == role]
        if len(m2) != 1:
            raise EditError(f"-Role '{role}' not found among candidate rows: "
                            + ', '.join(r['role'] for r in cands))
        nr = m2[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = (f"| {nr['role']} | {nr['model']} | {nr['tier']} "
                            f"| {', '.join(toks)} |")
        new_role_name = nr['role']
    else:
        if not role or not tier:
            raise EditError('model has no role row; --role and --tier required. Available roles: '
                            + ', '.join(r['role'] for r in rows))
        warns.append(f"WARN:new role '{role}' requires CHANGELOG justification")
        last = rows[-1]
        eol = get_eol(lines, last['idx']) or '\r\n'
        insert_at = last['idx'] + 2
        lines[insert_at:insert_at] = [f'| {role} | {new_model} | {tier} | {agent} |', eol]
        new_role_name = role

    # Rebuild agent->tier map (bound +2 covers an inserted row).
    tier_map = {}
    bound = min(span[1] + 2, len(lines))
    for i in range(span[0], bound, 2):
        m = ROLE_ROW.match(lines[i])
        if m and m.group(1).strip() != 'Role':
            for t in split_tokens(m.group(4)):
                tier_map[t] = m.group(3).strip()
    return ''.join(lines), old_role, new_role_name, tier_map, warns


def edit_distribution(text, agent, old_short, new_short):
    """Returns (new_text, shorts, old_count_after, new_count_after, row_deleted, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    span = find_section_span(lines, r'^### Models Distribution', r'^### ')
    if not span:
        raise EditError('anchor: ### Models Distribution section not found')

    def parse_rows(bound_extra=0):
        rows = []
        bound = min(span[1] + bound_extra, len(lines))
        for i in range(span[0], bound, 2):
            m = DIST_ROW.match(lines[i])
            if m and m.group(1).strip() != 'Model':
                rows.append({'idx': i, 'short': m.group(1).strip(), 'provider': m.group(2).strip(),
                             'count': int(m.group(3)), 'agents': m.group(4).strip()})
        return rows

    rows = parse_rows()
    if not rows:
        raise EditError('anchor: Models Distribution data rows not found')

    old_rows = [r for r in rows if r['short'] == old_short]
    if len(old_rows) != 1:
        raise EditError(f"anchor: Distribution row for '{old_short}' found {len(old_rows)} times (expected 1)")
    old_row = old_rows[0]
    old_toks = split_tokens(old_row['agents'])
    if agent not in old_toks:
        warns.append(f"WARN:distribution drift (agent '{agent}' not in row '{old_short}')")
    rest = [t for t in old_toks if t != agent]
    row_deleted = False
    if not rest:
        del lines[old_row['idx']:old_row['idx'] + 2]
        row_deleted = True
        rows = parse_rows(bound_extra=2)
    else:
        lines[old_row['idx']] = (f"| `{old_row['short']}` | {old_row['provider']} | {len(rest)} "
                                 f"| {', '.join(rest)} |")
    old_count_after = len(rest)

    if not rows:
        raise EditError('anchor: Models Distribution has no remaining rows after edit')

    new_rows = [r for r in rows if r['short'] == new_short]
    if len(new_rows) == 1:
        nr = new_rows[0]
        toks = split_tokens(nr['agents'])
        if agent not in toks:
            toks.append(agent)
        lines[nr['idx']] = (f"| `{nr['short']}` | {nr['provider']} | {len(toks)} "
                            f"| {', '.join(toks)} |")
        new_count_after = len(toks)
    elif len(new_rows) == 0:
        last = rows[-1]
        eol = get_eol(lines, last['idx']) or '\r\n'
        insert_at = last['idx'] + 2
        lines[insert_at:insert_at] = [f'| `{new_short}` | bifrost-litellm | 1 | {agent} |', eol]
        new_count_after = 1
    else:
        raise EditError(f"anchor: Distribution row for '{new_short}' found {len(new_rows)} times (expected 1)")

    shorts = [r['short'] for r in parse_rows(bound_extra=2)]
    return ''.join(lines), shorts, old_count_after, new_count_after, row_deleted, warns


def edit_full_table_row(text, agent, old_model, new_model):
    """Returns (new_text, warns)."""
    warns = []
    lines = split_lines_keep_eol(text)
    pat = re.compile(r'^\| \*\*' + re.escape(agent) + r'\*\* \|')
    hits = [i for i in range(0, len(lines), 2) if pat.match(lines[i])]
    if len(hits) != 1:
        raise EditError(f"anchor: Full Table row for '{agent}' found {len(hits)} times (expected 1)")
    idx = hits[0]
    cells = lines[idx].split('|')
    if len(cells) < 5:
        raise EditError(f"anchor: Full Table row for '{agent}' has too few cells")
    cur = cells[3].strip()
    if cur != old_model:
        warns.append(f'WARN:full-table model drift (cell={cur} expected={old_model})')
    cells[3] = f' {new_model} '
    lines[idx] = '|'.join(cells)
    return ''.join(lines), warns


def edit_summary_models_row(text, shorts):
    """Returns new_text."""
    lines = split_lines_keep_eol(text)
    pat = re.compile(r'^\| Models \| \d+ \| bifrost-litellm \(.*\) \|$')
    hits = [i for i in range(0, len(lines), 2) if pat.match(lines[i])]
    if len(hits) != 1:
        raise EditError(f'anchor: Summary Models row found {len(hits)} times (expected 1)')
    idx = hits[0]
    lines[idx] = f"| Models | {len(shorts)} | bifrost-litellm ({', '.join(shorts)}) |"
    return ''.join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agent', required=True)
    parser.add_argument('--model', required=True)
    parser.add_argument('--plan-only', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--commit', action='store_true')
    parser.add_argument('--push', action='store_true')
    parser.add_argument('--role', default='')
    parser.add_argument('--tier', default='')
    args = parser.parse_args()

    if args.plan_only and args.apply:
        print('ERROR:--plan-only and --apply are mutually exclusive')
        sys.exit(2)
    if args.tier and not args.role:
        print('ERROR:--tier requires --role')
        sys.exit(2)
    if args.tier and args.tier not in ('top', 'mid', 'low'):
        print(f"ERROR:--tier must be one of: top, mid, low (got '{args.tier}')")
        sys.exit(2)
    if not args.plan_only and not args.apply:
        args.plan_only = True
    if args.push and not args.commit:
        print('ERROR:--push requires --commit')
        sys.exit(2)

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'
    live_fm = live_dir / 'agents' / f'{args.agent}.md'
    deploy_fm = root / 'deploy-package' / 'agents' / f'{args.agent}.md'
    arch_paths = [root / 'ARCHITECTURE.md',
                  root / 'opencode-config' / 'ARCHITECTURE.md',
                  root / 'deploy-package' / 'project-files' / 'ARCHITECTURE.md']
    mcp_paths = [root / 'MCP_SETUP.md',
                 root / 'deploy-package' / 'project-files' / 'MCP_SETUP.md']

    for t in [live_fm, deploy_fm] + arch_paths + mcp_paths:
        if not t.is_file():
            print(f'ERROR:agent target file not found: {t}')
            sys.exit(2)

    def rel_path(p):
        p = p.resolve()
        try:
            return 'live:' + p.relative_to(live_dir.resolve()).as_posix()
        except ValueError:
            pass
        try:
            return p.relative_to(root.resolve()).as_posix()
        except ValueError:
            return str(p)

    if args.agent in ('orchestrator', 'plankestrator'):
        print('BLOCK:primary agent migration is manual (orchestrator/plankestrator — '
              'see ARCHITECTURE Model Roles / Identity Lock)')
        sys.exit(3)

    key_parts = split_model_key(args.model)
    if not key_parts:
        print(f"ERROR:model key must be provider/model-key (got '{args.model}')")
        sys.exit(2)
    provider, key = key_parts
    if provider != 'bifrost-litellm':
        print(f"BLOCK:provider '{provider}' is not bifrost-litellm")
        sys.exit(3)

    live_cfg = live_dir / 'opencode.json'
    if not live_cfg.is_file():
        print(f'ERROR:live opencode.json not found: {live_cfg}')
        sys.exit(2)
    try:
        cfg_text, _ = read_raw(live_cfg)
        cfg = json.loads(cfg_text)
        models = (cfg.get('provider', {}).get(provider) or {}).get('models')
        model_exists = isinstance(models, dict) and key in models
    except (ValueError, OSError) as e:
        print(f'BLOCK:live opencode.json is not valid JSON: {e}')
        sys.exit(3)
    if not model_exists:
        print(f'BLOCK:model not found in provider models: {args.model}')
        sys.exit(3)

    live_fm_text, live_fm_bom = read_raw(live_fm)
    deploy_fm_text, deploy_fm_bom = read_raw(deploy_fm)
    arch_raws = [read_raw(p) for p in arch_paths]
    mcp_raws = [read_raw(p) for p in mcp_paths]

    old_model = get_fm_model(live_fm_text)
    if not old_model:
        print('BLOCK:frontmatter without model: line')
        sys.exit(3)
    if old_model == args.model:
        print('STATUS:NO_CHANGES')
        sys.exit(0)
    old_parts = split_model_key(old_model)
    if not old_parts:
        print(f"BLOCK:existing frontmatter model key malformed: '{old_model}'")
        sys.exit(3)
    old_short = old_parts[1]
    new_short = key

    print(f'STATUS:MIGRATE_START agent={args.agent} old={old_model} new={args.model}')

    # Pre-gate: target FM pair + ARCHITECTURE x3 + MCP_SETUP x2 in sync
    drifts = []
    if sha256_file(live_fm) != sha256_file(deploy_fm):
        drifts.append('frontmatter pair (live vs deploy)')
    if len({sha256_file(p) for p in arch_paths}) > 1:
        drifts.append('ARCHITECTURE.md x3')
    if len({sha256_file(p) for p in mcp_paths}) > 1:
        drifts.append('MCP_SETUP.md x2')
    if drifts:
        if args.apply:
            print(f"BLOCK:mirrors drifted — run config-sync first ({'; '.join(drifts)})")
            sys.exit(3)
        for d in drifts:
            print(f'WARN:mirror drift ({d}) — run config-sync before apply')

    # Compute ALL edits in memory (two-phase: zero writes on any error)
    pending = []   # (path, new_text, bom, rel)
    warns = []
    plan_lines = []

    try:
        new_live = set_fm_model(live_fm_text, args.model)
        if new_live is None:
            raise EditError('anchor: frontmatter model: line not found (live)')
        pending.append((live_fm, new_live, live_fm_bom, rel_path(live_fm)))
        plan_lines.append(f'PLAN:{rel_path(live_fm)} old={old_model} new={args.model}')

        new_deploy = set_fm_model(deploy_fm_text, args.model)
        if new_deploy is None:
            raise EditError('anchor: frontmatter model: line not found (deploy)')
        pending.append((deploy_fm, new_deploy, deploy_fm_bom, rel_path(deploy_fm)))
        plan_lines.append(f'PLAN:{rel_path(deploy_fm)} old={old_model} new={args.model}')

        roles_info = None
        for i, path in enumerate(arch_paths):
            text = arch_raws[i][0]
            t1, row_old, w = edit_subagent_models_row(text, args.agent, args.model, old_model)
            warns += w
            t2, old_role, new_role_name, tier_map, w = edit_model_roles(
                t1, args.agent, args.model, args.role, args.tier)
            warns += w
            pending.append((path, t2, arch_raws[i][1], rel_path(path)))
            plan_lines.append(f'PLAN:{rel_path(path)} subagent_models_row old={row_old} new={args.model}')
            roles_info = (old_role, new_role_name, tier_map)
        if roles_info:
            plan_lines.append(f'PLAN:role {args.agent} {roles_info[0]} -> {roles_info[1]}')

        dist_info = None
        for i, path in enumerate(mcp_paths):
            text = mcp_raws[i][0]
            t1, shorts, old_cnt, new_cnt, row_deleted, w = edit_distribution(
                text, args.agent, old_short, new_short)
            warns += w
            t2, w = edit_full_table_row(t1, args.agent, old_model, args.model)
            warns += w
            t3 = edit_summary_models_row(t2, shorts)
            pending.append((path, t3, mcp_raws[i][1], rel_path(path)))
            plan_lines.append(f'PLAN:{rel_path(path)} distribution/full_table/summary')
            dist_info = (shorts, old_cnt, new_cnt, row_deleted)
        if dist_info:
            detail = f'PLAN:distribution {old_short} count->{dist_info[1]}; {new_short} count->{dist_info[2]}'
            if dist_info[3]:
                detail += f" (row '{old_short}' deleted)"
            plan_lines.append(detail)

        if roles_info and roles_info[2]:
            rank = {'top': 3, 'mid': 2, 'low': 1}
            for planner, executor in (('plan-bug', 'execute-bug'),
                                      ('dev-planner', 'dev-professor'),
                                      ('docs-planner', 'docs-writer')):
                tm = roles_info[2]
                if planner in tm and executor in tm:
                    if rank[tm[planner]] < rank[tm[executor]]:
                        warns.append(f'WARN:prewalk inversion ({planner} tier={tm[planner]} '
                                     f'< {executor} tier={tm[executor]})')
    except EditError as e:
        print(f'BLOCK:{e}')
        sys.exit(3)

    for pl in plan_lines:
        print(pl)
    for w in warns:
        print(w)

    if args.plan_only:
        print('STATUS:PLAN_ONLY')
        sys.exit(0)

    print('STATUS:APPLY_START')
    for path, new_text, bom, rel in pending:
        write_raw(path, new_text, bom)
        print(f'EDITED:{rel}')

    # Verify (re-read from disk)
    try:
        cfg_text2, _ = read_raw(live_cfg)
        json.loads(cfg_text2)
    except (ValueError, OSError) as e:
        print(f'ERROR:opencode.json no longer parses: {e}')
        sys.exit(3)
    if sha256_file(live_fm) == sha256_file(deploy_fm):
        print('VERIFY:frontmatter identical')
    else:
        print('ERROR:SHA256 mismatch: frontmatter pair')
        sys.exit(3)
    if len({sha256_file(p) for p in arch_paths}) == 1:
        print('VERIFY:architecture identical')
    else:
        print('ERROR:SHA256 mismatch: ARCHITECTURE.md x3')
        sys.exit(3)
    if len({sha256_file(p) for p in mcp_paths}) == 1:
        print('VERIFY:mcp-setup identical')
    else:
        print('ERROR:SHA256 mismatch: MCP_SETUP.md x2')
        sys.exit(3)

    print('WARN:restart required (config is read at session start — new model takes effect in a NEW opencode session)')
    print('WARN:CHANGELOG.md [Unreleased] entry is a manual step')

    if args.commit:
        name_res = git(root, 'config', 'user.name')
        email_res = git(root, 'config', 'user.email')
        git_name = name_res.stdout.strip()
        git_email = email_res.stdout.strip()
        if not git_name or not git_email:
            print(f"ERROR: git identity missing (user.name='{git_name}' user.email='{git_email}') "
                  "- set it with: git config user.name \"...\"; git config user.email \"...\"")
            sys.exit(3)
        commit_msg = f'refactor(models): {args.agent} {old_model} -> {args.model}'
        import tempfile
        tmp_dir = Path(tempfile.gettempdir()) / 'opencode'
        tmp_dir.mkdir(parents=True, exist_ok=True)
        msg_file = tmp_dir / 'commit-msg-models.txt'
        msg_file.write_text(commit_msg, encoding='utf-8')
        print('STATUS:COMMIT_START')
        repo_rel = [f'deploy-package/agents/{args.agent}.md',
                    'ARCHITECTURE.md',
                    'opencode-config/ARCHITECTURE.md',
                    'deploy-package/project-files/ARCHITECTURE.md',
                    'MCP_SETUP.md',
                    'deploy-package/project-files/MCP_SETUP.md']
        add_res = git(root, 'add', *repo_rel)
        if add_res.returncode != 0:
            print(f'ERROR:git add failed: {add_res.stderr}')
            sys.exit(3)
        res = git(root, 'commit', '-F', str(msg_file))
        if res.returncode != 0:
            print(f'ERROR:git commit failed: {res.stderr}')
            sys.exit(3)
        commit_hash = git(root, 'rev-parse', 'HEAD').stdout.strip()
        print(f'COMMITTED:hash={commit_hash} msg={commit_msg}')
        if args.push:
            print('STATUS:PUSH_START')
            branch = git(root, 'branch', '--show-current').stdout.strip()
            if not branch:
                print('ERROR: could not determine current branch')
                sys.exit(3)
            res = git(root, 'push', 'origin', branch)
            if res.returncode != 0:
                print(f'ERROR:git push failed: {res.stderr}')
                sys.exit(3)
            print(f'PUSHED:branch={branch}')

    print('STATUS:SUCCESS')
    sys.exit(0)


if __name__ == '__main__':
    main()
