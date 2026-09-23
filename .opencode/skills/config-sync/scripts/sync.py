#!/usr/bin/env python3
"""
sync.py - POSIX mirror of sync.ps1

SHA256 compare and sync live (~/.config/opencode) vs deploy-package vs project
mirrors. Pure byte-level copy + SHA256, no content parsing, never deletes.

Usage:
    python sync.py --plan [--group agents] [--agent worker] [--json]
    python sync.py --apply [--reverse] [--backup] [--group <name>] [--agent <name>] [--json]

Output:
    STATUS:/GROUP:/DRIFT:/MISSING:/EXTRA:/ERROR:/SYNCED:/VERIFY:/WARN:/BACKUP: lines

Exit codes:
    0 plan scan / apply without failures
    2 usage/environment error
    3 apply failures (copy/verify/backup errors)
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


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


def sha256_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().upper()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--reverse', action='store_true')
    parser.add_argument('--backup', action='store_true')
    parser.add_argument('--group', default='',
                        choices=['', 'agents', 'config', 'plugin', 'architecture',
                                 'mcp-setup', 'agents-md', 'plugin-md'])
    parser.add_argument('--agent', default='')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    if args.plan and args.apply:
        print('ERROR: --plan and --apply are mutually exclusive')
        sys.exit(2)
    if args.reverse and not args.apply:
        print('ERROR: --reverse requires --apply')
        sys.exit(2)
    if args.agent and args.group and args.group != 'agents':
        print('ERROR: --agent is only valid with --group agents')
        sys.exit(2)
    if args.agent and not args.group:
        print('WARN:narrowing to group agents (--agent given without --group)')
        args.group = 'agents'
    if not args.plan and not args.apply:
        args.plan = True

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'

    if not live_dir.is_dir():
        print(f'ERROR: live config dir not found: {live_dir}')
        sys.exit(2)
    if not (root / 'deploy-package').is_dir():
        print(f'ERROR: deploy-package not found under repo root: {root}')
        sys.exit(2)

    group_defs = [
        {'name': 'agents', 'kind': 'multi',
         'live_dir': live_dir / 'agents', 'deploy_dir': root / 'deploy-package' / 'agents'},
        {'name': 'config', 'kind': 'chain',
         'chain': [live_dir / 'opencode.json', root / 'deploy-package' / 'opencode.json']},
        {'name': 'plugin', 'kind': 'chain',
         'chain': [live_dir / 'plugins' / 'workflow-enforcement.ts',
                   root / 'plugins' / 'workflow-enforcement.ts',
                   root / 'deploy-package' / 'plugins' / 'workflow-enforcement.ts']},
        {'name': 'architecture', 'kind': 'chain',
         'chain': [root / 'ARCHITECTURE.md', root / 'opencode-config' / 'ARCHITECTURE.md',
                   root / 'deploy-package' / 'project-files' / 'ARCHITECTURE.md']},
        {'name': 'mcp-setup', 'kind': 'chain',
         'chain': [root / 'MCP_SETUP.md',
                   root / 'deploy-package' / 'project-files' / 'MCP_SETUP.md']},
        {'name': 'agents-md', 'kind': 'chain',
         'chain': [root / 'AGENTS.md', root / 'opencode-config' / 'AGENTS.md',
                   root / 'deploy-package' / 'project-files' / 'AGENTS.md',
                   live_dir / 'AGENTS.md']},
        {'name': 'plugin-md', 'kind': 'chain',
         'chain': [root / 'PLUGIN.md', root / 'opencode-config' / 'PLUGIN.md',
                   root / 'deploy-package' / 'project-files' / 'PLUGIN.md']},
    ]
    if args.group:
        group_defs = [g for g in group_defs if g['name'] == args.group]

    def path_label(p):
        p = Path(p).resolve()
        try:
            p.relative_to(live_dir.resolve())
            return 'live'
        except ValueError:
            pass
        try:
            p.relative_to((root / 'deploy-package').resolve())
            return 'deploy'
        except ValueError:
            pass
        return 'root'

    def rel_path(p):
        p = Path(p).resolve()
        try:
            return 'live:' + p.relative_to(live_dir.resolve()).as_posix()
        except ValueError:
            pass
        try:
            return p.relative_to(root.resolve()).as_posix()
        except ValueError:
            return str(p)

    def compare_chain(g):
        chain = list(g['chain'])
        src_idx = 0
        if args.reverse:
            src_idx = next((i for i, p in enumerate(chain)
                            if 'deploy-package' in p.parts), len(chain) - 1)
        findings = []
        ok = drift = missing = 0
        src = chain[src_idx]
        if not src.is_file():
            findings.append({'kind': 'error', 'origin': 'chain', 'path': rel_path(src),
                             'detail': 'source missing', 'src': None, 'dst': None})
        else:
            src_hash = sha256_file(src)
            for i, dst in enumerate(chain):
                if i == src_idx:
                    continue
                rp = rel_path(dst)
                if not dst.is_file():
                    findings.append({'kind': 'missing', 'origin': 'chain', 'path': rp,
                                     'detail': 'target absent', 'src': src, 'dst': dst})
                    missing += 1
                elif sha256_file(dst) != src_hash:
                    findings.append({'kind': 'drift', 'origin': 'chain', 'path': rp,
                                     'detail': f'src={src_hash[:8]} dst={sha256_file(dst)[:8]}',
                                     'src': src, 'dst': dst})
                    drift += 1
                else:
                    ok += 1
                    if args.json:
                        findings.append({'kind': 'ok', 'origin': 'chain', 'path': rp,
                                         'detail': 'identical', 'src': None, 'dst': None})
        return {'name': g['name'], 'total': len(chain) - 1, 'ok': ok, 'drift': drift,
                'missing': missing, 'extra': 0, 'findings': findings}

    def compare_agents(g):
        findings = []
        ok = drift = missing = extra = 0
        live_names = sorted(f.stem for f in g['live_dir'].glob('*.md')) if g['live_dir'].is_dir() else []
        deploy_names = sorted(f.stem for f in g['deploy_dir'].glob('*.md')) if g['deploy_dir'].is_dir() else []
        names = list(dict.fromkeys(live_names + deploy_names))
        if args.agent:
            names = [n for n in names if n == args.agent]
        for n in names:
            lp = g['live_dir'] / f'{n}.md'
            dp = g['deploy_dir'] / f'{n}.md'
            has_l = lp.is_file()
            has_d = dp.is_file()
            if has_l and has_d:
                h1 = sha256_file(lp)
                h2 = sha256_file(dp)
                if h1 == h2:
                    ok += 1
                    if args.json:
                        findings.append({'kind': 'ok', 'origin': 'agents',
                                         'path': f'agents/{n}.md', 'detail': 'identical',
                                         'src': None, 'dst': None})
                else:
                    # In reverse mode the deploy copy is the source of truth (restore).
                    if args.reverse:
                        findings.append({'kind': 'drift', 'origin': 'agents',
                                         'path': f'agents/{n}.md',
                                         'detail': f'src={h2[:8]} dst={h1[:8]}',
                                         'src': dp, 'dst': lp})
                    else:
                        findings.append({'kind': 'drift', 'origin': 'agents',
                                         'path': f'agents/{n}.md',
                                         'detail': f'src={h1[:8]} dst={h2[:8]}',
                                         'src': lp, 'dst': dp})
                    drift += 1
            elif has_l and not has_d:
                findings.append({'kind': 'extra', 'origin': 'agents',
                                 'path': f'agents/{n}.md', 'detail': 'live only',
                                 'src': lp, 'dst': dp})
                extra += 1
            elif has_d and not has_l:
                findings.append({'kind': 'missing', 'origin': 'agents',
                                 'path': f'agents/{n}.md', 'detail': 'live absent',
                                 'src': dp, 'dst': lp})
                missing += 1
        return {'name': g['name'], 'total': len(names), 'ok': ok, 'drift': drift,
                'missing': missing, 'extra': extra, 'findings': findings}

    group_results = []
    total_drift = total_missing = total_extra = 0

    if not args.json:
        print('STATUS:SCAN_START')

    for g in group_defs:
        res = compare_agents(g) if g['kind'] == 'multi' else compare_chain(g)
        group_results.append(res)
        total_drift += res['drift']
        total_missing += res['missing']
        total_extra += res['extra']
        if not args.json:
            print(f"GROUP:{res['name']} total={res['total']} ok={res['ok']} "
                  f"drift={res['drift']} missing={res['missing']} extra={res['extra']}")
            for f in res['findings']:
                if f['kind'] == 'ok':
                    continue
                print(f"{f['kind'].upper()}:{f['path']} {f['detail']}")

    if not args.json:
        print('WARN:out-of-scope live doc copies not synced (known drift, separate ticket): '
              'ARCHITECTURE.md, MCP_SETUP.md, PLUGIN.md, REVIEW_CONTEXT.md')

    if args.plan:
        if args.json:
            doc = {
                'groups': [{
                    'name': r['name'], 'total': r['total'], 'ok': r['ok'],
                    'drift': r['drift'], 'missing': r['missing'], 'extra': r['extra'],
                    'findings': [{'kind': f['kind'], 'path': f['path'], 'detail': f['detail']}
                                 for f in r['findings']],
                } for r in group_results],
                'summary': {'drift': total_drift, 'missing': total_missing,
                            'extra': total_extra, 'mode': 'plan'},
            }
            print(json.dumps(doc, indent=2, ensure_ascii=False))
        else:
            print(f'STATUS:PLAN_ONLY drift={total_drift} missing={total_missing} extra={total_extra}')
        sys.exit(0)

    # Apply mode
    direction = 'deploy->live' if args.reverse else 'live->deploy'
    if not args.json:
        print(f'STATUS:APPLY_START direction={direction}')

    actions = []
    failed = 0
    for res in group_results:
        for f in res['findings']:
            if f['kind'] == 'ok':
                continue
            if f['kind'] == 'drift':
                actions.append({'group': res['name'], 'src': f['src'], 'dst': f['dst'],
                                'rel': f['path'],
                                'direction': f"{path_label(f['src'])}->{path_label(f['dst'])}"})
            elif f['kind'] == 'missing':
                if f['origin'] == 'chain':
                    actions.append({'group': res['name'], 'src': f['src'], 'dst': f['dst'],
                                    'rel': f['path'],
                                    'direction': f"{path_label(f['src'])}->{path_label(f['dst'])}"})
                elif args.reverse:
                    actions.append({'group': res['name'], 'src': f['src'], 'dst': f['dst'],
                                    'rel': f['path'],
                                    'direction': f"{path_label(f['src'])}->{path_label(f['dst'])}"})
                else:
                    if not args.json:
                        print(f"ERROR:live source missing, skipped (restore with --apply --reverse): {f['path']}")
                    failed += 1
            elif f['kind'] == 'extra':
                if args.reverse:
                    if not args.json:
                        print(f"WARN:extra (live only) skipped in reverse mode (never deletes): {f['path']}")
                else:
                    actions.append({'group': res['name'], 'src': f['src'], 'dst': f['dst'],
                                    'rel': f['path'],
                                    'direction': f"{path_label(f['src'])}->{path_label(f['dst'])}"})
            elif f['kind'] == 'error':
                if not args.json:
                    print(f"ERROR:source missing, skipped: {f['path']}")
                failed += 1

    if not actions:
        if args.json:
            print(json.dumps({'summary': {'mode': 'apply', 'direction': direction,
                                          'synced': 0, 'failed': failed}}, indent=2))
        else:
            print('STATUS:NO_CHANGES')
        sys.exit(3 if failed else 0)

    if args.backup:
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_root = root / 'backup' / f'{ts}_config_sync'
        try:
            backup_root.mkdir(parents=True, exist_ok=True)
            for a in actions:
                if a['dst'].is_file():
                    gdir = backup_root / a['group']
                    gdir.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(a['dst'], gdir / a['dst'].name)
                    if not args.json:
                        print(f"BACKUP:{rel_path(a['dst'])} -> {rel_path(gdir / a['dst'].name)}")
        except OSError as e:
            print(f'ERROR:backup failed: {e}')
            sys.exit(3)

    synced = 0
    for a in actions:
        try:
            a['dst'].parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(a['src'], a['dst'])
            h1 = sha256_file(a['src'])
            h2 = sha256_file(a['dst'])
            if h1 != h2:
                print(f"ERROR:SHA256 mismatch after copy: {a['rel']}")
                failed += 1
                continue
            synced += 1
            if not args.json:
                print(f"SYNCED:{a['rel']} direction={a['direction']} sha={h1[:8]}")
                print(f"VERIFY:{a['rel']} identical")
        except OSError as e:
            print(f"ERROR:copy failed: {a['rel']} - {e}")
            failed += 1

    if args.json:
        print(json.dumps({'summary': {'mode': 'apply', 'direction': direction,
                                      'synced': synced, 'failed': failed}}, indent=2))
    else:
        print(f'STATUS:SUCCESS synced={synced} failed={failed}')
    sys.exit(3 if failed else 0)


if __name__ == '__main__':
    main()
