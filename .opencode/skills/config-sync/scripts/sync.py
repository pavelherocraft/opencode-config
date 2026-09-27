#!/usr/bin/env python3
"""
sync.py - live <-> repo config sync (5 sync pairs).

Pairs (see ARCHITECTURE.md §File Locations "Sync-механика"):
    1. agents/*.md                     live  <-> repo agents/*.md
    2. opencode.json                   live  <-> repo opencode.json
    3. plugins/workflow-enforcement.ts live  <-> repo plugins/workflow-enforcement.ts
    4. skills/git-commit/*             live  <-> repo skills/git-commit/*
    5. AGENTS.md                       live  <-> repo AGENTS.global.md

Modes:
    --save      live -> repo (DEFAULT: snapshot live before a commit)
    --restore   repo -> live (EXPLICIT emergency rollback only; prints a warning)
    --plan      drift report only (no writes; exit 3 when drift detected)

Pure byte-level copy + SHA256 — no content parsing, never deletes.

Usage:
    python sync.py [--save | --restore | --plan] [--pair <name>] [--json]

Output:
    STATUS:/PAIR:/SYNCED:/DRIFT:/MISSING:/EXTRA:/ERROR:/WARN:/SUMMARY: lines

Exit codes:
    0 ok (plan without drift; save/restore without failures)
    2 usage/environment error
    3 drift detected (--plan); copy/verify failures (--save/--restore)
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

PAIR_NAMES = ['agents', 'opencode.json', 'plugin', 'skills/git-commit', 'AGENTS.md']


def repo_root(script_dir):
    """<repo>/.opencode/skills/<skill>/scripts -> <repo>."""
    root = script_dir.resolve().parents[3]
    if (root / '.opencode' / 'skills').is_dir():
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


def pair_defs(live_dir, root):
    """5 sync pairs: (name, live_path, repo_path, kind)."""
    return [
        {'name': 'agents', 'kind': 'multi',
         'live': live_dir / 'agents', 'repo': root / 'agents',
         'pattern': '*.md'},
        {'name': 'opencode.json', 'kind': 'file',
         'live': live_dir / 'opencode.json', 'repo': root / 'opencode.json'},
        {'name': 'plugin', 'kind': 'file',
         'live': live_dir / 'plugins' / 'workflow-enforcement.ts',
         'repo': root / 'plugins' / 'workflow-enforcement.ts'},
        {'name': 'skills/git-commit', 'kind': 'multi',
         'live': live_dir / 'skills' / 'git-commit',
         'repo': root / 'skills' / 'git-commit',
         'pattern': '*'},
        {'name': 'AGENTS.md', 'kind': 'file',
         'live': live_dir / 'AGENTS.md', 'repo': root / 'AGENTS.global.md'},
    ]


def multi_rel_files(d, pattern):
    """Recursive relative posix paths of files under d matching pattern (top level for *.md)."""
    if not d.is_dir():
        return []
    if pattern == '*.md':
        return sorted(p.relative_to(d).as_posix() for p in d.glob(pattern) if p.is_file())
    return sorted(p.relative_to(d).as_posix() for p in d.rglob(pattern) if p.is_file())


def compare_pair(pair, src_dir_side):
    """Compare src-side files vs dst-side. src_dir_side: 'live' or 'repo'.
    Returns findings list; a finding is copyable when it has src+dst set."""
    name = pair['name']
    if pair['kind'] == 'multi':
        src_files = multi_rel_files(pair[src_dir_side], pair.get('pattern', '*'))
        dst_side = 'repo' if src_dir_side == 'live' else 'live'
        dst_files = multi_rel_files(pair[dst_side], pair.get('pattern', '*'))
        src_root, dst_root = pair[src_dir_side], pair[dst_side]
        findings = []
        for rel in sorted(set(src_files) | set(dst_files)):
            sp, dp = src_root / rel, dst_root / rel
            label = f'{name}/{rel}' if name != 'AGENTS.md' else name
            in_src, in_dst = rel in src_files, rel in dst_files
            if in_src and in_dst:
                h1, h2 = sha256_file(sp), sha256_file(dp)
                if h1 == h2:
                    findings.append({'kind': 'ok', 'pair': name, 'path': label})
                else:
                    findings.append({'kind': 'drift', 'pair': name, 'path': label,
                                     'detail': f'{src_dir_side}={h1[:8]} {dst_side}={h2[:8]}',
                                     'src': sp, 'dst': dp})
            elif in_src:
                findings.append({'kind': 'missing', 'pair': name, 'path': label,
                                 'detail': f'absent on {dst_side}',
                                 'src': sp, 'dst': dp})
            else:
                findings.append({'kind': 'extra', 'pair': name, 'path': label,
                                 'detail': f'exists on {dst_side} only (never deleted)'})
        return findings
    # file pair
    src_side = src_dir_side
    dst_side = 'repo' if src_dir_side == 'live' else 'live'
    sp, dp = pair[src_side], pair[dst_side]
    if not sp.is_file():
        return [{'kind': 'error', 'pair': name, 'path': name,
                 'detail': f'{src_side} source missing'}]
    h1 = sha256_file(sp)
    if not dp.is_file():
        return [{'kind': 'missing', 'pair': name, 'path': name,
                 'detail': f'absent on {dst_side}', 'src': sp, 'dst': dp}]
    h2 = sha256_file(dp)
    if h1 == h2:
        return [{'kind': 'ok', 'pair': name, 'path': name}]
    return [{'kind': 'drift', 'pair': name, 'path': name,
             'detail': f'{src_side}={h1[:8]} {dst_side}={h2[:8]}', 'src': sp, 'dst': dp}]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--save', action='store_true')
    parser.add_argument('--restore', action='store_true')
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--pair', default='', choices=[''] + PAIR_NAMES)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()

    modes = [m for m in (args.save, args.restore, args.plan) if m]
    if len(modes) > 1:
        print('ERROR: --save, --restore and --plan are mutually exclusive')
        sys.exit(2)
    if not modes:
        args.save = True  # default mode: save (live -> repo)

    skill_dir = Path(__file__).resolve().parent
    root = repo_root(skill_dir)
    live_dir = Path.home() / '.config' / 'opencode'

    if not live_dir.is_dir():
        print(f'ERROR: live config dir not found: {live_dir}')
        sys.exit(2)
    if not (root / '.opencode').is_dir():
        print(f'ERROR: repo root not found (no .opencode/ under it): {root}')
        sys.exit(2)

    pairs = pair_defs(live_dir, root)
    if args.pair:
        pairs = [p for p in pairs if p['name'] == args.pair]

    src_side = 'repo' if args.restore else 'live'
    dst_side = 'live' if args.restore else 'repo'

    if not args.json:
        print('STATUS:SCAN_START')
        if args.restore:
            print('WARN:RESTORE mode — repo -> live OVERWRITES the live config '
                  '(explicit emergency rollback). Recommended: backup-snapshot first.')

    all_findings = []
    for p in pairs:
        findings = compare_pair(p, src_side)
        all_findings.append((p['name'], findings))
        if not args.json:
            ok = sum(1 for f in findings if f['kind'] == 'ok')
            drift = sum(1 for f in findings if f['kind'] == 'drift')
            missing = sum(1 for f in findings if f['kind'] == 'missing')
            extra = sum(1 for f in findings if f['kind'] == 'extra')
            print(f"PAIR:{p['name']} ok={ok} drift={drift} missing={missing} extra={extra}")
            for f in findings:
                if f['kind'] == 'ok':
                    continue
                token = f['kind'].upper()
                hint = ' (use --save)' if f['kind'] in ('drift', 'missing') and args.plan else ''
                print(f"{token}:{f['path']} {f['detail']}{hint}")

    total_drift = sum(1 for _, fs in all_findings for f in fs if f['kind'] == 'drift')
    total_missing = sum(1 for _, fs in all_findings for f in fs if f['kind'] == 'missing')
    total_extra = sum(1 for _, fs in all_findings for f in fs if f['kind'] == 'extra')
    total_errors = sum(1 for _, fs in all_findings for f in fs if f['kind'] == 'error')

    # --- plan: report only ---------------------------------------------------
    if args.plan:
        if args.json:
            doc = {
                'mode': 'plan',
                'pairs': [{'name': n,
                           'findings': [{'kind': f['kind'], 'path': f['path'],
                                         'detail': f.get('detail', '')} for f in fs]}
                          for n, fs in all_findings],
                'summary': {'drift': total_drift, 'missing': total_missing,
                            'extra': total_extra, 'errors': total_errors},
            }
            print(json.dumps(doc, indent=2, ensure_ascii=False))
        else:
            print(f'SUMMARY:mode=plan drift={total_drift} missing={total_missing} '
                  f'extra={total_extra} errors={total_errors}')
        if total_drift or total_missing or total_errors:
            print('STATUS:DRIFT_DETECTED (fix with: config-sync --save)')
            sys.exit(3)
        print('STATUS:IN_SYNC')
        sys.exit(0)

    # --- save / restore: copy src -> dst for drift+missing --------------------
    mode = 'restore' if args.restore else 'save'
    direction = 'repo->live' if args.restore else 'live->repo'
    if not args.json:
        print(f'STATUS:APPLY_START mode={mode} direction={direction}')

    synced = 0
    failed = total_errors
    for _, fs in all_findings:
        for f in fs:
            if f['kind'] not in ('drift', 'missing'):
                continue
            try:
                f['dst'].parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f['src'], f['dst'])
                if sha256_file(f['src']) != sha256_file(f['dst']):
                    print(f"ERROR:SHA256 mismatch after copy: {f['path']}")
                    failed += 1
                    continue
                synced += 1
                if not args.json:
                    h = sha256_file(f['src'])
                    print(f"SYNCED:{f['path']} direction={direction} sha={h[:8]}")
            except OSError as e:
                print(f"ERROR:copy failed: {f['path']} - {e}")
                failed += 1

    if args.json:
        print(json.dumps({'summary': {'mode': mode, 'direction': direction,
                                      'synced': synced, 'failed': failed,
                                      'extra_reported': total_extra}},
                         indent=2, ensure_ascii=False))
    else:
        print(f'SUMMARY:mode={mode} synced={synced} failed={failed} extra_reported={total_extra}')
    if failed:
        print(f'STATUS:FAILED failed={failed}')
        sys.exit(3)
    print('STATUS:SUCCESS' if synced else 'STATUS:NO_CHANGES')
    sys.exit(0)


if __name__ == '__main__':
    main()
