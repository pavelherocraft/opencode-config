#!/usr/bin/env python3
"""
report.py - POSIX mirror of report.ps1

Fast LLM-free fleet report: per-agent table (frontmatter model, Model Roles
role/tier, mode, flattened permissions, routing membership orch/plan/both/
none) plus model-distribution and role-distribution summaries.

Usage:
    python report.py [--source live|deploy] [--format table|markdown|json]
                     [--agent NAME] [--role ROLE] [--model SUBSTR]
                     [--agents-dir DIR] [--arch PATH] [--config PATH]

Output:
    STATUS:/WARN:/ERROR:/MODEL_DIST:/ROLE_DIST:/SUMMARY: lines or a JSON document

Exit codes:
    0 report generated (WARNs allowed)
    2 usage/environment error

No exit 3: a report never gates. Strictly read-only.
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def read_raw(p):
    """Byte-safe read: decode UTF-8 (strip BOM if present), report BOM state."""
    data = Path(p).read_bytes()
    bom = data.startswith(b'\xef\xbb\xbf')
    return data.decode('utf-8-sig' if bom else 'utf-8'), bom


def get_fm_model(text):
    m = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
    if not m:
        return None
    mm = re.search(r'(?m)^model:[ \t]*(.*)$', m.group(1))
    if not mm:
        return None
    return mm.group(1).strip()


def split_tokens(cell):
    if not cell or not cell.strip():
        return []
    return [t.strip() for t in cell.split(',') if t.strip()]


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


def get_section_text(text, start_pat, end_pat):
    m = re.search(start_pat, text, re.M)
    if not m:
        return None
    after = text[m.end():]
    e = re.search(end_pat, after, re.M)
    if e:
        return after[:e.start()]
    return after


def get_model_role_map(arch_text):
    sec = get_section_text(arch_text, r'^## Model Roles', r'^## ')
    if sec is None:
        return None
    amap = {}
    roles = []
    for ln in re.split(r'\r?\n', sec):
        if not ln.startswith('|'):
            continue
        cells = [c.strip() for c in ln.split('|')]
        if len(cells) < 5:
            continue
        r, m, t, ags = cells[1], cells[2], cells[3], cells[4]
        if not r or r == 'Role' or re.match(r'^-+$', r):
            continue
        if t not in ('top', 'mid', 'low'):
            continue
        roles.append({'role': r, 'model': m, 'tier': t})
        for a in split_tokens(ags):
            amap[a] = {'role': r, 'tier': t, 'arch_model': m}
    if not roles:
        return None
    return {'map': amap, 'roles': roles}


def get_whitelist_names(arch_text, primary):
    header_pat = r'^### ' + re.escape(primary) + r' Whitelist \(\d+ agents\)'
    hm = re.search(header_pat, arch_text, re.M)
    if not hm:
        return None
    after = arch_text[hm.end():]
    fp = re.search(r'(?m)^\|', after)
    if not fp:
        return []
    rest = after[fp.start():]
    blank = re.search(r'\r?\n[ \t]*\r?\n', rest)
    tbl = rest[:blank.start()] if blank else rest
    names = []
    for rm in re.finditer(r'(?m)^\|\s*\d+\s*\|\s*([^|]+?)\s*\|', tbl):
        names.append(rm.group(1).strip())
    return names


def get_task_allow_names(cfg, primary):
    try:
        node = cfg['agent'][primary]['permission']['task']
    except (KeyError, TypeError):
        return None
    if not node:
        return None
    return [k for k, v in node.items() if k != '*' and v == 'allow']


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


def format_agent_table(rows):
    cols = ['AGENT', 'MODEL', 'ROLE', 'TIER', 'MODE', 'ROUTE', 'PERMISSIONS']
    w = {c: len(c) for c in cols}
    for r in rows:
        for c in cols:
            if len(r[c]) > w[c]:
                w[c] = len(r[c])
    sep = '+' + '+'.join('-' * (w[c] + 2) for c in cols) + '+'
    lines = [sep]
    lines.append('| ' + ' | '.join(c.ljust(w[c]) for c in cols) + ' |')
    lines.append(sep)
    for r in rows:
        lines.append('| ' + ' | '.join(r[c].ljust(w[c]) for c in cols) + ' |')
    lines.append(sep)
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', choices=['live', 'deploy'], default='live')
    parser.add_argument('--format', choices=['table', 'markdown', 'json'], default='table')
    parser.add_argument('--agent', default='')
    parser.add_argument('--role', default='')
    parser.add_argument('--model', default='')
    parser.add_argument('--agents-dir', default='')
    parser.add_argument('--arch', default='')
    parser.add_argument('--config', default='')
    args = parser.parse_args()

    if args.agent and (args.role or args.model):
        print('ERROR:COMBINATION -Agent cannot be combined with -Role/-Model')
        sys.exit(2)
    if args.source != 'live' and args.agents_dir:
        print('ERROR:COMBINATION -Source and -AgentsDir are mutually exclusive')
        sys.exit(2)

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'

    if args.agents_dir:
        agents_dir = Path(args.agents_dir)
        if not agents_dir.is_absolute():
            agents_dir = root / agents_dir
    elif args.source == 'deploy':
        agents_dir = root / 'deploy-package' / 'agents'
    else:
        agents_dir = live_dir / 'agents'
    if not agents_dir.is_dir():
        print(f'ERROR:ENV agents dir not found: {agents_dir}')
        sys.exit(2)

    arch_path = Path(args.arch) if args.arch else root / 'ARCHITECTURE.md'
    if not arch_path.is_file():
        print(f'ERROR:ENV ARCHITECTURE.md not found: {arch_path}')
        sys.exit(2)
    arch_name = args.arch if args.arch else 'ARCHITECTURE.md'
    arch_text, _ = read_raw(arch_path)

    role_info = get_model_role_map(arch_text)
    if not role_info:
        print('ERROR:ANCHOR model_roles (## Model Roles table not parsed)')
        sys.exit(2)
    orch_names = get_whitelist_names(arch_text, 'orchestrator')
    if orch_names is None:
        print('ERROR:ANCHOR whitelist_orchestrator (### orchestrator Whitelist header not found)')
        sys.exit(2)
    plan_names = get_whitelist_names(arch_text, 'plankestrator')
    if plan_names is None:
        print('ERROR:ANCHOR whitelist_plankestrator (### plankestrator Whitelist header not found)')
        sys.exit(2)

    # Routing cross-check (opencode.json vs ARCHITECTURE whitelists)
    cfg_path = Path(args.config) if args.config else live_dir / 'opencode.json'
    cfg = None
    if cfg_path.is_file():
        try:
            cfg = json.loads(read_raw(cfg_path)[0])
        except (ValueError, OSError):
            cfg = None
    routing_warns = []
    if cfg is not None:
        for prim, arch_set in (('orchestrator', orch_names), ('plankestrator', plan_names)):
            json_set = get_task_allow_names(cfg, prim)
            if json_set is None:
                json_set = []
            arch_only = [n for n in arch_set if n not in json_set]
            json_only = [n for n in json_set if n not in arch_set]
            if arch_only or json_only:
                routing_warns.append(
                    'WARN:ROUTING_MISMATCH primary={0} arch_only=[{1}] json_only=[{2}]'.format(
                        prim, ','.join(arch_only), ','.join(json_only)))
    else:
        routing_warns.append('WARN:CROSSCHECK_SKIPPED reason=opencode.json missing/unparsable')

    # Scan agents
    files = sorted(agents_dir.glob('*.md'), key=lambda p: p.stem)
    if not files:
        print(f'ERROR:ENV agents dir empty: {agents_dir}')
        sys.exit(2)

    warnings = []
    all_rows = []
    routing_orch, routing_plan, routing_both, routing_none = [], [], [], []
    for f in files:
        name = f.stem
        text, _ = read_raw(f)
        model = get_fm_model(text)
        if not model:
            warnings.append(f'WARN:FM_NO_MODEL agent={name}')
            model = '<missing>'
        mode = 'subagent'
        fm = re.match(r'(?s)\A---\r?\n(.*?)\r?\n---', text)
        if fm:
            mm = re.search(r'(?m)^mode:[ \t]*(.*)$', fm.group(1))
            if mm and mm.group(1).strip():
                mode = mm.group(1).strip()
        perms = get_fm_permission_flat(text)
        role, tier = '<unmapped>', '?'
        if name in role_info['map']:
            ri = role_info['map'][name]
            role, tier = ri['role'], ri['tier']
            if model != '<missing>' and ri['arch_model'] != model:
                warnings.append('WARN:ROLE_MODEL_DRIFT agent={0} arch={1} frontmatter={2}'.format(
                    name, ri['arch_model'], model))
        else:
            warnings.append(f'WARN:ROLE_UNMAPPED agent={name} (not in Model Roles table)')
        in_o = name in orch_names
        in_p = name in plan_names
        if in_o and in_p:
            route, lst = 'both', routing_both
        elif in_o:
            route, lst = 'orch', routing_orch
        elif in_p:
            route, lst = 'plan', routing_plan
        else:
            route, lst = '-', routing_none
        lst.append(name)
        all_rows.append({'AGENT': name, 'MODEL': model, 'ROLE': role, 'TIER': tier,
                         'MODE': mode, 'ROUTE': route, 'PERMLIST': perms})
    warnings.extend(routing_warns)

    # Distributions (FULL fleet, computed before filters)
    md_groups = {}
    for r in all_rows:
        if r['MODEL'] == '<missing>':
            continue
        md_groups.setdefault(r['MODEL'], []).append(r['AGENT'])
    model_dist = sorted(
        [{'model': m, 'count': len(a), 'agents': a} for m, a in md_groups.items()],
        key=lambda d: (-d['count'], d['model']))
    role_dist = []
    for rr in role_info['roles']:
        members = [r['AGENT'] for r in all_rows if r['ROLE'] == rr['role']]
        role_dist.append({'role': rr['role'], 'tier': rr['tier'],
                          'count': len(members), 'agents': members})

    # Filters (body only)
    shown_rows = all_rows
    if args.agent:
        shown_rows = [r for r in shown_rows if r['AGENT'] == args.agent]
        if not shown_rows:
            print(f'ERROR:AGENT_NOT_FOUND name={args.agent} (token-exact match failed)')
            sys.exit(2)
    if args.role:
        shown_rows = [r for r in shown_rows if r['ROLE'] == args.role]
    if args.model:
        low = args.model.lower()
        shown_rows = [r for r in shown_rows if low in r['MODEL'].lower()]

    unmapped = sum(1 for r in all_rows if r['ROLE'] == '<unmapped>')

    gen_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

    if args.format == 'json':
        agents_json = []
        for r in all_rows:
            perm_obj = {}
            for p in r['PERMLIST']:
                eq = p.find('=')
                if eq > 0:
                    perm_obj[p[:eq]] = p[eq + 1:]
            agents_json.append({'name': r['AGENT'], 'model': r['MODEL'], 'role': r['ROLE'],
                                'tier': r['TIER'], 'mode': r['MODE'], 'routing': r['ROUTE'],
                                'permissions': perm_obj})
        doc = {
            'generated_utc': gen_utc,
            'source': args.source,
            'agents_dir': str(agents_dir),
            'agents': agents_json,
            'model_dist': [{'model': d['model'], 'count': d['count'], 'agents': d['agents']}
                           for d in model_dist],
            'role_dist': [{'role': d['role'], 'tier': d['tier'], 'count': d['count'],
                           'agents': d['agents']} for d in role_dist],
            'routing': {'orchestrator': routing_orch, 'plankestrator': routing_plan,
                        'both': routing_both, 'none': routing_none},
            'warnings': warnings,
            'summary': {
                'agents': len(all_rows), 'shown': len(shown_rows),
                'models': len(model_dist), 'roles': len(role_info['roles']),
                'orch': len(routing_orch), 'plan': len(routing_plan),
                'both': len(routing_both), 'none': len(routing_none),
                'unmapped': unmapped, 'warn': len(warnings),
            },
        }
        print(json.dumps(doc, ensure_ascii=False, indent=2))
        sys.exit(0)

    print('STATUS:REPORT_START source={0} agents={1} arch={2}'.format(
        args.source, len(all_rows), arch_name))
    for w in warnings:
        print(w)

    if args.format == 'table':
        table_rows = []
        for r in shown_rows:
            pairs = r['PERMLIST']
            perm_str = '; '.join(pairs)
            if len(pairs) > 6:
                perm_str = '; '.join(pairs[:6]) + '+{0}'.format(len(pairs) - 6)
            table_rows.append({'AGENT': r['AGENT'], 'MODEL': r['MODEL'], 'ROLE': r['ROLE'],
                               'TIER': r['TIER'], 'MODE': r['MODE'], 'ROUTE': r['ROUTE'],
                               'PERMISSIONS': perm_str})
        for line in format_agent_table(table_rows):
            print(line)
        print('== MODEL DISTRIBUTION ==')
        for d in model_dist:
            print('MODEL_DIST:{0} count={1} agents={2}'.format(
                d['model'], d['count'], ','.join(d['agents'])))
        print('== ROLE DISTRIBUTION ==')
        for d in role_dist:
            print('ROLE_DIST:{0} tier={1} count={2} agents={3}'.format(
                d['role'], d['tier'], d['count'], ','.join(d['agents'])))
    else:
        print('## Agents')
        print('')
        print('| AGENT | MODEL | ROLE | TIER | MODE | ROUTE | PERMISSIONS |')
        print('|---|---|---|---|---|---|---|')
        for r in shown_rows:
            print('| {0} | {1} | {2} | {3} | {4} | {5} | {6} |'.format(
                r['AGENT'], r['MODEL'], r['ROLE'], r['TIER'], r['MODE'], r['ROUTE'],
                '; '.join(r['PERMLIST'])))
        print('')
        print('## Model distribution')
        print('')
        print('| MODEL | COUNT | AGENTS |')
        print('|---|---|---|')
        for d in model_dist:
            print('| {0} | {1} | {2} |'.format(d['model'], d['count'], ', '.join(d['agents'])))
        print('')
        print('## Role distribution')
        print('')
        print('| ROLE | TIER | COUNT | AGENTS |')
        print('|---|---|---|---|')
        for d in role_dist:
            print('| {0} | {1} | {2} | {3} |'.format(d['role'], d['tier'], d['count'],
                                                     ', '.join(d['agents'])))
        print('')
        for d in model_dist:
            print('MODEL_DIST:{0} count={1} agents={2}'.format(
                d['model'], d['count'], ','.join(d['agents'])))
        for d in role_dist:
            print('ROLE_DIST:{0} tier={1} count={2} agents={3}'.format(
                d['role'], d['tier'], d['count'], ','.join(d['agents'])))

    print('SUMMARY:agents={0} shown={1} models={2} roles={3} orch={4} plan={5} '
          'both={6} none={7} unmapped={8} warn={9}'.format(
              len(all_rows), len(shown_rows), len(model_dist), len(role_info['roles']),
              len(routing_orch), len(routing_plan), len(routing_both), len(routing_none),
              unmapped, len(warnings)))
    print('STATUS:SUCCESS')
    sys.exit(0)


if __name__ == '__main__':
    main()
